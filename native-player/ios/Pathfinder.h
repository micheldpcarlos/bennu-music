// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <nlohmann/json.hpp>
namespace cspot { struct Context; }
namespace ipad_player {
// The web player's GraphQL service ("pathfinder"): search, the personalized Home feed, the
// full library, and more. Each operation is identified by a persisted-query hash that Spotify
// rotates with web player releases, and requests carry a client token.
//
// Hash sources, in order: the values cached from the last run, a small config file in the
// project's GitHub repository, scraping the web player's JavaScript on the device (about two
// seconds on an iPad 2), and the values compiled into this build. A "PersistedQueryNotFound"
// answer refreshes and retries once. Three consecutive failures pause the service for ten
// minutes so callers fall back to the spclient routes without delay.
class Pathfinder {
 public:
  explicit Pathfinder(std::shared_ptr<cspot::Context> context);
  bool available();                                                      // not paused, not switched off
  nlohmann::json run(const std::string& op, const nlohmann::json& variables);   // returns response["data"]; throws on failure
  nlohmann::json search(const std::string& query);                       // {tracks, artists, albums, playlists}
  nlohmann::json home();                                                 // {sections:[{title, items:[entity]}]}
  nlohmann::json library(int limit);                                     // {items:[entity]} with type playlist/album/artist/collection
  std::string raw(const std::string& op, const std::string& variablesJSON);  // dev: full response text
  std::string refreshHashes(bool force);                                 // returns a summary line
  void refreshIfStale();                                                 // weekly background check
  std::string status();
 private:
  std::string hashFor(const std::string& op);
  nlohmann::json request(const std::string& op, const nlohmann::json& variables, const std::string& hash, int& httpStatus, std::string& rawOut);
  std::string clientToken();
  std::string fetchClientToken();
  std::map<std::string, std::string> remoteHashes();
  std::map<std::string, std::string> scrapeHashes();
  void loadState(); void saveState();
  void recordFailure(const std::string& why); void recordSuccess();
  std::shared_ptr<cspot::Context> context_;
  std::mutex mutex_;
  nlohmann::json state_;   // hashes{op:hash}, hashSource, hashAt, lastScrape, clientToken, clientTokenExpires, clientTokenRetryAt, failures, pausedUntil
};
}
