// SPDX-License-Identifier: GPL-3.0-or-later
#include "Pathfinder.h"
#include "PlayerBridge.h"
#include "SpclientClient.h"
#include "Catalog.h"
#include "AccessKeyFetcher.h"
#include "CSpotContext.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <CoreFoundation/CoreFoundation.h>

namespace ipad_player {
using JSON = nlohmann::json;
namespace {
// Compiled-in fallbacks, extracted from the web player on 2026-10-08. The runtime sources take
// precedence; these only matter on a device that has never been online with this build.
const std::map<std::string, std::string> kDefaultHashes{
    {"searchDesktop", "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03"},
    {"home", "5fb7da7a03ee2776c0670856609cb85a189a3cecc36cc160b91cde79063b9cf1"},
    {"libraryV3", "390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455"},
};
const char* kStatePath = "/var/mobile/Documents/bennu-pathfinder.json";
const char* kDebugMarker = "/var/mobile/Documents/bennu-debug";
const char* kRemoteConfig = "https://raw.githubusercontent.com/micheldpcarlos/bennu-music/main/config/pathfinder.json";
const char* kWebPlayer = "https://open.spotify.com/";
const char* kCdn = "https://open.spotifycdn.com/cdn/build/web-player/";
const char* kUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const char* kClientId = "65b708073fc0480ea92a077233ca87bd";   // the web player's id, the one the session token belongs to
const char* kAppVersion = "1.2.80.0";

long long now() { return static_cast<long long>(std::time(nullptr)); }
std::string encode(const std::string& in) {
  static const char* hex = "0123456789ABCDEF"; std::string out;
  for (unsigned char c : in) {
    if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') out += c;
    else { out += '%'; out += hex[c >> 4]; out += hex[c & 15]; }
  }
  return out;
}
bool isHex64(const std::string& s) { if (s.size() != 64) return false; for (char c : s) if (!isxdigit((unsigned char)c)) return false; return true; }
bool debugEnabled() { return std::ifstream(kDebugMarker).good(); }
void dump(const std::string& name, const std::string& text) {
  std::ofstream f("/var/mobile/Documents/bennu-pathfinder-" + name + ".json", std::ios::trunc); f << text.substr(0, 400000);
}
// Minimal protobuf writer/reader for the client-token handshake.
std::string varint(uint64_t n) { std::string o; do { unsigned char b = n & 0x7f; n >>= 7; if (n) b |= 0x80; o += (char)b; } while (n); return o; }
std::string field(unsigned number, const std::string& data) { return varint((number << 3) | 2) + varint(data.size()) + data; }
std::string varintField(unsigned number, uint64_t n) { return varint(number << 3) + varint(n); }
bool readVarint(const std::string& d, size_t& i, uint64_t& v) { v = 0; int shift = 0; while (i < d.size()) { unsigned char b = d[i++]; v |= (uint64_t)(b & 0x7f) << shift; if (!(b & 0x80)) return true; shift += 7; if (shift > 63) return false; } return false; }
template <class F> void each(const std::string& d, F fn) {
  size_t i = 0;
  while (i < d.size()) {
    uint64_t key; if (!readVarint(d, i, key)) return;
    unsigned number = (unsigned)(key >> 3), type = key & 7; uint64_t v = 0; std::string bytes;
    if (type == 0) { if (!readVarint(d, i, v)) return; }
    else if (type == 2) { uint64_t len; if (!readVarint(d, i, len) || i + len > d.size()) return; bytes = d.substr(i, len); i += len; }
    else if (type == 1) { if (i + 8 > d.size()) return; i += 8; }
    else if (type == 5) { if (i + 4 > d.size()) return; i += 4; }
    else return;
    fn(number, v, bytes);
  }
}
// Safe navigation: these responses are nested five levels deep and partly optional.
const JSON* at(const JSON* j, const char* key) { if (!j || !j->is_object()) return nullptr; auto it = j->find(key); return it == j->end() ? nullptr : &*it; }
std::string text(const JSON* j) { return j && j->is_string() ? j->get<std::string>() : std::string(); }
int number(const JSON* j) { return j && j->is_number() ? j->get<int>() : 0; }
std::string firstImage(const JSON* sources, int preferredWidth) {
  if (!sources || !sources->is_array() || sources->empty()) return {};
  std::string best; int bestWidth = 1 << 30;
  for (const auto& s : *sources) {
    auto url = text(at(&s, "url")); if (url.empty()) continue;
    int w = number(at(&s, "width"));
    if (w >= preferredWidth && w < bestWidth) { best = url; bestWidth = w; }
  }
  if (best.empty()) best = text(at(&(*sources)[sources->size() - 1], "url"));
  // User playlist covers come from image-cdn-*.spotifycdn.com in formats iOS 9 cannot decode;
  // the catalog knows the i.scdn.co JPEG form of the same image id.
  auto canonical = canonicalImageURL(best);
  return canonical.empty() ? best : canonical;
}
const JSON* items(const JSON* section) { auto i = at(section, "items"); return i && i->is_array() ? i : nullptr; }
// Image for any entity shape the service uses: coverArt.sources, images.items[0].sources, visuals.avatarImage.sources.
std::string entityImage(const JSON* data, int width) {
  if (auto s = at(at(data, "coverArt"), "sources")) return firstImage(s, width);
  if (auto s = at(at(data, "image"), "sources")) return firstImage(s, width);        // PseudoPlaylist (Liked Songs)
  if (auto imgs = items(at(data, "images"))) if (!imgs->empty()) return firstImage(at(&(*imgs)[0], "sources"), width);
  if (auto s = at(at(at(data, "visuals"), "avatarImage"), "sources")) return firstImage(s, width);
  return {};
}
std::pair<std::string, JSON> artistNames(const JSON* artists) {
  std::string joined; JSON list = JSON::array();
  if (auto arr = items(artists)) for (const auto& a : *arr) {
    auto name = text(at(at(&a, "profile"), "name")); auto uri = text(at(&a, "uri"));
    if (name.empty()) continue;
    joined += (joined.empty() ? "" : ", ") + name; list.push_back({{"name", name}, {"uri", uri}});
  }
  return {joined, list};
}
// One entity (album, playlist, artist, track, collection) -> the UI's row/card shape, or null when unknown.
JSON entity(const JSON* data) {
  auto uri = text(at(data, "uri")); if (uri.size() < 10) return nullptr;
  auto second = uri.find(':', 8); if (second == std::string::npos) return nullptr;
  std::string type = uri.substr(8, second - 8);   // spotify:<type>:...
  auto typeName = text(at(data, "__typename"));
  JSON out{{"uri", uri}, {"artwork", entityImage(data, 300)}};
  if (type == "playlist") {
    out["type"] = "playlist"; out["name"] = text(at(data, "name"));
    auto owner = text(at(at(at(data, "ownerV2"), "data"), "name"));
    out["subtitle"] = owner.empty() ? "Playlist" : "Playlist • " + owner;
  } else if (type == "album") {
    out["type"] = "album"; out["name"] = text(at(data, "name"));
    auto names = artistNames(at(data, "artists")); out["artist"] = names.first;
    out["subtitle"] = names.first.empty() ? "Album" : "Album • " + names.first;
  } else if (type == "artist") {
    out["type"] = "artist"; out["name"] = text(at(at(data, "profile"), "name")); out["subtitle"] = "Artist";
  } else if (type == "track") {
    out["type"] = "track"; out["name"] = text(at(data, "name"));
    auto names = artistNames(at(data, "artists")); out["artist"] = names.first; out["subtitle"] = names.first;
    if (out["artwork"].get<std::string>().empty()) out["artwork"] = entityImage(at(data, "albumOfTrack"), 300);
  } else if (uri == "spotify:collection:tracks" || (type == "user" && uri.find(":collection") != std::string::npos) || typeName == "PseudoPlaylist") {
    if (uri != "spotify:collection:tracks" && typeName == "PseudoPlaylist" && uri.find("tracks") == std::string::npos) return nullptr;   // Your Episodes etc.
    out["uri"] = "spotify:user:me:collection"; out["type"] = "collection";
    out["name"] = text(at(data, "name")); if (out["name"].get<std::string>().empty()) out["name"] = "Liked Songs";
    int count = number(at(data, "count")); out["subtitle"] = count ? "Playlist • " + std::to_string(count) + " songs" : "Playlist";
  } else {
    return nullptr;   // shows, episodes, audiobooks, users, folders: not playable here
  }
  if (out["name"].get<std::string>().empty()) return nullptr;
  return out;
}
}  // namespace

Pathfinder::Pathfinder(std::shared_ptr<cspot::Context> context) : context_(std::move(context)) { loadState(); }

void Pathfinder::loadState() {
  state_ = JSON::object();
  std::ifstream file(kStatePath);
  if (file) { try { file >> state_; } catch (...) { state_ = JSON::object(); } }
  if (!state_.is_object()) state_ = JSON::object();
  if (!state_.contains("hashes") || !state_["hashes"].is_object()) {
    state_["hashes"] = JSON::object();
    if (isHex64(state_.value("hash", ""))) state_["hashes"]["searchDesktop"] = state_["hash"];   // from the 0.3.0 state layout
    state_.erase("hash");
    if (!state_.contains("hashSource")) state_["hashSource"] = "default";
    saveState();
  }
}
void Pathfinder::saveState() { std::ofstream file(kStatePath, std::ios::trunc); file << state_.dump(); }
std::string Pathfinder::hashFor(const std::string& op) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto cached = state_["hashes"].value(op, "");
  if (isHex64(cached)) return cached;
  auto d = kDefaultHashes.find(op);
  return d == kDefaultHashes.end() ? "" : d->second;
}

