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
  if (id.compare(0, 8, "https://") == 0) return id.size() < 512 ? id : std::string();
  std::string bare = id.compare(0, 14, "spotify:image:") == 0 ? id.substr(14) : id;
  if (bare.size() != 40 || bare.find_first_not_of("0123456789abcdef") != std::string::npos) return {};
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
  auto trackURIs = contextTrackURIs("spotify:search:" + encoded, nullptr);
  if (trackURIs.size() > 20) trackURIs.resize(20);
  std::fprintf(stderr, "CATALOG: search tracks=%lu\n", static_cast<unsigned long>(trackURIs.size()));
  hydrate(trackURIs, [&](size_t, bool done) { result["tracks"] = TRACKLIST(trackURIs); publish(result.dump(), false); (void)done; });
  // Albums and artists come back as representative tracks; group them.
  try {
    auto albumTracks = contextTrackURIs("spotify:search:albums:" + encoded, nullptr);
    if (albumTracks.size() > 12) albumTracks.resize(12);
    hydrate(albumTracks, [](size_t, bool) {});
    std::set<std::string> seen; JSON albums = JSON::array();
    for (const auto& uri : albumTracks) {
      auto json = trackJSON(uri); if (json.empty()) continue;
      auto track = JSON::parse(json);
      auto albumUri = str(track, "albumUri", 64);
      if (albumUri.empty() || seen.count(albumUri)) continue;
      seen.insert(albumUri);
      albums.push_back({{"uri", albumUri}, {"name", str(track, "album", 512)}, {"artist", str(track, "artist", 512)}, {"artwork", str(track, "artwork", 512)}});
      if (albums.size() >= 8) break;
    }
    result["albums"] = albums; publish(result.dump(), false);
  } catch (...) { std::fprintf(stderr, "CATALOG: album search failed\n"); }
  try {
    auto artistTracks = contextTrackURIs("spotify:search:artists:" + encoded, nullptr);
    if (artistTracks.size() > 10) artistTracks.resize(10);
    hydrate(artistTracks, [](size_t, bool) {});
    std::set<std::string> seen; JSON artists = JSON::array();
    for (const auto& uri : artistTracks) {
      auto json = trackJSON(uri); if (json.empty()) continue;
      auto track = JSON::parse(json);
      if (!track.count("artists") || !track["artists"].is_array() || track["artists"].empty()) continue;
      auto artistUri = str(track["artists"][0], "uri", 64), name = str(track["artists"][0], "name", 256);
      if (artistUri.empty() || seen.count(artistUri)) continue;
      seen.insert(artistUri);
      JSON entry{{"uri", artistUri}, {"name", name}, {"image", ""}};
      if (artists.size() < 4) { try { auto summary = JSON::parse(artistSummary(hexFromBase62(artistUri.substr(15)))); entry["image"] = str(summary, "image", 512); } catch (...) {} }
      artists.push_back(entry);
      if (artists.size() >= 6) break;
    }
    result["artists"] = artists;
  } catch (...) { std::fprintf(stderr, "CATALOG: artist search failed\n"); }
  result["loading"] = false;
  publish(result.dump(), true);
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
  JSON summary{{"uri", "spotify:playlist:" + id}, {"name", str(meta, "context_description", 256)},
      {"description", str(meta, "context_long_description", 1024)}, {"owner", str(meta, "context_owner", 128)},
      {"artwork", imageURL(str(meta, "image_url", 512))}, {"count", uris.size()}};
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
          items.push_back({{"uri", uri}, {"name", str(meta, "context_description", 256)}, {"subtitle", "Playlist"}, {"artwork", imageURL(str(meta, "image_url", 512))}, {"type", "playlist"}});
        } else if (uri.find(":collection") != std::string::npos) {
          items.push_back({{"uri", uri}, {"name", "Liked Songs"}, {"subtitle", "Playlist"}, {"artwork", ""}, {"type", "collection"}});
        } else continue;
        publish(JSON{{"items", items}, {"loading", true}}.dump(), false);
      } catch (...) { std::fprintf(stderr, "CATALOG: recent item failed\n"); }
      if (items.size() >= 12) break;
    }
  publish(JSON{{"items", items}, {"loading", false}}.dump(), true);
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
  publish(JSON{{"name", str(document, "name", 128)}, {"image", imageURL(str(document, "image_url", 512))}, {"playlists", playlists}, {"loading", false}}.dump(), true);
}
}
