// SPDX-License-Identifier: GPL-3.0-or-later
#include "Catalog.h"
#include "SpclientClient.h"
#include "CSpotContext.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <set>
#include <thread>
#include <sys/stat.h>
namespace ipad_player {
using JSON = nlohmann::json;
namespace {
const char* kAlphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
bool validID(const std::string& id) {
  return id.size() == 22 && id.find_first_not_of(kAlphabet) == std::string::npos;
}
std::string percentEncode(const std::string& input) {
  const char* digits = "0123456789ABCDEF";
  std::string output;
  for (unsigned char byte : input) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') ||
        byte == '-' || byte == '_' || byte == '.' || byte == '~') output += static_cast<char>(byte);
    else if (byte == ' ') output += '+';
    else { output += '%'; output += digits[byte >> 4]; output += digits[byte & 15]; }
  }
  return output;
}
std::string str(const JSON& object, const char* key, size_t limit = 1024) {
  if (!object.is_object()) return {};
  auto found = object.find(key);
  if (found == object.end() || !found->is_string()) return {};
  auto value = found->get<std::string>();
  return value.size() <= limit ? value : value.substr(0, limit);
}
long long num(const JSON& object, const char* key) {
  if (!object.is_object()) return 0;
  auto found = object.find(key);
  return found != object.end() && found->is_number() ? found->get<long long>() : 0;
}
std::string imageURL(const std::string& id) {
  if (id.empty()) return {};
  if (id.compare(0, 8, "https://") == 0) {
    if (id.size() >= 2048) return {};  // profile photos on fbcdn carry long signed query strings
    // Legacy hosts (u.scdn.co no longer resolves) and image-cdn-ak.spotifycdn.com (serves formats
    // iOS 9 cannot decode) carry the same 40-hex image id; i.scdn.co serves it as JPEG.
    auto slash = id.rfind('/');
    if (slash != std::string::npos && id.size() - slash - 1 == 40 && id.find("i.scdn.co") == std::string::npos) {
      auto tail = id.substr(slash + 1);
      if (tail.find_first_not_of("0123456789abcdef") == std::string::npos) return imageURL(tail);
    }
    return id;
  }
  if (id.compare(0, 15, "spotify:mosaic:") == 0) return id.size() < 512 ? id : std::string();  // the UI composes 2x2 collages
  std::string bare = id.compare(0, 14, "spotify:image:") == 0 ? id.substr(14) : id;
  if (bare.size() != 40 || bare.find_first_not_of("0123456789abcdef") != std::string::npos) return {};
  // Characters 8-16 select size and format. 0000d72c is only served as WebP, which iOS 9
  // cannot decode; 0000bebb is the JPEG equivalent for playlist covers.
  if (bare.compare(8, 8, "0000d72c") == 0) bare.replace(8, 8, "0000bebb");
  return "https://i.scdn.co/image/" + bare;
}
// cover_group / portrait_group -> {default, small}
void pickImages(const JSON& group, std::string& normal, std::string& small) {
  if (!group.is_object() || !group.count("image") || !group["image"].is_array()) return;
  std::string any;
  for (const auto& image : group["image"]) {
    auto size = str(image, "size", 16), file = str(image, "file_id", 64);
    if (file.empty()) continue;
    if (any.empty()) any = file;
    if (size == "DEFAULT") normal = file; else if (size == "SMALL") small = file;
  }
  if (normal.empty()) normal = any;
  if (small.empty()) small = normal;
  normal = imageURL(normal); small = imageURL(small);
}
std::string artistNames(const JSON& list) {
  std::string names; size_t count = 0;
  if (!list.is_array()) return names;
  for (const auto& person : list) {
    if (++count > 3) break;
    auto name = str(person, "name", 256);
    if (!name.empty()) { if (!names.empty()) names += ", "; names += name; }
  }
  return names;
}
std::string cleanBiography(std::string text) {
  // Spotify biographies carry <a href=...> links; keep the words only.
  std::string output; bool inTag = false;
  for (char c : text) { if (c == '<') inTag = true; else if (c == '>') inTag = false; else if (!inTag) output += c; }
  if (output.size() > 1200) { output.resize(1200); output += "…"; }
  return output;
}
int yearOf(const JSON& object) { return object.is_object() && object.count("date") ? static_cast<int>(num(object["date"], "year")) : 0; }
}
std::string hexFromBase62(const std::string& id) {
  if (!validID(id)) return {};
  unsigned char bytes[16] = {0};
  for (char c : id) {
    unsigned carry = static_cast<unsigned>(std::string(kAlphabet).find(c));
    for (int i = 15; i >= 0; --i) { unsigned value = bytes[i] * 62u + carry; bytes[i] = value & 0xff; carry = value >> 8; }
  }
  static const char* digits = "0123456789abcdef";
  std::string hex;
  for (unsigned char b : bytes) { hex += digits[b >> 4]; hex += digits[b & 15]; }
  return hex;
}
std::string base62FromHex(const std::string& hex) {
  if (hex.size() != 32 || hex.find_first_not_of("0123456789abcdef") != std::string::npos) return {};
  unsigned char bytes[16];
  for (int i = 0; i < 16; ++i) bytes[i] = static_cast<unsigned char>(std::stoul(hex.substr(i * 2, 2), nullptr, 16));
  std::string output;
  for (int digit = 0; digit < 22; ++digit) {
    unsigned remainder = 0;
    for (int i = 0; i < 16; ++i) { unsigned value = (remainder << 8) | bytes[i]; bytes[i] = static_cast<unsigned char>(value / 62); remainder = value % 62; }
    output += kAlphabet[remainder];
  }
  std::reverse(output.begin(), output.end());
  return output;
}

