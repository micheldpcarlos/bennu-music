// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
namespace cspot { struct Context; class AccessKeyFetcher; }
namespace ipad_player {
class CatalogSearch {
 public:
  explicit CatalogSearch(std::shared_ptr<cspot::Context> context);
  ~CatalogSearch();
  std::string search(const std::string& query);
 private:
  std::unique_ptr<cspot::AccessKeyFetcher> tokenFetcher;
  std::mutex mutex;
  std::chrono::steady_clock::time_point nextAttempt{};
};
}
