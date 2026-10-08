// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <memory>
#include <mutex>
#include <string>
#include <nlohmann/json.hpp>
namespace cspot { struct Context; }
namespace ipad_player {
// Search through the web player's GraphQL endpoint ("pathfinder"), which returns tracks,
// artists, albums and playlists directly. It needs two things Spotify rotates on its own
// schedule: the persisted-query hash of the "searchDesktop" operation, and a client token.
//
// Hash sources, in order: the cached value from the last run, a small config file in the
// project's GitHub repository, scraping the web player's JavaScript on the device, and the
// value compiled into this build. A "persisted query not found" answer triggers a refresh
// and one retry. Three consecutive failures pause this path for ten minutes so the caller
// falls back to the context-resolve search without delay.
class Pathfinder {
 public:
  explicit Pathfinder(std::shared_ptr<cspot::Context> context);
  bool available();                                 // not paused by the breaker, not switched off
  nlohmann::json search(const std::string& query);  // {tracks, artists, albums, playlists}; throws on failure
  std::string refreshHash(bool force);              // for the dev URL; returns the hash in use
  void refreshIfStale();                            // weekly background check (remote config, then scrape)
  std::string status();                             // one-line summary for logs and the UI
 private:
  nlohmann::json query(const std::string& text, const std::string& hash, int& httpStatus);
  nlohmann::json parse(const nlohmann::json& response);
  std::string clientToken();
  std::string fetchClientToken();
  std::string remoteHash();
  std::string scrapeHash();
  void loadState(); void saveState();
  void recordFailure(const std::string& why); void recordSuccess();
  std::shared_ptr<cspot::Context> context_;
  std::mutex mutex_;
  nlohmann::json state_;   // hash, hashSource, hashAt, clientToken, clientTokenExpires, failures, pausedUntil, lastScrape
};
}