bool Pathfinder::available() {
  if (!ipad_catalog_kind_enabled("pathfinder")) return false;
  std::lock_guard<std::mutex> lock(mutex_);
  return state_.value("pausedUntil", 0LL) <= now();
}
std::string Pathfinder::status() {
  std::lock_guard<std::mutex> lock(mutex_);
  std::ostringstream s;
  s << "ops=" << state_["hashes"].size() << " source=" << state_.value("hashSource", "?") << " search=" << state_["hashes"].value("searchDesktop", kDefaultHashes.at("searchDesktop")).substr(0, 8)
    << " failures=" << state_.value("failures", 0) << " token=" << (state_.value("clientTokenExpires", 0LL) > now() ? "yes" : "no");
  return s.str();
}
void Pathfinder::recordFailure(const std::string& why) {
  std::lock_guard<std::mutex> lock(mutex_);
  int failures = state_.value("failures", 0) + 1; state_["failures"] = failures;
  if (failures >= 3) { state_["pausedUntil"] = now() + 600; state_["failures"] = 0; std::fprintf(stderr, "PATHFINDER: paused for 10 minutes (%s)\n", why.c_str()); }
  else std::fprintf(stderr, "PATHFINDER: failure %d: %s\n", failures, why.c_str());
  saveState();
}
void Pathfinder::recordSuccess() { std::lock_guard<std::mutex> lock(mutex_); if (state_.value("failures", 0)) { state_["failures"] = 0; saveState(); } }

