// SPDX-License-Identifier: GPL-3.0-or-later
#include "Pathfinder.h"
#include "PlayerBridge.h"
#include "AccessKeyFetcher.h"
#include "CSpotContext.h"
#include "SpclientClient.h"
#include <chrono>
#include <thread>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace ipad_player {
using JSON = nlohmann::json;
namespace {
// Compiled-in fallback, extracted from the web player on 2026-10-08. The runtime sources above
// take precedence; this only matters on a device that has never been online with this build.
const char* kDefaultHash = "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03";
const char* kStatePath = "/var/mobile/Documents/bennu-pathfinder.json";
const char* kDebugBodyPath = "/var/mobile/Documents/bennu-pathfinder-last.json";
const char* kRemoteConfig = "https://raw.githubusercontent.com/micheldpcarlos/bennu-music/main/config/pathfinder.json";
const char* kWebPlayer = "https://open.spotify.com/";
const char* kCdn = "https://open.spotifycdn.com/cdn/build/web-player/";
const char* kUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const char* kClientId = "65b708073fc0480ea92a077233ca87bd";   // the web player's id, the same one the session token belongs to
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
// Safe navigation helpers: these responses are nested five levels deep and partly optional.
const JSON* at(const JSON* j, const char* key) { if (!j || !j->is_object()) return nullptr; auto it = j->find(key); return it == j->end() ? nullptr : &*it; }
std::string text(const JSON* j) { return j && j->is_string() ? j->get<std::string>() : std::string(); }
std::string firstImage(const JSON* sources, int preferredWidth) {
  // sources: [{url,width,height}]. Prefer the first one at or above the wanted width.
  if (!sources || !sources->is_array() || sources->empty()) return {};
  std::string best; int bestWidth = 1 << 30;
  for (const auto& s : *sources) {
    auto url = text(at(&s, "url")); if (url.empty()) continue;
    int w = s.contains("width") && s["width"].is_number() ? s["width"].get<int>() : 0;
    if (w >= preferredWidth && w < bestWidth) { best = url; bestWidth = w; }
  }
  if (best.empty()) best = text(at(&(*sources)[sources->size() - 1], "url"));
  return best;
}
const JSON* items(const JSON* section) { auto i = at(section, "items"); return i && i->is_array() ? i : nullptr; }
}  // namespace

Pathfinder::Pathfinder(std::shared_ptr<cspot::Context> context) : context_(std::move(context)) { loadState(); }

void Pathfinder::loadState() {
  state_ = JSON::object();
  std::ifstream file(kStatePath);
  if (file) { try { file >> state_; } catch (...) { state_ = JSON::object(); } }
  if (!state_.is_object()) state_ = JSON::object();
  if (!isHex64(state_.value("hash", ""))) { state_["hash"] = kDefaultHash; state_["hashSource"] = "default"; state_["hashAt"] = now(); saveState(); }
}
void Pathfinder::saveState() { std::ofstream file(kStatePath, std::ios::trunc); file << state_.dump(); }

