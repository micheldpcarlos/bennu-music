// SPDX-License-Identifier: GPL-3.0-or-later
#include "CatalogSearch.h"
#include "AccessKeyFetcher.h"
#include "HTTPClient.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <fstream>
#include <ctime>
#include <sys/stat.h>
namespace {
using JSON = nlohmann::json;
std::string message(const char* text) {
  return JSON{{"message", text}, {"tracks", JSON::array()}}.dump();
}
std::string percentEncode(const std::string& input) {
  const char* digits = "0123456789ABCDEF";
  std::string output;
  for (unsigned char byte : input) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || byte == '-' || byte == '_' || byte == '.' || byte == '~')
      output += static_cast<char>(byte);
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
}
namespace ipad_player {
CatalogSearch::CatalogSearch(std::shared_ptr<cspot::Context> context, std::string path)
    : tokenFetcher(cspot::AccessKeyFetcher::forContext(context)), policyPath(std::move(path)) {
  try {
    std::ifstream input(policyPath);
    if (input) {
      JSON policy; input >> policy;
      retryAt = policy.value("retry_at", 0LL);
      quotaBlocked = policy.value("quota_blocked", false);
      if (retryAt < 0) retryAt = 0;
      std::fprintf(stderr, "CATALOG: restored cooldown=%d quota_blocked=%d\n",
          retryAt > static_cast<long long>(std::time(nullptr)), quotaBlocked);
    }
  } catch (...) { std::fprintf(stderr, "CATALOG: cooldown state unreadable\n"); }
}
CatalogSearch::~CatalogSearch() = default;
void CatalogSearch::savePolicy() {
  // Store timing only. No account credentials, queries, tokens or response body.
  const auto temporary = policyPath + ".tmp";
  std::ofstream output(temporary, std::ios::trunc);
  output << JSON{{"retry_at", retryAt}, {"quota_blocked", quotaBlocked}}.dump();
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
    std::fprintf(stderr, "CATALOG: sending search request epoch_seconds=%lld\n", static_cast<long long>(std::time(nullptr)));
    auto response = bell::HTTPClient::get(
        "https://api.spotify.com/v1/search?type=track&limit=10&q=" + percentEncode(query),
        {{"Authorization", "Bearer " + token}, {"Accept", "application/json"}});
    const int status = response->statusCode();
    std::fprintf(stderr, "CATALOG: HTTP=%d epoch_seconds=%lld\n", status, static_cast<long long>(std::time(nullptr)));
    if (status == 429) {
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
      std::fprintf(stderr, "CATALOG: HTTP=429 reason=%s retry_seconds=%lld source=%s blocked=%d\n",
          reason.c_str(), seconds, validRetry ? "server" : "fallback", quotaBlocked);
      savePolicy();
      return cooldownMessage();
    }
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
      const auto title = field(item, "name");
      std::string album;
      if (item.count("album") && item["album"].is_object()) album = field(item["album"], "name");
      tracks.push_back({{"uri", uri}, {"title", title.empty() ? "Untitled" : title},
          {"artist", artist.empty() ? "Unknown artist" : artist}, {"album", album},
          {"url", "https://open.spotify.com/track/" + id}});
    }
    std::fprintf(stderr, "CATALOG: tracks=%lu\n", static_cast<unsigned long>(tracks.size()));
    auto result = JSON{{"message", tracks.empty() ? "No tracks found. Try another search." :
        "Tap a track to play on this iPad. The info button opens Spotify."}, {"tracks", tracks}}.dump();
    if (cache.size() >= 8 && !cache.count(query)) cache.erase(cache.begin());
    cache[query] = Cached{now, result};
    failures = 0; retryAt = 0;
    nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    return result;
  } catch (...) {
    std::fprintf(stderr, "CATALOG: request or response failure\n");
    return "{\"message\":\"Could not reach Spotify search. Please try later.\",\"tracks\":[]}";
  }
}
}