// ---- client token (clienttoken.spotify.com, protobuf)
std::string Pathfinder::clientToken() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (state_.value("clientTokenExpires", 0LL) > now() + 60) return state_.value("clientToken", "");
    if (state_.value("clientTokenRetryAt", 0LL) > now()) return {};   // queries work without one; do not pay for a failing handshake every time
  }
  try { return fetchClientToken(); }
  catch (const std::exception& e) {
    std::fprintf(stderr, "PATHFINDER: client token failed: %s\n", e.what());
    std::lock_guard<std::mutex> lock(mutex_); state_["clientTokenRetryAt"] = now() + 3600; saveState();
    return {};
  }
}
std::string Pathfinder::fetchClientToken() {
  // The token service rejects NativeIOSData from this client id (HTTP 400) but accepts the
  // desktop variants, which is what librespot-family clients send.
  std::string macos = field(1, "14.5") + field(2, "MacBookPro18,1") + field(3, "arm64");    // NativeDesktopMacOSData
  std::string platform = field(3, macos);                                                   // PlatformSpecificData.desktop_macos
  std::string connectivity = field(1, platform) + field(2, context_->config.deviceId);     // ConnectivitySdkData
  std::string clientData = field(1, std::string(kAppVersion) + ".g00000000") + field(2, kClientId) + field(3, connectivity);
  std::string request = varintField(1, 1) + field(2, clientData);                           // REQUEST_CLIENT_DATA_REQUEST
  auto response = SpclientClient::fetch("POST", "https://clienttoken.spotify.com/v1/clienttoken",
      {{"Accept", "application/x-protobuf"}, {"Content-Type", "application/x-protobuf"}, {"User-Agent", kUserAgent}}, request, 65536, 20);
  if (response.status != 200) throw std::runtime_error("HTTP " + std::to_string(response.status));
  std::string token; long long expires = 0; uint64_t responseType = 0;
  each(response.body, [&](unsigned n, uint64_t v, const std::string& b) {
    if (n == 1) responseType = v;
    if (n == 2) each(b, [&](unsigned m, uint64_t w, const std::string& c) { if (m == 1) token = c; else if (m == 2) expires = (long long)w; });
  });
  if (responseType != 1 || token.empty()) throw std::runtime_error("no token granted (type " + std::to_string(responseType) + ")");
  std::lock_guard<std::mutex> lock(mutex_);
  state_["clientToken"] = token; state_["clientTokenExpires"] = now() + (expires > 0 ? expires : 3600) - 300; saveState();
  std::fprintf(stderr, "PATHFINDER: client token granted for %llds\n", expires);
  return token;
}