Catalog::Catalog(std::shared_ptr<cspot::Context> context, std::string dir)
    : context_(std::move(context)), client(new SpclientClient(context_)), client2(new SpclientClient(context_)), cacheDir(std::move(dir)) {
  mkdir(cacheDir.c_str(), 0700);
  mkdir((cacheDir + "/tracks").c_str(), 0700);
}
Catalog::~Catalog() = default;

std::string Catalog::getJSON(const std::string& path, int& status) {
  auto response = client->get(path);
  status = response.status;
  return response.body;
}
bool Catalog::cachedTrack(const std::string& uri, std::string& json) {
  {
    std::lock_guard<std::mutex> lock(cacheMutex);
    auto found = memoryCache.find(uri);
    if (found != memoryCache.end()) { json = found->second; return true; }
  }
  std::ifstream file(cacheDir + "/tracks/" + uri.substr(14) + ".json");
  if (!file) return false;
  std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
  if (content.empty() || content.size() > 8192) return false;
  std::lock_guard<std::mutex> lock(cacheMutex);
  if (memoryCache.size() > 3000) memoryCache.clear();
  memoryCache[uri] = content; json = content; return true;
}
void Catalog::storeTrack(const std::string& uri, const std::string& json) {
  { std::lock_guard<std::mutex> lock(cacheMutex); if (memoryCache.size() > 3000) memoryCache.clear(); memoryCache[uri] = json; }
  std::ofstream file(cacheDir + "/tracks/" + uri.substr(14) + ".json", std::ios::trunc);
  file << json;
}
// Fetch one track's metadata and convert it to the UI shape.
std::string Catalog::trackJSON(const std::string& uri) {
  std::string cached;
  if (cachedTrack(uri, cached)) return cached;
  return {};
}
static JSON trackFromMetadata(const std::string& uri, const JSON& meta) {
  JSON track;
  track["uri"] = uri; track["id"] = uri.substr(14);
  track["title"] = str(meta, "name", 512);
  track["artist"] = artistNames(meta.count("artist") ? meta["artist"] : JSON());
  JSON artists = JSON::array();
  if (meta.count("artist") && meta["artist"].is_array())
    for (const auto& person : meta["artist"]) {
      auto gid = str(person, "gid", 32), name = str(person, "name", 256);
      if (gid.size() == 32 && !name.empty()) artists.push_back({{"name", name}, {"uri", "spotify:artist:" + base62FromHex(gid)}});
      if (artists.size() >= 4) break;
    }
  track["artists"] = artists;
  std::string art, small;
  if (meta.count("album") && meta["album"].is_object()) {
    const auto& album = meta["album"];
    track["album"] = str(album, "name", 512);
    auto gid = str(album, "gid", 32);
    if (gid.size() == 32) track["albumUri"] = "spotify:album:" + base62FromHex(gid);
    if (album.count("cover_group")) pickImages(album["cover_group"], art, small);
  }
  track["artwork"] = art; track["artworkSmall"] = small;
  track["duration"] = num(meta, "duration");
  track["number"] = num(meta, "number");
  track["disc"] = num(meta, "disc_number");
  return track;
}
void Catalog::hydrate(const std::vector<std::string>& uris, const std::function<void(size_t, bool)>& progress) {
  std::vector<std::string> missing;
  for (const auto& uri : uris) { std::string ignored; if (!cachedTrack(uri, ignored)) missing.push_back(uri); }
  if (missing.empty()) { progress(uris.size(), true); return; }
  std::atomic<size_t> next{0}, loaded{0};
  std::mutex progressMutex;
  auto worker = [&](SpclientClient* http) {
    for (;;) {
      size_t index = next.fetch_add(1);
      if (index >= missing.size()) break;
      const auto& uri = missing[index];
      try {
        auto response = http->get("/metadata/4/track/" + hexFromBase62(uri.substr(14)) + "?market=from_token");
        if (response.status == 200) {
          auto meta = JSON::parse(response.body);
          storeTrack(uri, trackFromMetadata(uri, meta).dump());
        } else std::fprintf(stderr, "CATALOG: track metadata HTTP=%d\n", response.status);
      } catch (...) { std::fprintf(stderr, "CATALOG: track metadata request failed\n"); }
      size_t count = ++loaded;
      if (count % 6 == 0) { std::lock_guard<std::mutex> lock(progressMutex); progress(count, false); }
    }
  };
  std::thread second(worker, client2.get());
  worker(client.get());
  second.join();
  progress(uris.size(), true);
}
static JSON trackList(Catalog* catalog, const std::vector<std::string>& uris,
                      const std::function<std::string(const std::string&)>& lookup) {
  JSON list = JSON::array();
  for (const auto& uri : uris) {
    auto json = lookup(uri);
    if (json.empty()) list.push_back({{"uri", uri}, {"id", uri.substr(14)}, {"loading", true}, {"title", ""}, {"artist", ""}});
    else { try { list.push_back(JSON::parse(json)); } catch (...) {} }
  }
  return list;
}
#define TRACKLIST(uris) trackList(this, uris, [this](const std::string& u) { return trackJSON(u); })