bool Pathfinder::available() {
  if (!ipad_catalog_kind_enabled("pathfinder")) return false;
  std::lock_guard<std::mutex> lock(mutex_);
  return state_.value("pausedUntil", 0LL) <= now();
}
std::string Pathfinder::status() {
  std::lock_guard<std::mutex> lock(mutex_);
  std::ostringstream s;
  s << "hash=" << state_.value("hash", "").substr(0, 8) << " source=" << state_.value("hashSource", "?") << " failures=" << state_.value("failures", 0)
    << " token=" << (state_.value("clientTokenExpires", 0LL) > now() ? "yes" : "no");
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
    if (state_.value("clientTokenRetryAt", 0LL) > now()) return {};   // the search works without one; do not pay for a failing handshake on every query
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
  // desktop variants, which is what librespot-family clients send; the token is tied to the
  // client id and device id, not to the platform fields.
  std::string macos = field(1, "14.5") + field(2, "MacBookPro18,1") + field(3, "arm64");    // NativeDesktopMacOSData
  std::string platform = field(3, macos);                                                   // PlatformSpecificData.desktop_macos
  std::string connectivity = field(1, platform) + field(2, context_->config.deviceId);     // ConnectivitySdkData
  std::string clientData = field(1, std::string(kAppVersion) + ".g00000000") + field(2, kClientId) + field(3, connectivity);
  std::string request = varintField(1, 1) + field(2, clientData);                           // REQUEST_CLIENT_DATA_REQUEST
  auto response = SpclientClient::fetch("POST", "https://clienttoken.spotify.com/v1/clienttoken",
      {{"Accept", "application/x-protobuf"}, {"Content-Type", "application/x-protobuf"}, {"User-Agent", kUserAgent}}, request, 65536, 20);
  const auto& data = response.body;
  if (response.status != 200) throw std::runtime_error("HTTP " + std::to_string(response.status));
  std::string token; long long expires = 0; uint64_t responseType = 0;
  each(data, [&](unsigned n, uint64_t v, const std::string& b) {
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
std::string Pathfinder::remoteHash() {
  try {
    auto response = SpclientClient::fetch("GET", kRemoteConfig, {{"User-Agent", kUserAgent}, {"Cache-Control", "no-cache"}}, "", 65536, 15);
    if (response.status != 200) return {};
    auto json = JSON::parse(response.body);
    auto hash = json.value("searchDesktop", ""); return isHex64(hash) ? hash : "";
  } catch (...) { return {}; }
}
std::string Pathfinder::scrapeHash() {
  // 1. The page lists its bundles; the main one holds the chunk map.
  auto page = SpclientClient::fetch("GET", kWebPlayer, {{"User-Agent", kUserAgent}, {"Accept-Language", "en"}, {"Accept", "text/html"}}, "", 2 * 1024 * 1024, 30).body;
  std::string mainUrl;
  for (auto at = page.find("/cdn/build/web-player/web-player."); at != std::string::npos; at = page.find("/cdn/build/web-player/web-player.", at + 1)) {
    auto end = page.find_first_of("\"' ", at); if (end == std::string::npos) break;
    auto ref = page.substr(at, end - at);
    if (ref.size() > 4 && ref.compare(ref.size() - 3, 3, ".js") == 0) { mainUrl = "https://open.spotifycdn.com" + ref; break; }
  }
  if (mainUrl.empty()) throw std::runtime_error("web player page has no main bundle (page " + std::to_string(page.size()) + " bytes)");
  // 2. The main bundle (a few MB) maps chunk ids to names and names to content hashes.
  auto bundle = SpclientClient::fetch("GET", mainUrl, {{"User-Agent", kUserAgent}}, "", 12 * 1024 * 1024, 120).body;
  auto name = bundle.find("\"xpui-routes-search\"");
  if (name == std::string::npos) throw std::runtime_error("search chunk name not found (bundle " + std::to_string(bundle.size()) + " bytes)");
  // the id precedes the name: ...,4406:"xpui-routes-search",...
  size_t idEnd = name - 1, idStart = idEnd; while (idStart > 0 && isdigit((unsigned char)bundle[idStart - 1])) --idStart;
  auto id = bundle.substr(idStart, idEnd - idStart);
  if (id.empty()) throw std::runtime_error("search chunk id not found");
  // every `ID:"xxxxxxxx"` is a candidate content hash (there is one map for js, one for css)
  std::string needle = id + ":\"";
  for (auto pos = bundle.find(needle); pos != std::string::npos; pos = bundle.find(needle, pos + 1)) {
    if (pos > 0 && (isdigit((unsigned char)bundle[pos - 1]))) continue;
    auto h = bundle.substr(pos + needle.size(), 8);
    bool hex = h.size() == 8; for (char c : h) hex = hex && isxdigit((unsigned char)c);
    if (!hex) continue;
    try {
      auto chunk = SpclientClient::fetch("GET", std::string(kCdn) + "xpui-routes-search." + h + ".js", {{"User-Agent", kUserAgent}}, "", 2 * 1024 * 1024, 30).body;
      auto op = chunk.find("\"searchDesktop\"");
      if (op == std::string::npos) continue;
      // ..."searchDesktop","query","<64 hex>"
      auto q = chunk.find("\"query\",\"", op); if (q == std::string::npos || q - op > 40) continue;
      auto hash = chunk.substr(q + 9, 64);
      if (isHex64(hash)) return hash;
    } catch (...) { continue; }
  }
  throw std::runtime_error("hash not found in search chunk");
}
std::string Pathfinder::refreshHash(bool force) {
  std::string current, source; long long lastScrape;
  { std::lock_guard<std::mutex> lock(mutex_); current = state_.value("hash", ""); source = state_.value("hashSource", ""); lastScrape = state_.value("lastScrape", 0LL); }
  auto remote = remoteHash();
  if (!remote.empty() && remote != current) {
    std::lock_guard<std::mutex> lock(mutex_); state_["hash"] = remote; state_["hashSource"] = "remote"; state_["hashAt"] = now(); saveState();
    std::fprintf(stderr, "PATHFINDER: hash updated from the repository config\n"); return remote;
  }
  if (!force && now() - lastScrape < 3600) {                   // never hammer the CDN
    if (current != kDefaultHash) { std::lock_guard<std::mutex> lock(mutex_); state_["hash"] = kDefaultHash; state_["hashSource"] = "default"; saveState(); return kDefaultHash; }
    return current;
  }
  try {
    auto started = std::chrono::steady_clock::now();
    auto scraped = scrapeHash();
    std::lock_guard<std::mutex> lock(mutex_);
    state_["lastScrape"] = now();
    if (scraped != current) { state_["hash"] = scraped; state_["hashSource"] = "scrape"; state_["hashAt"] = now(); }
    saveState();
    std::fprintf(stderr, "PATHFINDER: scraped hash %s in %lld ms (%s)\n", scraped.substr(0, 8).c_str(),
        (long long)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started).count(), scraped == current ? "unchanged" : "new");
    return scraped;
  } catch (const std::exception& e) {
    std::lock_guard<std::mutex> lock(mutex_); state_["lastScrape"] = now();
    std::fprintf(stderr, "PATHFINDER: scrape failed: %s\n", e.what());
    // Last resort: the hash this build shipped with, if the current one is something else.
    if (current != kDefaultHash) { state_["hash"] = kDefaultHash; state_["hashSource"] = "default"; state_["hashAt"] = now(); saveState(); return kDefaultHash; }
    saveState();
    return current;
  }
}

void Pathfinder::refreshIfStale() {
  long long hashAt, lastScrape;
  { std::lock_guard<std::mutex> lock(mutex_); hashAt = state_.value("hashAt", 0LL); lastScrape = state_.value("lastScrape", 0LL); }
  const long long week = 7 * 24 * 3600;
  if (now() - hashAt < week || now() - lastScrape < week) return;
  { std::lock_guard<std::mutex> lock(mutex_); state_["lastScrape"] = now(); saveState(); }   // one attempt per week even if it fails
  std::thread([this]() { try { refreshHash(true); } catch (...) {} }).detach();
}
// ---- the query
JSON Pathfinder::query(const std::string& text, const std::string& hash, int& httpStatus) {
  JSON variables{{"searchTerm", text}, {"offset", 0}, {"limit", 10}, {"numberOfTopResults", 5}, {"includeAudiobooks", false}, {"includeArtistHasConcertsField", false},
      {"includePreReleases", false}, {"includeLocalConcertsField", false}, {"includeAuthors", false}, {"includeAlbumPreReleases", false}, {"includeEpisodeContentRatingsV2", false}};
  JSON extensions{{"persistedQuery", {{"version", 1}, {"sha256Hash", hash}}}};
  std::string url = "https://api-partner.spotify.com/pathfinder/v1/query?operationName=searchDesktop&variables=" + encode(variables.dump()) + "&extensions=" + encode(extensions.dump());
  auto token = cspot::AccessKeyFetcher::forContext(context_)->getAccessKey();
  if (token.empty()) throw std::runtime_error("no session token");
  std::vector<std::pair<std::string, std::string>> headers{{"Authorization", "Bearer " + token}, {"app-platform", "WebPlayer"}, {"spotify-app-version", kAppVersion},
      {"User-Agent", kUserAgent}, {"Origin", "https://open.spotify.com"}, {"Referer", "https://open.spotify.com/"}, {"Accept-Language", "en"}, {"Accept", "application/json"}};
  auto client = clientToken(); if (!client.empty()) headers.push_back({"client-token", client});
  auto response = SpclientClient::fetch("GET", url, headers, "", 2 * 1024 * 1024, 25);
  httpStatus = response.status;
  auto raw = response.body;
  if (std::ifstream("/var/mobile/Documents/bennu-debug")) { std::ofstream debug(kDebugBodyPath, std::ios::trunc); debug << "HTTP " << httpStatus << "\n" << raw.substr(0, 300000); }
  try { return JSON::parse(raw); } catch (...) { return JSON{{"parseError", true}, {"text", raw.substr(0, 200)}}; }
}
JSON Pathfinder::search(const std::string& text) {
  std::string hash; { std::lock_guard<std::mutex> lock(mutex_); hash = state_.value("hash", kDefaultHash); }
  for (int attempt = 0; attempt < 2; ++attempt) {
    int status = 0; JSON response;
    try { response = query(text, hash, status); } catch (const std::exception& e) { recordFailure(e.what()); throw; }
    std::string errorText;
    if (response.contains("errors") && response["errors"].is_array() && !response["errors"].empty()) errorText = response["errors"][0].value("message", "");
    bool staleHash = errorText.find("ersisted") != std::string::npos || (status == 400 && response.contains("errors"));
    if (status == 200 && at(at(&response, "data"), "searchV2")) {
      auto result = parse(response);
      recordSuccess();
      return result;
    }
    if (staleHash && attempt == 0) {
      std::fprintf(stderr, "PATHFINDER: stale hash (%s); refreshing\n", errorText.c_str());
      auto fresh = refreshHash(true);
      if (fresh != hash) { hash = fresh; continue; }
    }
    if ((status == 401 || status == 403) && attempt == 0) {
      // Let the next attempt obtain a fresh client token; the session token refreshes itself.
      std::lock_guard<std::mutex> lock(mutex_); state_["clientTokenExpires"] = 0; saveState();
      continue;
    }
    std::string why = "HTTP " + std::to_string(status) + (errorText.empty() ? "" : " " + errorText.substr(0, 120));
    recordFailure(why);
    throw std::runtime_error(why);
  }
  throw std::runtime_error("pathfinder: retry exhausted");
}

// ---- response -> UI JSON, same keys the rest of the catalog uses
JSON Pathfinder::parse(const JSON& response) {
  JSON out{{"tracks", JSON::array()}, {"artists", JSON::array()}, {"albums", JSON::array()}, {"playlists", JSON::array()}};
  const JSON* v2 = at(at(&response, "data"), "searchV2");
  auto artistNames = [](const JSON* artists) {
    std::string joined; JSON list = JSON::array();
    if (auto arr = items(artists)) for (const auto& a : *arr) {
      auto name = text(at(at(&a, "profile"), "name")); auto uri = text(at(&a, "uri"));
      if (name.empty()) continue;
      joined += (joined.empty() ? "" : ", ") + name; list.push_back({{"name", name}, {"uri", uri}});
    }
    return std::make_pair(joined, list);
  };
  if (auto arr = items(at(v2, "tracksV2"))) for (const auto& wrapper : *arr) {
    const JSON* data = at(at(&wrapper, "item"), "data"); if (!data) data = at(&wrapper, "data"); if (!data) continue;
    auto uri = text(at(data, "uri")); if (uri.compare(0, 14, "spotify:track:") != 0) continue;
    auto names = artistNames(at(data, "artists"));
    const JSON* album = at(data, "albumOfTrack");
    auto artwork = firstImage(at(at(album, "coverArt"), "sources"), 300), small = firstImage(at(at(album, "coverArt"), "sources"), 64);
    int duration = 0; if (auto d = at(at(data, "duration"), "totalMilliseconds")) if (d->is_number()) duration = d->get<int>();
    bool playable = true; if (auto p = at(at(data, "playability"), "playable")) if (p->is_boolean()) playable = p->get<bool>();
    if (!playable) continue;
    out["tracks"].push_back({{"uri", uri}, {"id", uri.substr(14)}, {"title", text(at(data, "name"))}, {"artist", names.first}, {"artists", names.second},
        {"album", text(at(album, "name"))}, {"albumUri", text(at(album, "uri"))}, {"artwork", artwork}, {"artworkSmall", small.empty() ? artwork : small},
        {"duration", duration}, {"number", 0}, {"disc", 0}});
  }
  if (auto arr = items(at(v2, "artists"))) for (const auto& wrapper : *arr) {
    const JSON* data = at(&wrapper, "data"); if (!data) continue;
    auto uri = text(at(data, "uri")); auto name = text(at(at(data, "profile"), "name")); if (uri.empty() || name.empty()) continue;
    out["artists"].push_back({{"uri", uri}, {"name", name}, {"image", firstImage(at(at(at(data, "visuals"), "avatarImage"), "sources"), 160)}});
  }
  if (auto arr = items(at(v2, "albumsV2"))) for (const auto& wrapper : *arr) {
    const JSON* data = at(&wrapper, "data"); if (!data) continue;
    auto uri = text(at(data, "uri")); auto name = text(at(data, "name")); if (uri.empty() || name.empty()) continue;
    auto names = artistNames(at(data, "artists"));
    int year = 0; if (auto y = at(at(data, "date"), "year")) if (y->is_number()) year = y->get<int>();
    out["albums"].push_back({{"uri", uri}, {"name", name}, {"artist", names.first}, {"artwork", firstImage(at(at(data, "coverArt"), "sources"), 300)}, {"year", year}});
  }
  if (auto arr = items(at(v2, "playlists"))) for (const auto& wrapper : *arr) {
    const JSON* data = at(&wrapper, "data"); if (!data) continue;
    auto uri = text(at(data, "uri")); auto name = text(at(data, "name")); if (uri.empty() || name.empty()) continue;
    std::string artwork;
    if (auto imgs = items(at(data, "images"))) if (!imgs->empty()) artwork = firstImage(at(&(*imgs)[0], "sources"), 300);
    auto owner = text(at(at(at(data, "ownerV2"), "data"), "name"));
    out["playlists"].push_back({{"uri", uri}, {"name", name}, {"owner", owner}, {"artwork", artwork}});
  }
  std::fprintf(stderr, "PATHFINDER: tracks=%lu artists=%lu albums=%lu playlists=%lu\n", (unsigned long)out["tracks"].size(), (unsigned long)out["artists"].size(),
      (unsigned long)out["albums"].size(), (unsigned long)out["playlists"].size());
  return out;
}
}  // namespace ipad_player