// ---- hash sources
std::map<std::string, std::string> Pathfinder::remoteHashes() {
  std::map<std::string, std::string> out;
  try {
    auto response = SpclientClient::fetch("GET", kRemoteConfig, {{"User-Agent", kUserAgent}, {"Cache-Control", "no-cache"}}, "", 65536, 15);
    if (response.status != 200) return out;
    auto json = JSON::parse(response.body);
    for (auto it = json.begin(); it != json.end(); ++it) if (it.value().is_string() && isHex64(it.value().get<std::string>())) out[it.key()] = it.value().get<std::string>();
  } catch (...) {}
  return out;
}
static void collectHashes(const std::string& js, std::map<std::string, std::string>& out) {
  // Persisted queries appear as ("<operation>","query"|"mutation","<64 hex>")
  for (const char* kind : {"\",\"query\",\"", "\",\"mutation\",\""}) {
    size_t klen = std::strlen(kind);
    for (auto pos = js.find(kind); pos != std::string::npos; pos = js.find(kind, pos + 1)) {
      auto hash = js.substr(pos + klen, 64); if (!isHex64(hash)) continue;
      auto nameEnd = pos, nameStart = pos;
      while (nameStart > 0 && (isalnum((unsigned char)js[nameStart - 1]) || js[nameStart - 1] == '_')) --nameStart;
      if (nameStart == nameEnd || nameStart == 0 || js[nameStart - 1] != '"') continue;
      out[js.substr(nameStart, nameEnd - nameStart)] = hash;
    }
  }
}
std::map<std::string, std::string> Pathfinder::scrapeHashes() {
  std::map<std::string, std::string> found;
  // 1. The page lists its bundles; the main one holds most operations and the chunk map.
  auto page = SpclientClient::fetch("GET", kWebPlayer, {{"User-Agent", kUserAgent}, {"Accept-Language", "en"}, {"Accept", "text/html"}}, "", 2 * 1024 * 1024, 30).body;
  std::string mainUrl;
  for (auto p = page.find("/cdn/build/web-player/web-player."); p != std::string::npos; p = page.find("/cdn/build/web-player/web-player.", p + 1)) {
    auto end = page.find_first_of("\"' ", p); if (end == std::string::npos) break;
    auto ref = page.substr(p, end - p);
    if (ref.size() > 4 && ref.compare(ref.size() - 3, 3, ".js") == 0) { mainUrl = "https://open.spotifycdn.com" + ref; break; }
  }
  if (mainUrl.empty()) throw std::runtime_error("web player page has no main bundle (page " + std::to_string(page.size()) + " bytes)");
  auto bundle = SpclientClient::fetch("GET", mainUrl, {{"User-Agent", kUserAgent}}, "", 12 * 1024 * 1024, 120).body;
  collectHashes(bundle, found);
  // 2. Search lives in its own route chunk: ...,4406:"xpui-routes-search",... and 4406:"<8 hex>" in the hash map.
  auto name = bundle.find("\"xpui-routes-search\"");
  if (name != std::string::npos) {
    size_t idEnd = name - 1, idStart = idEnd; while (idStart > 0 && isdigit((unsigned char)bundle[idStart - 1])) --idStart;
    auto id = bundle.substr(idStart, idEnd - idStart); std::string needle = id + ":\"";
    for (auto pos = bundle.find(needle); pos != std::string::npos && !found.count("searchDesktop"); pos = bundle.find(needle, pos + 1)) {
      if (pos > 0 && isdigit((unsigned char)bundle[pos - 1])) continue;
      auto h = bundle.substr(pos + needle.size(), 8); bool hex = h.size() == 8; for (char c : h) hex = hex && isxdigit((unsigned char)c);
      if (!hex) continue;
      try { collectHashes(SpclientClient::fetch("GET", std::string(kCdn) + "xpui-routes-search." + h + ".js", {{"User-Agent", kUserAgent}}, "", 2 * 1024 * 1024, 30).body, found); } catch (...) {}
    }
  }
  if (found.empty()) throw std::runtime_error("no operations found (bundle " + std::to_string(bundle.size()) + " bytes)");
  return found;
}
std::string Pathfinder::refreshHashes(bool force) {
  long long lastScrape; { std::lock_guard<std::mutex> lock(mutex_); lastScrape = state_.value("lastScrape", 0LL); }
  auto remote = remoteHashes();
  bool changed = false;
  if (!remote.empty()) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& kv : remote) if (state_["hashes"].value(kv.first, "") != kv.second) { state_["hashes"][kv.first] = kv.second; changed = true; }
    if (changed) { state_["hashSource"] = "remote"; state_["hashAt"] = now(); saveState(); std::fprintf(stderr, "PATHFINDER: %lu hashes updated from the repository config\n", (unsigned long)remote.size()); }
  }
  if (!force && now() - lastScrape < 3600) return changed ? "remote" : "unchanged";   // never hammer the CDN
  try {
    auto started = std::chrono::steady_clock::now();
    auto scraped = scrapeHashes();
    std::lock_guard<std::mutex> lock(mutex_);
    state_["lastScrape"] = now(); int updated = 0;
    for (const auto& kv : scraped) if (state_["hashes"].value(kv.first, "") != kv.second) { state_["hashes"][kv.first] = kv.second; ++updated; }
    if (updated) { state_["hashSource"] = "scrape"; state_["hashAt"] = now(); }
    saveState();
    std::fprintf(stderr, "PATHFINDER: scraped %lu operations in %lld ms (%d updated)\n", (unsigned long)scraped.size(),
        (long long)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started).count(), updated);
    return "scrape";
  } catch (const std::exception& e) {
    std::lock_guard<std::mutex> lock(mutex_); state_["lastScrape"] = now();
    std::fprintf(stderr, "PATHFINDER: scrape failed: %s\n", e.what());
    for (const auto& kv : kDefaultHashes) state_["hashes"][kv.first] = kv.second;   // last resort: what this build shipped with
    state_["hashSource"] = "default"; saveState();
    return "default";
  }
}
void Pathfinder::refreshIfStale() {
  long long hashAt, lastScrape;
  { std::lock_guard<std::mutex> lock(mutex_); hashAt = state_.value("hashAt", 0LL); lastScrape = state_.value("lastScrape", 0LL); }
  const long long week = 7 * 24 * 3600;
  if (now() - hashAt < week || now() - lastScrape < week) return;
  { std::lock_guard<std::mutex> lock(mutex_); state_["lastScrape"] = now(); saveState(); }   // one attempt per week even if it fails
  std::thread([this]() { try { refreshHashes(true); } catch (...) {} }).detach();
}