std::vector<std::string> Catalog::contextTrackURIs(const std::string& uri, std::string* metadataJSON) {
  int status = 0;
  auto body = getJSON("/context-resolve/v1/" + uri, status);
  if (status != 200) throw std::runtime_error("context HTTP " + std::to_string(status));
  auto document = JSON::parse(body);
  std::vector<std::string> uris;
  if (document.count("pages") && document["pages"].is_array())
    for (const auto& page : document["pages"]) {
      if (!page.is_object() || !page.count("tracks") || !page["tracks"].is_array()) continue;
      for (const auto& item : page["tracks"]) {
        auto track = str(item, "uri", 36);
        if (track.size() == 36 && track.compare(0, 14, "spotify:track:") == 0 && validID(track.substr(14))) uris.push_back(track);
        if (uris.size() >= 500) break;
      }
      if (uris.size() >= 500) break;
    }
  if (metadataJSON) *metadataJSON = document.count("metadata") ? document["metadata"].dump() : "{}";
  return uris;
}

void Catalog::tracks(const std::vector<std::string>& uris, const Publish& publish) {
  hydrate(uris, [&](size_t, bool done) { publish(JSON{{"tracks", TRACKLIST(uris)}, {"loading", !done}}.dump(), done); });
}

void Catalog::context(const std::string& uri, const Publish& publish) {
  std::string metadata;
  auto uris = contextTrackURIs(uri, &metadata);
  JSON meta = JSON::parse(metadata);
  publish(JSON{{"uri", uri}, {"name", str(meta, "context_description", 256)}, {"uris", uris}, {"loading", false}}.dump(), true);
}

