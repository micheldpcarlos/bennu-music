// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <map>
#include "HTTPClient.h"
namespace cspot { struct Context; class AccessKeyFetcher; }
namespace ipad_player {
class CatalogSearch {
 public:
  explicit CatalogSearch(std::shared_ptr<cspot::Context> context,
      std::string policyPath = "/var/mobile/Documents/cspot-catalog-policy.json");
  ~CatalogSearch();
  std::string search(const std::string& query);
 private:
  std::string searchContextResolve(const std::string& query, const std::string& token, unsigned delay);
  std::string searchWebApi(const std::string& query, const std::string& token, unsigned delay);
  std::string rateLimited(const std::unique_ptr<bell::HTTPClient::Response>& response, unsigned delay);
  std::string finish(const std::string& query, const std::string& result);
  std::string spclientHost();
  std::string spclient;
  std::string backend;
  struct Cached { std::chrono::steady_clock::time_point at; std::string json; };
  void savePolicy();
  std::string cooldownMessage();
  std::shared_ptr<cspot::AccessKeyFetcher> tokenFetcher;
  std::mutex mutex;
  std::map<std::string, Cached> cache;
  std::string policyPath;
  long long retryAt = 0;
  bool quotaBlocked = false;
  unsigned failures = 0;
  std::chrono::steady_clock::time_point nextAttempt{};
};
}
