// SPDX-License-Identifier: GPL-3.0-or-later
#include "Catalog.h"
#include "SpclientClient.h"
#include "Pathfinder.h"
#include "CSpotContext.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <dirent.h>
#include <sys/stat.h>
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
// Minimal protobuf wire format helpers: enough for the extended-metadata request and response.
namespace proto {
struct Field { unsigned number; unsigned type; uint64_t varint; std::string bytes; };
bool readVarint(const std::string& d, size_t& i, uint64_t& out) {
  out = 0; int shift = 0;
  while (i < d.size() && shift < 64) { unsigned char b = d[i++]; out |= static_cast<uint64_t>(b & 0x7f) << shift; if (!(b & 0x80)) return true; shift += 7; }
  return false;
}
// Iterates fields of a message; unknown wire types abort.
bool each(const std::string& d, const std::function<void(const Field&)>& fn) {
  size_t i = 0;
  while (i < d.size()) {
    uint64_t key; if (!readVarint(d, i, key)) return false;
    Field f; f.number = static_cast<unsigned>(key >> 3); f.type = key & 7; f.varint = 0;
    if (f.type == 0) { if (!readVarint(d, i, f.varint)) return false; }
    else if (f.type == 2) { uint64_t len; if (!readVarint(d, i, len) || i + len > d.size()) return false; f.bytes = d.substr(i, len); i += len; }
    else if (f.type == 1) { if (i + 8 > d.size()) return false; i += 8; }
    else if (f.type == 5) { if (i + 4 > d.size()) return false; i += 4; }
    else return false;
    fn(f);
  }
  return true;
}
std::string varint(uint64_t n) { std::string o; do { unsigned char b = n & 0x7f; n >>= 7; o += static_cast<char>(n ? b | 0x80 : b); } while (n); return o; }
std::string lengthDelimited(unsigned number, const std::string& data) { return varint((number << 3) | 2) + varint(data.size()) + data; }
std::string varintField(unsigned number, uint64_t n) { return varint(number << 3) + varint(n); }
std::string hex(const std::string& bytes) { static const char* d = "0123456789abcdef"; std::string o; for (unsigned char b : bytes) { o += d[b >> 4]; o += d[b & 15]; } return o; }
int64_t zigzag(uint64_t n) { return static_cast<int64_t>(n >> 1) ^ -static_cast<int64_t>(n & 1); }
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
    : context_(std::move(context)), client(new SpclientClient(context_)), client2(new SpclientClient(context_)), pathfinder(new Pathfinder(context_)), cacheDir(std::move(dir)) {
  mkdir(cacheDir.c_str(), 0700);
  mkdir((cacheDir + "/tracks").c_str(), 0700);
  try {
    std::ifstream file(cacheDir + "/covers.json");
    if (file) { JSON saved; file >> saved; if (saved.is_object()) for (auto it = saved.begin(); it != saved.end(); ++it) if (it->is_string()) coverCache[it.key()] = it->get<std::string>(); }
  } catch (...) { coverCache.clear(); }
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
// Decodes one metadata Track message (librespot proto numbering) into the UI track shape.
static bool trackFromProto(const std::string& uri, const std::string& data, JSON& track) {
  std::string name, albumName, albumGid, art, small; JSON artists = JSON::array(); std::string artistNames;
  int64_t number = 0, disc = 0, duration = 0; bool ok = true;
  ok = proto::each(data, [&](const proto::Field& f) {
    switch (f.number) {
      case 2: name = f.bytes; break;
      case 3:  // album { gid=1, name=2, cover_group=17 { image=1 { file_id=1, size=2 } } }
        proto::each(f.bytes, [&](const proto::Field& a) {
          if (a.number == 1) albumGid = proto::hex(a.bytes);
          else if (a.number == 2) albumName = a.bytes;
          else if (a.number == 17) proto::each(a.bytes, [&](const proto::Field& g) {
            if (g.number != 1) return;
            std::string file; uint64_t size = 0;
            proto::each(g.bytes, [&](const proto::Field& im) { if (im.number == 1) file = proto::hex(im.bytes); else if (im.number == 2) size = im.varint; });
            if (file.size() != 40) return;
            if (size == 0 && art.empty()) art = file;        // DEFAULT
            else if (size == 1 && small.empty()) small = file;  // SMALL
            else if (art.empty()) art = file;
          });
        }); break;
      case 4: {  // artist { gid=1, name=2 }
        std::string gid, artistName;
        proto::each(f.bytes, [&](const proto::Field& ar) { if (ar.number == 1) gid = proto::hex(ar.bytes); else if (ar.number == 2) artistName = ar.bytes; });
        if (!artistName.empty()) {
          if (artists.size() < 4 && gid.size() == 32) artists.push_back({{"name", artistName}, {"uri", "spotify:artist:" + base62FromHex(gid)}});
          if (artists.size() <= 3) { if (!artistNames.empty()) artistNames += ", "; artistNames += artistName; }
        }
        break; }
      case 5: number = proto::zigzag(f.varint); break;
      case 6: disc = proto::zigzag(f.varint); break;
      case 7: duration = proto::zigzag(f.varint); break;
      default: break;
    }
  });
  if (!ok || name.empty()) return false;
  if (small.empty()) small = art;
  track = {{"uri", uri}, {"id", uri.substr(14)}, {"title", name.substr(0, 512)}, {"artist", artistNames.substr(0, 512)}, {"artists", artists},
           {"album", albumName.substr(0, 512)}, {"artwork", imageURL(art)}, {"artworkSmall", imageURL(small)},
           {"duration", duration}, {"number", number}, {"disc", disc}};
  if (albumGid.size() == 32) track["albumUri"] = "spotify:album:" + base62FromHex(albumGid);
  return true;
}
size_t Catalog::hydrateBatch(const std::vector<std::string>& uris) {
  size_t stored = 0;
  for (size_t start = 0; start < uris.size(); start += 50) {
    std::vector<std::string> chunk(uris.begin() + start, uris.begin() + std::min(uris.size(), start + 50));
    // BatchedEntityRequest { header=1 { country=1, catalogue=2 }, entity_request=2 [ { entity_uri=1, query=2 [ { extension_kind=1 } ] } ] }
    // ExtensionKind TRACK_V4 = 10 (1 is CANVAZ).
    std::string body = proto::lengthDelimited(1, proto::lengthDelimited(1, "BR") + proto::lengthDelimited(2, "premium"));
    for (const auto& uri : chunk) body += proto::lengthDelimited(2, proto::lengthDelimited(1, uri) + proto::lengthDelimited(2, proto::varintField(1, 10)));
    SpclientClient::Response response;
    try { response = client->post("/extended-metadata/v0/extended-metadata", body, "application/x-protobuf", "application/x-protobuf"); }
    catch (...) { std::fprintf(stderr, "CATALOG: batch metadata request failed\n"); return stored; }
    if (response.status != 200) { std::fprintf(stderr, "CATALOG: batch metadata HTTP=%d\n", response.status); return stored; }
    // Observed on the wire: BatchedExtensionResponse { extended_metadata=2 [ { header=1, extension_kind=2,
    //   extension_data=3 [ { header=1, entity_uri=2, extension_data=3 Any{type_url=1, value=2} } ] } ] }
    size_t before = stored;
    proto::each(response.body, [&](const proto::Field& top) {
      if (top.number != 2) return;
      proto::each(top.bytes, [&](const proto::Field& arr) {
        if (arr.number != 3) return;
        std::string uri, payload;
        proto::each(arr.bytes, [&](const proto::Field& e) {
          if (e.number == 2) uri = e.bytes;
          else if (e.number == 3) proto::each(e.bytes, [&](const proto::Field& any) { if (any.number == 2) payload = any.bytes; });
        });
        if (uri.size() != 36 || uri.compare(0, 14, "spotify:track:") != 0 || payload.empty()) return;
        JSON track;
        if (trackFromProto(uri, payload, track)) { storeTrack(uri, track.dump()); ++stored; }
      });
    });
    std::fprintf(stderr, "CATALOG: batch metadata chunk=%lu decoded=%lu\n", static_cast<unsigned long>(chunk.size()), static_cast<unsigned long>(stored - before));
    if (stored == before) return stored;  // nothing decoded: let the caller fall back
  }
  return stored;
}
void Catalog::hydrate(const std::vector<std::string>& uris, const std::function<void(size_t, bool)>& progress) {
  std::vector<std::string> missing;
  for (const auto& uri : uris) { std::string ignored; if (!cachedTrack(uri, ignored)) missing.push_back(uri); }
  if (missing.empty()) { progress(uris.size(), true); return; }
  if (missing.size() >= 3) {
    // One round trip per 50 tracks; anything the batch did not return falls through to per-track fetches.
    hydrateBatch(missing);
    std::vector<std::string> still;
    for (const auto& uri : missing) { std::string ignored; if (!cachedTrack(uri, ignored)) still.push_back(uri); }
    progress(uris.size() - still.size(), still.empty());
    if (still.empty()) return;
    missing.swap(still);
  }
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

std::string Catalog::pathfinderStatus() { return pathfinder->status(); }
std::string Catalog::pathfinderRefresh() { return pathfinder->refreshHashes(true); }
std::string Catalog::pathfinderRaw(const std::string& op, const std::string& variablesJSON) { return pathfinder->raw(op, variablesJSON); }
void Catalog::homeFeed(const Publish& publish) {
  if (!pathfinder->available()) throw std::runtime_error("search service paused");
  auto feed = pathfinder->home(); feed["loading"] = false;
  publish(feed.dump(), true);
}
void Catalog::library(const Publish& publish) {
  if (!pathfinder->available()) throw std::runtime_error("search service paused");
  auto lib = pathfinder->library(200); lib["loading"] = false;
  publish(lib.dump(), true);
}
void Catalog::search(const std::string& query, const Publish& publish) {
  // Preferred path: the web player's search, which answers with tracks, artists, albums and
  // playlists in one call and needs no metadata hydration. Falls through to the
  // context-resolve search when it is paused or fails.
  if (pathfinder->available()) {
    try {
      auto found = pathfinder->search(query);
      for (const auto& track : found["tracks"]) storeTrack(track["uri"].get<std::string>(), track.dump());   // the queue screen reads these
      JSON result{{"query", query}, {"tracks", found["tracks"]}, {"albums", found["albums"]}, {"artists", found["artists"]}, {"playlists", found["playlists"]},
          {"loading", false}, {"source", "pathfinder"}};
      publish(result.dump(), true);
      pathfinder->refreshIfStale();
      return;
    } catch (const std::exception& error) {
      std::fprintf(stderr, "CATALOG: pathfinder search failed (%s); using context-resolve\n", error.what());
    }
  }
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
  { std::lock_guard<std::mutex> lock(cacheMutex); auto found = artistCache.find(gidHex); if (found != artistCache.end()) return found->second; }
  auto computed = artistSummaryUncached(gidHex);
  std::lock_guard<std::mutex> lock(cacheMutex);
  if (artistCache.size() > 200) artistCache.clear();
  artistCache[gidHex] = computed;
  return computed;
}
std::string Catalog::artistSummaryUncached(const std::string& gidHex) {
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
    if (cover.empty()) {
      // No cover at all: Spotify shows a mosaic of the first tracks' album art. Build the same.
      auto uris = contextTrackURIs("spotify:playlist:" + id, nullptr);
      if (uris.size() > 8) uris.resize(8);
      hydrate(uris, [](size_t, bool) {});
      std::vector<std::string> ids; std::set<std::string> seen;
      for (const auto& uri : uris) {
        auto json = trackJSON(uri); if (json.empty()) continue;
        auto art = str(JSON::parse(json), "artwork", 512);
        auto slash = art.rfind('/');
        if (slash == std::string::npos || art.size() - slash - 1 != 40) continue;
        auto imageId = art.substr(slash + 1);
        if (seen.insert(imageId).second) ids.push_back(imageId);
        if (ids.size() == 4) break;
      }
      if (ids.size() == 4) cover = "spotify:mosaic:" + ids[0] + ":" + ids[1] + ":" + ids[2] + ":" + ids[3];
      else if (!ids.empty()) cover = "https://i.scdn.co/image/" + ids[0];
    }
  } catch (...) { std::fprintf(stderr, "CATALOG: playlist cover lookup failed\n"); }
  std::lock_guard<std::mutex> lock(cacheMutex);
  if (coverCache.size() > 500) coverCache.clear();
  coverCache[id] = cover;
  try { std::ofstream file(cacheDir + "/covers.json", std::ios::trunc); file << JSON(coverCache).dump(); } catch (...) {}
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
void Catalog::home(const Publish& publish) {
  const auto username = context_->config.username;
  int status = 0;
  auto body = getJSON("/recently-played/v3/user/" + username + "/recently-played?format=json&limit=30", status);
  if (status != 200) throw std::runtime_error("recent HTTP " + std::to_string(status));
  auto document = JSON::parse(body);
  // Artists behind what was played recently: artist contexts directly, album contexts via the album.
  std::vector<std::string> artistIds; std::set<std::string> seen;
  auto addArtist = [&](const std::string& uri) {
    if (uri.compare(0, 15, "spotify:artist:") != 0 || !validID(uri.substr(15)) || !seen.insert(uri).second) return;
    artistIds.push_back(uri.substr(15));
  };
  if (document.count("playContexts") && document["playContexts"].is_array())
    for (const auto& entry : document["playContexts"]) {
      if (artistIds.size() >= 8) break;
      auto uri = str(entry, "uri", 128);
      try {
        if (uri.compare(0, 15, "spotify:artist:") == 0) addArtist(uri);
        else if (uri.compare(0, 14, "spotify:album:") == 0 && validID(uri.substr(14))) {
          auto album = JSON::parse(albumSummary(hexFromBase62(uri.substr(14))));
          addArtist(str(album, "artistUri", 64));
        } else {
          // playlists and the liked-songs collection: use the artist of the last played track
          auto track = str(entry, "lastPlayedTrackUri", 64);
          if (track.size() == 36 && track.compare(0, 14, "spotify:track:") == 0 && validID(track.substr(14))) {
            hydrate({track}, [](size_t, bool) {});
            auto json = trackJSON(track);
            if (!json.empty()) { auto t = JSON::parse(json); if (t.count("artists") && t["artists"].is_array() && !t["artists"].empty()) addArtist(str(t["artists"][0], "uri", 64)); }
          }
        }
      } catch (...) {}
    }
  JSON radios = JSON::array(), releases = JSON::array();
  for (const auto& id : artistIds) {
    try {
      auto artist = JSON::parse(artistSummary(hexFromBase62(id)));
      radios.push_back({{"uri", "spotify:station:artist:" + id}, {"name", artist["name"].get<std::string>() + " Radio"}, {"subtitle", "Based on " + artist["name"].get<std::string>()}, {"artwork", artist["image"]}, {"type", "station"}});
      publish(JSON{{"radios", radios}, {"releases", releases}, {"loading", true}}.dump(), false);
      std::vector<std::string> gids = artist["albumGids"].get<std::vector<std::string>>();
      std::vector<std::string> singles = artist["singleGids"].get<std::vector<std::string>>();
      if (!singles.empty()) gids.insert(gids.begin(), singles[0]);
      int bestYear = 0; JSON best;
      for (size_t i = 0; i < gids.size() && i < 2; ++i) {
        auto album = JSON::parse(albumSummary(gids[i])); album.erase("uris");
        int year = album.value("year", 0);
        if (year > bestYear) { bestYear = year; best = album; }
      }
      if (!best.is_null()) releases.push_back({{"uri", best["uri"]}, {"name", best["name"]}, {"subtitle", best["artist"].get<std::string>() + (bestYear ? " • " + std::to_string(bestYear) : "")}, {"artwork", best["artwork"]}, {"type", "album"}, {"year", bestYear}});
    } catch (...) { std::fprintf(stderr, "CATALOG: home artist failed\n"); }
  }
  std::stable_sort(releases.begin(), releases.end(), [](const JSON& a, const JSON& b) { return a.value("year", 0) > b.value("year", 0); });
  publish(JSON{{"radios", radios}, {"releases", releases}, {"loading", false}}.dump(), true);
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
std::string canonicalImageURL(const std::string& idOrUrl) { return imageURL(idOrUrl); }
static std::vector<int> versionParts(const std::string& text) {
  std::vector<int> parts; std::string digits;
  for (char c : text + ".") { if (isdigit((unsigned char)c)) digits += c; else if (!digits.empty()) { parts.push_back(std::atoi(digits.c_str())); digits.clear(); } }
  while (parts.size() < 3) parts.push_back(0);
  return parts;
}
void Catalog::updateCheck(const std::string& currentVersion, const Publish& publish) {
  auto response = SpclientClient::fetch("GET", "https://api.github.com/repos/micheldpcarlos/bennu-music/releases/latest",
      {{"User-Agent", "BennuMusic/" + currentVersion}, {"Accept", "application/vnd.github+json"}}, "", 512 * 1024, 20);
  if (response.status != 200) throw std::runtime_error("GitHub answered HTTP " + std::to_string(response.status));
  auto release = JSON::parse(response.body);
  std::string tag = str(release, "tag_name", 64); if (!tag.empty() && tag[0] == 'v') tag.erase(0, 1);
  std::string debUrl, debName;
  if (release.count("assets") && release["assets"].is_array())
    for (const auto& asset : release["assets"]) {
      auto name = str(asset, "name", 128);
      if (name.size() > 4 && name.compare(name.size() - 4, 4, ".deb") == 0) { debUrl = str(asset, "browser_download_url", 512); debName = name; break; }
    }
  bool newer = versionParts(tag) > versionParts(currentVersion);
  JSON out{{"latest", tag}, {"current", currentVersion}, {"newer", newer}, {"debUrl", debUrl}, {"debName", debName}, {"page", str(release, "html_url", 256)},
      {"notes", str(release, "body", 600)}, {"loading", false}};
  std::fprintf(stderr, "UPDATE: latest=%s current=%s newer=%d\n", tag.c_str(), currentVersion.c_str(), newer ? 1 : 0);
  publish(out.dump(), true);
}
void Catalog::downloadUpdate(const std::string& url, const Publish& publish) {
  static const std::string kReleases = "https://github.com/micheldpcarlos/bennu-music/";
  if (url.compare(0, kReleases.size(), kReleases) != 0 && url.find("githubusercontent.com") == std::string::npos) throw std::runtime_error("unexpected download host");
  auto response = SpclientClient::fetch("GET", url, {{"User-Agent", "BennuMusic"}, {"Accept", "application/octet-stream"}}, "", 24 * 1024 * 1024, 180);
  if (response.status != 200 || response.body.size() < 1024) throw std::runtime_error("download answered HTTP " + std::to_string(response.status));
  auto slash = url.rfind('/'); std::string name = slash == std::string::npos ? "update.deb" : url.substr(slash + 1);
  if (name.find("..") != std::string::npos || name.find('/') != std::string::npos) name = "update.deb";
  std::string dir = "/var/mobile/Downloads"; mkdir(dir.c_str(), 0755);
  std::string path = dir + "/" + name;
  { std::ofstream file(path, std::ios::binary | std::ios::trunc); file.write(response.body.data(), (std::streamsize)response.body.size()); if (!file) throw std::runtime_error("could not write " + path); }
  std::fprintf(stderr, "UPDATE: saved %s (%lu bytes)\n", path.c_str(), (unsigned long)response.body.size());
  publish(JSON{{"path", path}, {"bytes", response.body.size()}, {"loading", false}}.dump(), true);
}
void Catalog::clearCache(const Publish& publish) {
  { std::lock_guard<std::mutex> lock(cacheMutex); memoryCache.clear(); coverCache.clear(); artistCache.clear(); }
  int removed = 0;
  for (const std::string& sub : {"/tracks", ""}) {
    std::string dir = cacheDir + sub;
    if (DIR* d = opendir(dir.c_str())) {
      while (dirent* e = readdir(d)) { std::string name = e->d_name; if (name == "." || name == "..") continue; if (name.size() > 5 && name.compare(name.size() - 5, 5, ".json") == 0) { if (!std::remove((dir + "/" + name).c_str())) ++removed; } }
      closedir(d);
    }
  }
  std::fprintf(stderr, "CACHE: cleared %d files\n", removed);
  publish(JSON{{"removed", removed}, {"loading", false}}.dump(), true);
}
}  // namespace ipad_player