void Catalog::search(const std::string& query, const Publish& publish) {
  const auto encoded = percentEncode(query);
  JSON result{{"query", query}, {"tracks", JSON::array()}, {"albums", JSON::array()}, {"artists", JSON::array()}, {"loading", true}};
  auto raw = contextTrackURIs("spotify:search:" + encoded, nullptr);
  std::vector<std::string> trackURIs; std::set<std::string> seenTracks;
  for (const auto& uri : raw) if (seenTracks.insert(uri).second) { trackURIs.push_back(uri); if (trackURIs.size() >= 20) break; }
  std::fprintf(stderr, "CATALOG: search tracks=%lu\n", static_cast<unsigned long>(trackURIs.size()));
  hydrate(trackURIs, [&](size_t, bool done) { result["tracks"] = TRACKLIST(trackURIs); publish(result.dump(), false); (void)done; });
  // The dedicated album/artist search contexts return unrelated items, so albums and artists
  // are the ones most frequent among the matching tracks (the query's artist dominates).
  std::map<std::string, std::pair<int, JSON>> albums, artists;
  std::vector<std::string> albumOrder, artistOrder;
  for (const auto& uri : trackURIs) {
    auto json = trackJSON(uri); if (json.empty()) continue;
    auto track = JSON::parse(json);
    auto albumUri = str(track, "albumUri", 64);
    if (!albumUri.empty()) {
      auto& entry = albums[albumUri];
      if (entry.first++ == 0) { albumOrder.push_back(albumUri); entry.second = {{"uri", albumUri}, {"name", str(track, "album", 512)}, {"artist", str(track, "artist", 512)}, {"artwork", str(track, "artwork", 512)}}; }
    }
    if (track.count("artists") && track["artists"].is_array())
      for (const auto& person : track["artists"]) {
        auto artistUri = str(person, "uri", 64), name = str(person, "name", 256);
        if (artistUri.empty()) continue;
        auto& entry = artists[artistUri];
        if (entry.first++ == 0) { artistOrder.push_back(artistUri); entry.second = {{"uri", artistUri}, {"name", name}, {"image", ""}}; }
      }
  }
  auto rank = [](std::vector<std::string>& order, std::map<std::string, std::pair<int, JSON>>& counts) {
    std::stable_sort(order.begin(), order.end(), [&](const std::string& a, const std::string& b) { return counts[a].first > counts[b].first; });
  };
  rank(albumOrder, albums); rank(artistOrder, artists);
  JSON albumList = JSON::array();
  for (const auto& uri : albumOrder) { albumList.push_back(albums[uri].second); if (albumList.size() >= 8) break; }
  result["albums"] = albumList; publish(result.dump(), false);
  JSON artistList = JSON::array();
  for (const auto& uri : artistOrder) {
    JSON entry = artists[uri].second;
    if (artistList.size() < 4) { try { auto summary = JSON::parse(artistSummary(hexFromBase62(uri.substr(15)))); entry["image"] = str(summary, "image", 512); } catch (...) {} }
    artistList.push_back(entry);
    if (artistList.size() >= 6) break;
  }
  result["artists"] = artistList;
  result["loading"] = false;
  publish(result.dump(), true);
}

static std::string base64ToHex(const std::string& input) {
  static const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string bytes; unsigned buffer = 0; int bits = 0;
  for (char c : input) {
    if (c == '=') break;
    auto value = alphabet.find(c); if (value == std::string::npos) return {};
    buffer = (buffer << 6) | static_cast<unsigned>(value); bits += 6;
    if (bits >= 8) { bits -= 8; bytes += static_cast<char>((buffer >> bits) & 0xff); }
  }
  static const char* digits = "0123456789abcdef"; std::string hex;
  for (unsigned char b : bytes) { hex += digits[b >> 4]; hex += digits[b & 15]; }
  return hex;
}
std::string Catalog::albumSummary(const std::string& gidHex) {
  int status = 0;
  auto body = getJSON("/metadata/4/album/" + gidHex + "?market=from_token", status);
  if (status != 200) throw std::runtime_error("album HTTP " + std::to_string(status));
  auto meta = JSON::parse(body);
  std::string art, small; if (meta.count("cover_group")) pickImages(meta["cover_group"], art, small);
  JSON summary{{"uri", "spotify:album:" + base62FromHex(gidHex)}, {"name", str(meta, "name", 512)},
      {"artist", artistNames(meta.count("artist") ? meta["artist"] : JSON())}, {"artwork", art}, {"artworkSmall", small},
      {"year", yearOf(meta)}, {"type", str(meta, "type", 32)}, {"label", str(meta, "label", 256)}};
  if (meta.count("artist") && meta["artist"].is_array() && !meta["artist"].empty()) {
    auto gid = str(meta["artist"][0], "gid", 32); if (gid.size() == 32) summary["artistUri"] = "spotify:artist:" + base62FromHex(gid);
  }
  std::vector<std::string> uris;
  if (meta.count("disc") && meta["disc"].is_array())
    for (const auto& disc : meta["disc"])
      if (disc.is_object() && disc.count("track") && disc["track"].is_array())
        for (const auto& track : disc["track"]) { auto gid = str(track, "gid", 32); if (gid.size() == 32) uris.push_back("spotify:track:" + base62FromHex(gid)); }
  summary["uris"] = uris;
  return summary.dump();
}
void Catalog::album(const std::string& id, const Publish& publish) {
  if (!validID(id)) throw std::invalid_argument("bad album id");
  auto summary = JSON::parse(albumSummary(hexFromBase62(id)));
  std::vector<std::string> uris = summary["uris"].get<std::vector<std::string>>();
  summary.erase("uris");
  hydrate(uris, [&](size_t, bool done) { summary["tracks"] = TRACKLIST(uris); summary["loading"] = !done; publish(summary.dump(), done); });
}

