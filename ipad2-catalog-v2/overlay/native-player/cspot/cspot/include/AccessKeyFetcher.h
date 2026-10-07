#pragma once
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
namespace cspot {
struct Context;
class AccessKeyFetcher {
 public:
  explicit AccessKeyFetcher(std::shared_ptr<Context> ctx);
  // One synchronized provider per live account session, shared by playback and catalog.
  static std::shared_ptr<AccessKeyFetcher> forContext(std::shared_ptr<Context> ctx);
  bool isExpired();
  std::string getAccessKey();
  void updateAccessKey();
  std::string error();
 private:
  bool expiredLocked();
  void updateLocked();
  std::shared_ptr<Context> ctx;
  std::mutex mutex;
  std::string accessKey, lastError;
  long long expiresAt = 0;
  bool credentialsRejected = false;
  unsigned failures = 0;
  std::chrono::steady_clock::time_point nextAttempt{};
};
}