// ---- requests
JSON Pathfinder::request(const std::string& op, const JSON& variables, const std::string& hash, int& httpStatus, std::string& rawOut) {
  JSON extensions{{"persistedQuery", {{"version", 1}, {"sha256Hash", hash}}}};
  std::string url = "https://api-partner.spotify.com/pathfinder/v1/query?operationName=" + op + "&variables=" + encode(variables.dump()) + "&extensions=" + encode(extensions.dump());
  auto token = cspot::AccessKeyFetcher::forContext(context_)->getAccessKey();
  if (token.empty()) throw std::runtime_error("no session token");
  std::vector<std::pair<std::string, std::string>> headers{{"Authorization", "Bearer " + token}, {"app-platform", "WebPlayer"}, {"spotify-app-version", kAppVersion},
      {"User-Agent", kUserAgent}, {"Origin", "https://open.spotify.com"}, {"Referer", "https://open.spotify.com/"}, {"Accept-Language", "en"}, {"Accept", "application/json"}};
  auto client = clientToken(); if (!client.empty()) headers.push_back({"client-token", client});
  auto response = SpclientClient::fetch("GET", url, headers, "", 4 * 1024 * 1024, 25);
  httpStatus = response.status; rawOut = response.body;
  if (debugEnabled()) dump(op, "HTTP " + std::to_string(httpStatus) + "\n" + response.body);
  try { return JSON::parse(response.body); } catch (...) { return JSON{{"parseError", true}, {"text", response.body.substr(0, 200)}}; }
}
JSON Pathfinder::run(const std::string& op, const JSON& variables) {
  std::string hash = hashFor(op);
  if (hash.empty()) throw std::runtime_error("no hash known for " + op);
  for (int attempt = 0; attempt < 2; ++attempt) {
    int status = 0; JSON response; std::string raw;
    try { response = request(op, variables, hash, status, raw); } catch (const std::exception& e) { recordFailure(e.what()); throw; }
    std::string errorText;
    if (response.contains("errors") && response["errors"].is_array() && !response["errors"].empty()) errorText = response["errors"][0].value("message", "");
    if (status == 200 && response.contains("data") && response["data"].is_object() && !response["data"].empty()) { recordSuccess(); return response["data"]; }
    bool staleHash = errorText.find("ersisted") != std::string::npos;
    if (staleHash && attempt == 0) {
      std::fprintf(stderr, "PATHFINDER: stale hash for %s; refreshing\n", op.c_str());
      refreshHashes(true);
      auto fresh = hashFor(op);
      if (fresh != hash) { hash = fresh; continue; }
    }
    if ((status == 401 || status == 403) && attempt == 0) {
      std::lock_guard<std::mutex> lock(mutex_); state_["clientTokenExpires"] = 0; saveState();
      continue;
    }
    std::string why = op + ": HTTP " + std::to_string(status) + (errorText.empty() ? "" : " " + errorText.substr(0, 160));
    recordFailure(why);
    throw std::runtime_error(why);
  }
  throw std::runtime_error(op + ": retry exhausted");
}
std::string Pathfinder::raw(const std::string& op, const std::string& variablesJSON) {
  JSON variables = JSON::object();
  try { if (!variablesJSON.empty()) variables = JSON::parse(variablesJSON); } catch (...) { return "{\"error\":\"bad variables json\"}"; }
  int status = 0; std::string body;
  try { request(op, variables, hashFor(op), status, body); } catch (const std::exception& e) { return std::string("{\"error\":\"") + e.what() + "\"}"; }
  dump(op, "HTTP " + std::to_string(status) + "\n" + body);
  return body;
}