std::string Catalog::artistSummary(const std::string& gidHex) {
  int status = 0;
  auto body = getJSON("/metadata/4/artist/" + gidHex + "?market=from_token", status);
  if (status != 200) throw std::runtime_error("artist HTTP " + std::to_string(status));
  auto meta = JSON::parse(body);
  std::string image, small; if (meta.count("portrait_group")) pickImages(meta["portrait_group"], image, small);
  JSON summary{{"uri", "spotify:artist:" + base62FromHex(gidHex)}, {"name", str(meta, "name", 256)}, {"image", image}, {"imageSmall", small}, {"biography", ""}};
  if (meta.count("biography") && meta["biography"].is_array() && !meta["biography"].empty())
    summary["biography"] = cleanBiography(str(meta["biography"][0], "text", 4000));
  std::vector<std::string> top;
  if (meta.count("top_track") && meta["top_track"].is_array())
    for (const auto& group : meta["top_track"]) {
      if (!group.is_object() || !group.count("track") || !group["track"].is_array()) continue;
      for (const auto& track : group["track"]) { auto gid = str(track, "gid", 32); if (gid.size() == 32) top.push_back("spotify:track:" + base62FromHex(gid)); }
      if (!top.empty()) break;
    }
  summary["topUris"] = top;
  auto collect = [&](const char* key, size_t limit) {
    std::vector<std::string> gids;
    if (meta.count(key) && meta[key].is_array())
      for (const auto& group : meta[key]) {
        if (!group.is_object() || !group.count("album") || !group["album"].is_array() || group["album"].empty()) continue;
        auto gid = str(group["album"][0], "gid", 32); if (gid.size() == 32) gids.push_back(gid);
        if (gids.size() >= limit) break;
      }
    return gids;
  };
  summary["albumGids"] = collect("album_group", 8);
  summary["singleGids"] = collect("single_group", 8);
  return summary.dump();
}
void Catalog::artist(const std::string& id, const Publish& publish) {
  if (!validID(id)) throw std::invalid_argument("bad artist id");
  auto summary = JSON::parse(artistSummary(hexFromBase62(id)));
  std::vector<std::string> top = summary["topUris"].get<std::vector<std::string>>();
  if (top.size() > 10) top.resize(10);
  std::vector<std::string> albumGids = summary["albumGids"].get<std::vector<std::string>>(), singleGids = summary["singleGids"].get<std::vector<std::string>>();
  summary.erase("topUris"); summary.erase("albumGids"); summary.erase("singleGids");
  summary["albums"] = JSON::array(); summary["singles"] = JSON::array();
  hydrate(top, [&](size_t, bool done) { summary["topTracks"] = TRACKLIST(top); summary["loading"] = true; publish(summary.dump(), false); (void)done; });
  auto fill = [&](const std::vector<std::string>& gids, const char* key) {
    for (const auto& gid : gids) {
      try { auto album = JSON::parse(albumSummary(gid)); album.erase("uris"); summary[key].push_back(album); publish(summary.dump(), false); }
      catch (...) { std::fprintf(stderr, "CATALOG: album summary failed\n"); }
    }
  };
  fill(albumGids, "albums"); fill(singleGids, "singles");
  summary["loading"] = false;
  publish(summary.dump(), true);
}

