// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
namespace cspot { struct Context; }
namespace ipad_player {
class SpclientClient;
// Browsing data for the UI, built from Spotify's spclient endpoints with the session's
// own token. Every method returns UI-ready JSON and may publish partial results while
// track names are still being fetched. Track metadata is cached on disk.
class Catalog {
 public:
  using Publish = std::function<void(const std::string& json, bool done)>;
  explicit Catalog(std::shared_ptr<cspot::Context> context, std::string cacheDir = "/var/mobile/Documents/bennu-cache");
  ~Catalog();
  void search(const std::string& query, const Publish& publish);
  void album(const std::string& id, const Publish& publish);
  void artist(const std::string& id, const Publish& publish);
  void playlist(const std::string& id, const Publish& publish);
  void collection(const Publish& publish);          // liked songs
  void recent(const Publish& publish);              // recently played contexts
  void profile(const Publish& publish);
  void playlists(const Publish& publish);          // the user's own and followed playlists (rootlist)
  void home(const Publish& publish);               // artist radios and new releases from recently played artists
  void context(const std::string& uri, const Publish& publish);  // any playable context -> tracks
  void tracks(const std::vector<std::string>& uris, const Publish& publish);
 private:
  struct Track;
  std::string hostPath(const std::string& path);
  std::string getJSON(const std::string& path, int& status);
  std::vector<std::string> contextTrackURIs(const std::string& uri, std::string* metadataJSON);
  void hydrate(const std::vector<std::string>& uris, const std::function<void(size_t loaded, bool done)>& progress);
  size_t hydrateBatch(const std::vector<std::string>& uris);   // extended-metadata, up to 50 per call; returns tracks stored
  bool cachedTrack(const std::string& uri, std::string& json);
  void storeTrack(const std::string& uri, const std::string& json);
  std::string trackJSON(const std::string& uri);
  std::string albumSummary(const std::string& gidHex);
  std::string artistSummary(const std::string& gidHex);
  std::string artistSummaryUncached(const std::string& gidHex);
  std::string playlistCover(const std::string& id);   // fallback for generated playlists (charts, radios, mixes)
  std::map<std::string, std::string> coverCache;
  std::map<std::string, std::string> artistCache;   // gid hex -> artist summary json (per session)
  std::shared_ptr<cspot::Context> context_;
  std::unique_ptr<SpclientClient> client, client2;
  std::string cacheDir;
  std::mutex cacheMutex;
  std::map<std::string, std::string> memoryCache;  // uri -> track json
};
std::string base62FromHex(const std::string& hex);
std::string hexFromBase62(const std::string& id);
}