// ---- operations
JSON Pathfinder::search(const std::string& textQuery) {
  JSON variables{{"searchTerm", textQuery}, {"offset", 0}, {"limit", 10}, {"numberOfTopResults", 5}, {"includeAudiobooks", false}, {"includeArtistHasConcertsField", false},
      {"includePreReleases", false}, {"includeLocalConcertsField", false}, {"includeAuthors", false}, {"includeAlbumPreReleases", false}, {"includeEpisodeContentRatingsV2", false}};
  JSON data = run("searchDesktop", variables);
  JSON out{{"tracks", JSON::array()}, {"artists", JSON::array()}, {"albums", JSON::array()}, {"playlists", JSON::array()}};
  const JSON* v2 = at(&data, "searchV2");
  if (auto arr = items(at(v2, "tracksV2"))) for (const auto& wrapper : *arr) {
    const JSON* d = at(at(&wrapper, "item"), "data"); if (!d) d = at(&wrapper, "data"); if (!d) continue;
    auto uri = text(at(d, "uri")); if (uri.compare(0, 14, "spotify:track:") != 0) continue;
    auto names = artistNames(at(d, "artists"));
    const JSON* album = at(d, "albumOfTrack");
    auto artwork = firstImage(at(at(album, "coverArt"), "sources"), 300), small = firstImage(at(at(album, "coverArt"), "sources"), 64);
    bool playable = true; if (auto p = at(at(d, "playability"), "playable")) if (p->is_boolean()) playable = p->get<bool>();
    if (!playable) continue;
    out["tracks"].push_back({{"uri", uri}, {"id", uri.substr(14)}, {"title", text(at(d, "name"))}, {"artist", names.first}, {"artists", names.second},
        {"album", text(at(album, "name"))}, {"albumUri", text(at(album, "uri"))}, {"artwork", artwork}, {"artworkSmall", small.empty() ? artwork : small},
        {"duration", number(at(at(d, "duration"), "totalMilliseconds"))}, {"number", 0}, {"disc", 0}});
  }
  for (const char* section : {"artists", "albumsV2", "playlists"}) {
    if (auto arr = items(at(v2, section))) for (const auto& wrapper : *arr) {
      auto e = entity(at(&wrapper, "data")); if (e.is_null()) continue;
      std::string type = e["type"];
      if (type == "artist") out["artists"].push_back({{"uri", e["uri"]}, {"name", e["name"]}, {"image", e["artwork"]}});
      else if (type == "album") out["albums"].push_back({{"uri", e["uri"]}, {"name", e["name"]}, {"artist", e["artist"]}, {"artwork", e["artwork"]}});
      else if (type == "playlist") {
        std::string subtitle = e["subtitle"];
        out["playlists"].push_back({{"uri", e["uri"]}, {"name", e["name"]}, {"owner", subtitle.size() > 11 ? subtitle.substr(11) : ""}, {"artwork", e["artwork"]}});
      }
    }
  }
  std::fprintf(stderr, "PATHFINDER: tracks=%lu artists=%lu albums=%lu playlists=%lu\n", (unsigned long)out["tracks"].size(), (unsigned long)out["artists"].size(),
      (unsigned long)out["albums"].size(), (unsigned long)out["playlists"].size());
  return out;
}
static std::string systemTimeZone() {
  std::string name = "UTC";
  if (CFTimeZoneRef zone = CFTimeZoneCopySystem()) {
    char buffer[128] = {0};
    if (CFStringGetCString(CFTimeZoneGetName(zone), buffer, sizeof buffer, kCFStringEncodingUTF8)) name = buffer;
    CFRelease(zone);
  }
  return name;
}
JSON Pathfinder::home() {
  // HomeEndUserIntegration is an enum; the web player sends INTEGRATION_WEB_PLAYER.
  JSON variables{{"timeZone", systemTimeZone()}, {"sp_t", ""}, {"facet", ""}, {"sectionItemsLimit", 10}, {"includeHomeChapterVideoCards", false},
      {"homeEndUserIntegration", "INTEGRATION_WEB_PLAYER"}, {"includeEpisodeContentRatingsV2", false}};
  JSON data = run("home", variables);
  JSON out{{"sections", JSON::array()}, {"greeting", text(at(at(at(&data, "home"), "greeting"), "transformedLabel"))}};
  // data.home.sectionContainer.sections.items[].{data.__typename, data.title.transformedLabel, sectionItems.items[].content.data}
  // Only the shelf-style sections; the single-card feed sections and the shorts row are skipped.
  const JSON* sections = items(at(at(at(&data, "home"), "sectionContainer"), "sections"));
  if (sections) for (const auto& section : *sections) {
    if (text(at(at(&section, "data"), "__typename")) != "HomeGenericSectionData") continue;
    auto title = text(at(at(at(&section, "data"), "title"), "transformedLabel"));
    if (title.empty()) continue;
    JSON list = JSON::array();
    if (auto arr = items(at(&section, "sectionItems"))) for (const auto& item : *arr) {
      const JSON* d = at(at(&item, "content"), "data"); if (!d) d = at(&item, "data");
      auto e = entity(d); if (!e.is_null()) list.push_back(e);
    }
    if (list.size() >= 2) out["sections"].push_back({{"title", title}, {"items", list}});
  }
  std::fprintf(stderr, "PATHFINDER: home sections=%lu\n", (unsigned long)out["sections"].size());
  return out;
}
JSON Pathfinder::library(int limit) {
  JSON variables{{"filters", JSON::array()}, {"order", nullptr}, {"textFilter", ""}, {"features", JSON::array({"LIKED_SONGS", "YOUR_EPISODES"})},
      {"limit", limit}, {"offset", 0}, {"flatten", true}, {"expandedFolders", JSON::array()}, {"folderUri", nullptr}, {"includeFoldersWhenFlattening", true}};
  JSON data = run("libraryV3", variables);
  JSON out{{"items", JSON::array()}, {"total", 0}};
  const JSON* lib = at(at(&data, "me"), "libraryV3");
  out["total"] = number(at(lib, "totalCount"));
  if (auto arr = items(lib)) for (const auto& wrapper : *arr) {
    const JSON* d = at(at(&wrapper, "item"), "data"); if (!d) d = at(&wrapper, "data");
    auto e = entity(d); if (!e.is_null()) out["items"].push_back(e);
  }
  std::fprintf(stderr, "PATHFINDER: library items=%lu of %d\n", (unsigned long)out["items"].size(), out["total"].get<int>());
  return out;
}
}  // namespace ipad_player