void Catalog::playlist(const std::string& id, const Publish& publish) {
  if (!validID(id)) throw std::invalid_argument("bad playlist id");
  std::string metadata;
  auto uris = contextTrackURIs("spotify:playlist:" + id, &metadata);
  JSON meta = JSON::parse(metadata);
  const auto name = str(meta, "context_description", 256);
  auto description = str(meta, "context_long_description", 1024);
  if (description == name) description.clear();
  // context_owner is a user uri; show the profile's display name when it is just an id.
  auto owner = str(meta, "context_owner", 128);
  if (owner.compare(0, 13, "spotify:user:") == 0) owner = owner.substr(13);
  if (owner == "spotify") owner = "Spotify";
  else if (!owner.empty()) {
    try {
      int status = 0;
      auto profile = JSON::parse(getJSON("/user-profile-view/v3/profile/" + owner, status));
      auto display = status == 200 ? str(profile, "name", 128) : std::string();
      if (!display.empty()) owner = display;
    } catch (...) {}
  }
  auto artwork = imageURL(str(meta, "image_url", 2048));
  if (artwork.empty()) artwork = playlistCover(id);
  JSON summary{{"uri", "spotify:playlist:" + id}, {"name", name}, {"description", description}, {"owner", owner},
      {"artwork", artwork}, {"count", uris.size()}};
  hydrate(uris, [&](size_t, bool done) { summary["tracks"] = TRACKLIST(uris); summary["loading"] = !done; publish(summary.dump(), done); });
}

void Catalog::collection(const Publish& publish) {
  const auto username = context_->config.username;
  auto uris = contextTrackURIs("spotify:user:" + username + ":collection", nullptr);
  JSON summary{{"uri", "spotify:user:" + username + ":collection"}, {"name", "Liked Songs"}, {"count", uris.size()}, {"artwork", ""}};
  hydrate(uris, [&](size_t, bool done) { summary["tracks"] = TRACKLIST(uris); summary["loading"] = !done; publish(summary.dump(), done); });
}

void Catalog::recent(const Publish& publish) {
  const auto username = context_->config.username;
  int status = 0;
  auto body = getJSON("/recently-played/v3/user/" + username + "/recently-played?format=json&limit=24", status);
  if (status != 200) throw std::runtime_error("recent HTTP " + std::to_string(status));
  auto document = JSON::parse(body);
  JSON items = JSON::array();
  std::set<std::string> seen;
  if (document.count("playContexts") && document["playContexts"].is_array())
    for (const auto& entry : document["playContexts"]) {
      auto uri = str(entry, "uri", 128);
      if (uri.empty() || seen.count(uri)) continue;
      seen.insert(uri);
      try {
        if (uri.compare(0, 14, "spotify:album:") == 0 && validID(uri.substr(14))) {
          auto album = JSON::parse(albumSummary(hexFromBase62(uri.substr(14))));
          items.push_back({{"uri", uri}, {"name", album["name"]}, {"subtitle", album["artist"]}, {"artwork", album["artwork"]}, {"type", "album"}});
        } else if (uri.compare(0, 15, "spotify:artist:") == 0 && validID(uri.substr(15))) {
          auto artist = JSON::parse(artistSummary(hexFromBase62(uri.substr(15))));
          items.push_back({{"uri", uri}, {"name", artist["name"]}, {"subtitle", "Artist"}, {"artwork", artist["image"]}, {"type", "artist"}});
        } else if (uri.compare(0, 17, "spotify:playlist:") == 0 && validID(uri.substr(17))) {
          std::string metadata; contextTrackURIs(uri, &metadata);
          auto meta = JSON::parse(metadata);
          auto artwork = imageURL(str(meta, "image_url", 2048));
          if (artwork.empty()) artwork = playlistCover(uri.substr(17));
          items.push_back({{"uri", uri}, {"name", str(meta, "context_description", 256)}, {"subtitle", "Playlist"}, {"artwork", artwork}, {"type", "playlist"}});
        } else if (uri.find(":collection") != std::string::npos) {
          items.push_back({{"uri", uri}, {"name", "Liked Songs"}, {"subtitle", "Playlist"}, {"artwork", ""}, {"type", "collection"}});
        } else continue;
        publish(JSON{{"items", items}, {"loading", true}}.dump(), false);
      } catch (...) { std::fprintf(stderr, "CATALOG: recent item failed\n"); }
      if (items.size() >= 12) break;
    }
  publish(JSON{{"items", items}, {"loading", false}}.dump(), true);
}

