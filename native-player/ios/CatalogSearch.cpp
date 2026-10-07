// SPDX-License-Identifier: GPL-3.0-or-later
#include "CatalogSearch.h"
#include "AccessKeyFetcher.h"
#include "TrackReference.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <stdexcept>
#include <fstream>
#include <ctime>
#include <sys/stat.h>
namespace {
using JSON = nlohmann::json;
// Default backend: spclient context-resolve with a spotify:search: URI, which the
// session's login5 token already authorizes (the same token playback uses).
// Creating this marker switches back to the public Web API for comparison.
const char* kWebApiMarker = "/var/mobile/Documents/cspot-catalog-webapi";
const char* kContextResolve = "context-resolve";
const char* kWebApi = "web-api";
std::string message(const char* text) {
  return JSON{{"message", text}, {"tracks", JSON::array()}}.dump();
}
std::string percentEncode(const std::string& input, bool plusForSpace = false) {
  const char* digits = "0123456789ABCDEF";
  std::string output;
  for (unsigned char byte : input) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || byte == '-' || byte == '_' || byte == '.' || byte == '~')
      output += static_cast<char>(byte);
    else if (byte == ' ' && plusForSpace) output += '+';
    else { output += '%'; output += digits[byte >> 4]; output += digits[byte & 15]; }
  }
  return output;
}
std::string field(const JSON& object, const char* key, size_t limit = 1024) {
  auto found = object.find(key);
  if (found == object.end() || !found->is_string()) return {};
  auto value = found->get<std::string>();
  return value.size() <= limit ? value : std::string();
}
bool validID(const std::string& id) {
  return id.size() == 22 && id.find_first_not_of(
      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") == std::string::npos;
}
std::string hexGID(const std::string& uri) {
  cspot::TrackReference reference;
  reference.uri = uri;
  reference.decodeURI();
  // The big-number decoder drops leading zero bytes; a GID is always 16 bytes.
  if (reference.gid.empty() || reference.gid.size() > 16) return {};
  std::vector<uint8_t> gid(16 - reference.gid.size(), 0);
  gid.insert(gid.end(), reference.gid.begin(), reference.gid.end());
  const char* digits = "0123456789abcdef";
  std::string hex;
  for (uint8_t byte : gid) { hex += digits[byte >> 4]; hex += digits[byte & 15]; }
  return hex;
}
// Key names only (no values) so a response shape can be diagnosed without logging content.
std::string keyNames(const JSON& object) {
  std::string names;
  if (!object.is_object()) return names;
  for (auto it = object.begin(); it != object.end(); ++it) {
    if (names.size() > 200) { names += ",..."; break; }
    if (!names.empty()) names += ',';
    names += it.key().substr(0, 32);
  }
  return names;
}
JSON trackEntry(const std::string& uri, const std::string& id, const std::string& title,
                const std::string& artist, const std::string& album) {
  return {{"uri", uri}, {"title", title.empty() ? "Untitled" : title},
          {"artist", artist.empty() ? "Unknown artist" : artist}, {"album", album},
          {"url", "https://open.spotify.com/track/" + id}};
}
}
namespace ipad_player {
CatalogSearch::CatalogSearch(std::shared_ptr<cspot::Context> context, std::string path)
    : tokenFetcher(cspot::AccessKeyFetcher::forContext(context)), policyPath(std::move(path)) {
  struct stat marker;
  backend = stat(kWebApiMarker, &marker) == 0 ? kWebApi : kContextResolve;
  try {
    std::ifstream input(policyPath);
    if (input) {
      JSON policy; input >> policy;
      const auto saved = policy.value("backend", std::string(kWebApi));
      if (saved == backend) {
        retryAt = policy.value("retry_at", 0LL);
        quotaBlocked = policy.value("quota_blocked", false);
        if (retryAt < 0) retryAt = 0;
        std::fprintf(stderr, "CATALOG: restored cooldown=%d quota_blocked=%d backend=%s\n",
            retryAt > static_cast<long long>(std::time(nullptr)), quotaBlocked, backend.c_str());
      } else {
        // A restriction recorded against another backend says nothing about this one.
        std::fprintf(stderr, "CATALOG: ignoring cooldown recorded for backend=%s; now using %s\n",
            saved.c_str(), backend.c_str());
      }
    }
  } catch (...) { std::fprintf(stderr, "CATALOG: cooldown state unreadable\n"); }
  std::fprintf(stderr, "CATALOG: backend=%s\n", backend.c_str());
}
CatalogSearch::~CatalogSearch() = default;
void CatalogSearch::savePolicy() {
  // Store timing only. No account credentials, queries, tokens or response body.
  const auto temporary = policyPath + ".tmp";
  std::ofstream output(temporary, std::ios::trunc);
  output << JSON{{"retry_at", retryAt}, {"quota_blocked", quotaBlocked}, {"backend", backend}}.dump();
  output.close();
  if (!output || std::rename(temporary.c_str(), policyPath.c_str()) != 0)
    std::fprintf(stderr, "CATALOG: could not persist cooldown\n");
  else chmod(policyPath.c_str(), 0600);
}
std::string CatalogSearch::cooldownMessage() {
  if (quotaBlocked) return JSON{{"message", "Spotify reported a restriction with no safe retry time. Search is paused; see the catalog log."}, {"tracks", JSON::array()}, {"quota_blocked", true}}.dump();
  const auto remaining = std::max(0LL, retryAt - static_cast<long long>(std::time(nullptr)));
  const std::string text = "Spotify limited search. Try again in " + std::to_string(remaining) + " seconds.";
  return JSON{{"message", text}, {"tracks", JSON::array()}, {"retry_at", retryAt}}.dump();
}
std::string CatalogSearch::spclientHost() {
  if (!spclient.empty()) return spclient;
  try {
    auto response = bell::HTTPClient::get("https://apresolve.spotify.com/?type=spclient");
    if (response->statusCode() == 200 && response->contentLength() <= 16384) {
      const auto bytes = response->bytes();
      auto document = JSON::parse(bytes.begin(), bytes.end());
      if (document.is_object() && document.count("spclient") && document["spclient"].is_array() &&
          !document["spclient"].empty() && document["spclient"][0].is_string()) {
        auto host = document["spclient"][0].get<std::string>();
        if (host.size() <= 128 && host.find_first_not_of(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:") == std::string::npos)
          spclient = host;
      }
    }
  } catch (...) { /* fall back below */ }
  if (spclient.empty()) spclient = "spclient.wg.spotify.com:443";
  std::fprintf(stderr, "CATALOG: spclient host=%s\n", spclient.c_str());
  return spclient;
}
std::string CatalogSearch::search(const std::string& query) {
  try {
    std::lock_guard<std::mutex> lock(mutex);
    if (query.empty() || query.size() > 256) return message("Enter a song or artist name (maximum 256 UTF-8 bytes).");
    const auto now = std::chrono::steady_clock::now();
    auto found = cache.find(query);
    if (found != cache.end() && now - found->second.at < std::chrono::minutes(10)) {
      std::fprintf(stderr, "CATALOG: cache hit; no network request\n");
      return found->second.json;
    }
    if (quotaBlocked || static_cast<long long>(std::time(nullptr)) < retryAt) return cooldownMessage();
    if (now < nextAttempt) return message("Please wait before searching again.");
    ++failures;
    const unsigned delay = std::min(300u, 5u << std::min(failures - 1, 6u));
    nextAttempt = now + std::chrono::seconds(delay);
    const auto token = tokenFetcher->getAccessKey();
    if (token.empty()) {
      std::fprintf(stderr, "CATALOG: session token unavailable; no search request\n");
      return message(tokenFetcher->error().c_str());
    }
    std::fprintf(stderr, "CATALOG: sending search request backend=%s epoch_seconds=%lld\n",
        backend.c_str(), static_cast<long long>(std::time(nullptr)));
    return backend == kWebApi ? searchWebApi(query, token, delay) : searchContextResolve(query, token, delay);
  } catch (...) {
    std::fprintf(stderr, "CATALOG: request or response failure\n");
    return "{\"message\":\"Could not reach Spotify search. Please try later.\",\"tracks\":[]}";
  }
}
std::string CatalogSearch::rateLimited(const std::unique_ptr<bell::HTTPClient::Response>& response, unsigned delay) {
  auto retry = response->header("retry-after");
  std::string value(retry.begin(), retry.end());
  long long seconds = std::max(60u, delay);
  bool validRetry = false;
  if (!value.empty() && value.size() <= 10 && value.find_first_not_of("0123456789") == std::string::npos) {
    auto parsed = std::stoull(value);
    if (parsed <= 2147483647ULL) { seconds = std::max(1ULL, parsed); validRetry = true; }
    else quotaBlocked = true; // Refuse to guess a shorter wait.
  }
  if (!value.empty() && value.size() > 10 && value.find_first_not_of("0123456789") == std::string::npos)
    quotaBlocked = true;
  std::string reason = "UNKNOWN";
  try {
    if (response->contentLength() <= 16384) {
      auto errorBytes = response->bytes();
      if (errorBytes.size() <= 16384) {
        auto errorBody = JSON::parse(errorBytes.begin(), errorBytes.end());
        std::string raw;
        if (errorBody.is_object()) {
          raw = field(errorBody, "reason", 64);
          if (raw.empty() && errorBody.count("error") && errorBody["error"].is_object()) raw = field(errorBody["error"], "reason", 64);
        }
        if (raw == "QUOTA_EXCEEDED") { reason = raw; if (!validRetry) quotaBlocked = true; }
        else if (raw == "RATE_LIMITED" || raw == "RATE_LIMIT_EXCEEDED") reason = raw;
      }
    }
  } catch (...) { /* Keep status and header diagnostics even if the error body is invalid. */ }
  retryAt = static_cast<long long>(std::time(nullptr)) + seconds;
  std::fprintf(stderr, "CATALOG: HTTP=429 reason=%s retry_seconds=%lld source=%s blocked=%d backend=%s\n",
      reason.c_str(), seconds, validRetry ? "server" : "fallback", quotaBlocked, backend.c_str());
  savePolicy();
  return cooldownMessage();
}
std::string CatalogSearch::finish(const std::string& query, const std::string& result) {
  const auto now = std::chrono::steady_clock::now();
  if (cache.size() >= 8 && !cache.count(query)) cache.erase(cache.begin());
  cache[query] = Cached{now, result};
  failures = 0; retryAt = 0;
  nextAttempt = now + std::chrono::seconds(5);
  return result;
}
std::string CatalogSearch::searchContextResolve(const std::string& query, const std::string& token, unsigned delay) {
  const auto host = spclientHost();
  auto response = bell::HTTPClient::get(
      "https://" + host + "/context-resolve/v1/spotify:search:" + percentEncode(query, true),
      {{"Authorization", "Bearer " + token}, {"Accept", "application/json"}});
  const int status = response->statusCode();
  std::fprintf(stderr, "CATALOG: HTTP=%d epoch_seconds=%lld\n", status, static_cast<long long>(std::time(nullptr)));
  if (status == 429) return rateLimited(response, delay);
  if (status == 401) return message("Spotify rejected the session token for search.");
  if (status == 403) return message("Spotify denied search for this session.");
  if (status != 200) return message("Spotify search is unavailable. Please try later.");
  if (response->contentLength() > 262144) return message("Catalog response is too large.");
  const auto bytes = response->bytes();
  if (bytes.size() > 262144) return message("Catalog response is too large.");
  auto document = JSON::parse(bytes.begin(), bytes.end());
  if (!document.is_object() || !document.count("pages") || !document["pages"].is_array() || document["pages"].empty())
    { std::fprintf(stderr, "CATALOG: context keys=%s\n", keyNames(document).c_str()); return message("Spotify returned no results page."); }
  const auto& page = document["pages"][0];
  if (!page.is_object() || !page.count("tracks") || !page["tracks"].is_array())
    { std::fprintf(stderr, "CATALOG: context page keys=%s\n", keyNames(page).c_str()); return message("Spotify returned an invalid track list."); }
  std::vector<std::string> uris;
  for (const auto& item : page["tracks"]) {
    if (uris.size() >= 10) break;
    if (!item.is_object()) continue;
    const auto uri = field(item, "uri", 36);
    if (uri.size() == 36 && uri.compare(0, 14, "spotify:track:") == 0 && validID(uri.substr(14))) uris.push_back(uri);
    if (uris.size() == 1) {
      std::fprintf(stderr, "CATALOG: context track keys=%s\n", keyNames(item).c_str());
      if (item.count("metadata")) std::fprintf(stderr, "CATALOG: context track metadata keys=%s\n", keyNames(item["metadata"]).c_str());
    }
  }
  std::fprintf(stderr, "CATALOG: context tracks=%lu of %lu\n", static_cast<unsigned long>(uris.size()),
      static_cast<unsigned long>(page["tracks"].size()));
  // Hydrate names through spclient metadata, one request per track. Failures keep the
  // URI so playback can still be tested; the first failure is logged with its status.
  auto tracks = JSON::array();
  bool metadataFailureLogged = false;
  for (const auto& uri : uris) {
    const auto id = uri.substr(14);
    std::string title, artist, album;
    const auto hex = hexGID(uri);
    try {
      if (hex.empty()) throw std::runtime_error("gid");
      auto meta = bell::HTTPClient::get("https://" + host + "/metadata/4/track/" + hex + "?market=from_token",
          {{"Authorization", "Bearer " + token}, {"Accept", "application/json"}});
      if (meta->statusCode() != 200 || meta->contentLength() > 65536) {
        if (!metadataFailureLogged) { std::fprintf(stderr, "CATALOG: metadata HTTP=%d\n", meta->statusCode()); metadataFailureLogged = true; }
      } else {
        const auto body = meta->bytes();
        auto info = JSON::parse(body.begin(), body.end());
        if (info.is_object()) {
          title = field(info, "name");
          if (info.count("artist") && info["artist"].is_array()) {
            size_t count = 0;
            for (const auto& person : info["artist"]) {
              if (++count > 3) break;
              auto name = field(person, "name", 256);
              if (!name.empty()) { if (!artist.empty()) artist += ", "; artist += name; }
            }
          }
          if (info.count("album") && info["album"].is_object()) album = field(info["album"], "name");
          if (title.empty() && !metadataFailureLogged) { std::fprintf(stderr, "CATALOG: metadata keys=%s\n", keyNames(info).c_str()); metadataFailureLogged = true; }
        }
      }
    } catch (...) {
      if (!metadataFailureLogged) { std::fprintf(stderr, "CATALOG: metadata request failed\n"); metadataFailureLogged = true; }
    }
    if (title.empty()) title = "Track " + id.substr(0, 6);
    tracks.push_back(trackEntry(uri, id, title, artist, album));
  }
  std::fprintf(stderr, "CATALOG: tracks=%lu\n", static_cast<unsigned long>(tracks.size()));
  return finish(query, JSON{{"message", tracks.empty() ? "No tracks found. Try another search." :
      "Tap a track to play on this iPad. The info button opens Spotify."}, {"tracks", tracks}}.dump());
}
std::string CatalogSearch::searchWebApi(const std::string& query, const std::string& token, unsigned delay) {
  auto response = bell::HTTPClient::get(
      "https://api.spotify.com/v1/search?type=track&limit=10&q=" + percentEncode(query),
      {{"Authorization", "Bearer " + token}, {"Accept", "application/json"}});
  const int status = response->statusCode();
  std::fprintf(stderr, "CATALOG: HTTP=%d epoch_seconds=%lld\n", status, static_cast<long long>(std::time(nullptr)));
  if (status == 429) return rateLimited(response, delay);
  if (status == 401) return message("Spotify rejected the catalog token. Playback login does not prove catalog access.");
  if (status == 403) return message("Spotify denied catalog access for this session. Catalog authorization needs attention.");
  if (status != 200) return message("Spotify search is unavailable. Please try later.");
  if (response->contentLength() > 131072) return message("Catalog response is too large.");
  const auto bytes = response->bytes();
  if (bytes.size() > 131072) return message("Catalog response is too large.");
  auto document = JSON::parse(bytes.begin(), bytes.end());
  if (!document.is_object() || !document.count("tracks") || !document["tracks"].is_object() ||
      !document["tracks"].count("items") || !document["tracks"]["items"].is_array())
    return message("Spotify returned an invalid track list.");
  auto tracks = JSON::array();
  for (const auto& item : document["tracks"]["items"]) {
    if (tracks.size() >= 10) break;
    if (!item.is_object()) continue;
    const auto id = field(item, "id", 22);
    const auto uri = field(item, "uri", 36);
    if (!validID(id) || uri != "spotify:track:" + id) continue;
    if (item.count("is_playable") && item["is_playable"].is_boolean() && !item["is_playable"].get<bool>()) continue;
    std::string artist;
    if (item.count("artists") && item["artists"].is_array()) {
      size_t count = 0;
      for (const auto& person : item["artists"]) {
        if (++count > 3) break;
        auto name = field(person, "name", 256);
        if (!name.empty()) { if (!artist.empty()) artist += ", "; artist += name; }
      }
    }
    std::string album;
    if (item.count("album") && item["album"].is_object()) album = field(item["album"], "name");
    tracks.push_back(trackEntry(uri, id, field(item, "name"), artist, album));
  }
  std::fprintf(stderr, "CATALOG: tracks=%lu\n", static_cast<unsigned long>(tracks.size()));
  return finish(query, JSON{{"message", tracks.empty() ? "No tracks found. Try another search." :
      "Tap a track to play on this iPad. The info button opens Spotify."}, {"tracks", tracks}}.dump());
}
}