// Spotify-generated playlists carry their cover only in the playlist record's pictureSize list.
std::string Catalog::playlistCover(const std::string& id) {
  if (!validID(id)) return {};
  { std::lock_guard<std::mutex> lock(cacheMutex); auto found = coverCache.find(id); if (found != coverCache.end()) return found->second; }
  std::string cover;
  try {
    int status = 0;
    auto body = getJSON("/playlist/v2/playlist/" + id + "?decorate=attributes,picture", status);
    if (status == 200) {
      auto document = JSON::parse(body);
      const JSON& attributes = document.count("attributes") ? document["attributes"] : JSON::object();
      std::string preferred, any;
      if (attributes.count("pictureSize") && attributes["pictureSize"].is_array())
        for (const auto& entry : attributes["pictureSize"]) {
          auto url = imageURL(str(entry, "url", 2048)), target = str(entry, "targetName", 16);
          if (url.empty()) continue;
          if (any.empty()) any = url;
          if (target == "default") preferred = url;
        }
      cover = preferred.empty() ? any : preferred;
      if (cover.empty()) { auto hex = base64ToHex(str(attributes, "picture", 64)); if (hex.size() == 40) cover = imageURL(hex); }
    }
  } catch (...) { std::fprintf(stderr, "CATALOG: playlist cover lookup failed\n"); }
  std::lock_guard<std::mutex> lock(cacheMutex);
  if (coverCache.size() > 500) coverCache.clear();
  coverCache[id] = cover;
  return cover;
}
void Catalog::playlists(const Publish& publish) {
  const auto username = context_->config.username;
  int status = 0;
  auto body = getJSON("/playlist/v2/user/" + username + "/rootlist?decorate=revision,attributes,length,owner,capabilities,status_code&from=0&length=300", status);
  if (status != 200) throw std::runtime_error("rootlist HTTP " + std::to_string(status));
  auto document = JSON::parse(body);
  JSON list = JSON::array();
  if (document.count("contents") && document["contents"].is_object()) {
    const auto& contents = document["contents"];
    const JSON& items = contents.count("items") ? contents["items"] : JSON::array();
    const JSON& meta = contents.count("metaItems") ? contents["metaItems"] : JSON::array();
    for (size_t i = 0; i < items.size() && items.is_array(); ++i) {
      auto uri = str(items[i], "uri", 128);
      if (uri.compare(0, 17, "spotify:playlist:") != 0 || !validID(uri.substr(17))) continue;  // folders are start/end-group markers
      JSON entry{{"uri", uri}, {"name", ""}, {"artwork", ""}, {"owner", ""}, {"count", 0}};
      if (meta.is_array() && i < meta.size() && meta[i].is_object()) {
        const auto& m = meta[i];
        if (m.count("attributes") && m["attributes"].is_object()) {
          entry["name"] = str(m["attributes"], "name", 256);
          auto picture = base64ToHex(str(m["attributes"], "picture", 64));
          if (picture.size() == 40) entry["artwork"] = imageURL(picture);
        }
        entry["owner"] = str(m, "ownerUsername", 128);
        entry["count"] = num(m, "length");
      }
      if (entry["name"].get<std::string>().empty()) entry["name"] = "Playlist";
      if (entry["artwork"].get<std::string>().empty()) entry["artwork"] = playlistCover(uri.substr(17));
      list.push_back(entry);
    }
  }
  std::fprintf(stderr, "CATALOG: playlists=%lu\n", static_cast<unsigned long>(list.size()));
  publish(JSON{{"playlists", list}, {"loading", false}}.dump(), true);
}
void Catalog::profile(const Publish& publish) {
  const auto username = context_->config.username;
  int status = 0;
  auto body = getJSON("/user-profile-view/v3/profile/" + username, status);
  if (status != 200) throw std::runtime_error("profile HTTP " + std::to_string(status));
  auto document = JSON::parse(body);
  JSON playlists = JSON::array();
  if (document.count("public_playlists") && document["public_playlists"].is_array())
    for (const auto& entry : document["public_playlists"]) {
      auto uri = str(entry, "uri", 128);
      if (uri.compare(0, 17, "spotify:playlist:") != 0) continue;
      playlists.push_back({{"uri", uri}, {"name", str(entry, "name", 256)}, {"artwork", imageURL(str(entry, "image_url", 512))}, {"owner", str(entry, "owner_name", 128)}});
    }
  publish(JSON{{"name", str(document, "name", 128)}, {"image", imageURL(str(document, "image_url", 2048))}, {"playlists", playlists}, {"loading", false}}.dump(), true);
}
}
