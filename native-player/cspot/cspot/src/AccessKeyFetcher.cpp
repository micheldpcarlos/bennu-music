#include "AccessKeyFetcher.h"

#include <algorithm>
#include <cstring>           // for strrchr
#include <initializer_list>  // for initializer_list
#include <map>               // for operator!=, operator==
#include <type_traits>       // for remove_extent_t
#include <vector>            // for vector

#include "BellLogger.h"    // for AbstractLogger
#include "CSpotContext.h"  // for Context
#include "HTTPClient.h"
#include "Logger.h"            // for CSPOT_LOG
#include "MercurySession.h"    // for MercurySession, MercurySession::Res...
#include "NanoPBExtensions.h"  // for bell::nanopb::encode...
#include "NanoPBHelper.h"      // for pbEncode and pbDecode
#include "Packet.h"            // for cspot
#include "TimeProvider.h"      // for TimeProvider
#include "Utils.h"             // for string_format

#ifdef BELL_ONLY_CJSON
#include "cJSON.h"
#else
#include "nlohmann/json.hpp"      // for basic_json<>::object_t, basic_json
#include "nlohmann/json_fwd.hpp"  // for json
#endif

#include "protobuf/login5.pb.h"  // for LoginRequest

using namespace cspot;

static std::string CLIENT_ID =
    "65b708073fc0480ea92a077233ca87bd";  // Spotify web client's client id

static std::string SCOPES =
    "streaming,user-library-read,user-library-modify,user-top-read,user-read-"
    "recently-played";  // Required access scopes

AccessKeyFetcher::AccessKeyFetcher(std::shared_ptr<cspot::Context> ctx)
    : ctx(ctx) {}

std::shared_ptr<AccessKeyFetcher> AccessKeyFetcher::forContext(std::shared_ptr<Context> ctx) {
  static std::mutex registryMutex;
  static std::map<Context*, std::weak_ptr<AccessKeyFetcher>> providers;
  std::lock_guard<std::mutex> guard(registryMutex);
  for (auto it = providers.begin(); it != providers.end();) {
    if (it->second.expired()) it = providers.erase(it); else ++it;
  }
  auto existing = providers[ctx.get()].lock();
  if (existing) return existing;
  auto provider = std::make_shared<AccessKeyFetcher>(ctx);
  providers[ctx.get()] = provider; return provider;
}
bool AccessKeyFetcher::expiredLocked() {
  return accessKey.empty() || ctx->timeProvider->getSyncedTimestamp() >= expiresAt;
}
bool AccessKeyFetcher::isExpired() {
  std::lock_guard<std::mutex> guard(mutex); return expiredLocked();
}
std::string AccessKeyFetcher::error() {
  std::lock_guard<std::mutex> guard(mutex); return lastError;
}
std::string AccessKeyFetcher::getAccessKey() {
  std::lock_guard<std::mutex> guard(mutex);
  if (expiredLocked()) updateLocked();
  return expiredLocked() ? std::string() : accessKey;
}
void AccessKeyFetcher::updateAccessKey() {
  std::lock_guard<std::mutex> guard(mutex); updateLocked();
}
void AccessKeyFetcher::updateLocked() {
  if (credentialsRejected || std::chrono::steady_clock::now() < nextAttempt) return;
  ++failures;
  const unsigned delay = std::min(300u, 5u << std::min(failures - 1, 6u));
  nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(delay);
  lastError = "Token request failed; retry is delayed.";
  LoginRequest loginRequest = LoginRequest_init_zero;
  LoginResponse loginResponse = LoginResponse_init_zero;
  struct ResponseGuard {
    LoginResponse& response;
    ~ResponseGuard() { pb_release(LoginResponse_fields, &response); }
  } responseGuard{loginResponse};
  loginRequest.client_info.client_id.funcs.encode = &bell::nanopb::encodeString;
  loginRequest.client_info.client_id.arg = &CLIENT_ID;
  loginRequest.client_info.device_id.funcs.encode = &bell::nanopb::encodeString;
  loginRequest.client_info.device_id.arg = &ctx->config.deviceId;
  loginRequest.login_method.stored_credential.username.funcs.encode = &bell::nanopb::encodeString;
  loginRequest.login_method.stored_credential.username.arg = &ctx->config.username;
  loginRequest.which_login_method = LoginRequest_stored_credential_tag;
  loginRequest.login_method.stored_credential.data.funcs.encode = &bell::nanopb::encodeVector;
  loginRequest.login_method.stored_credential.data.arg = &ctx->config.authData;
  try {
    auto encodedRequest = pbEncode(LoginRequest_fields, &loginRequest);
    CSPOT_LOG(info, "PLAYBACK AUTH: requesting login5 token");
    auto response = bell::HTTPClient::post(
        "https://login5.spotify.com/v3/login",
        {{"Content-Type", "application/x-protobuf"}}, encodedRequest);
    int httpStatus = response->statusCode();
    if (httpStatus != 200) {
      if (httpStatus == 429) {
        auto header = response->header("retry-after");
        std::string value(header.begin(), header.end());
        unsigned long seconds = std::max(60u, delay);
        if (!value.empty() && value.size() <= 10 && value.find_first_not_of("0123456789") == std::string::npos) {
          unsigned long long parsed = std::stoull(value);
          if (parsed <= 2147483647ULL) seconds = static_cast<unsigned long>(std::max(1ULL, parsed));
          else credentialsRejected = true; // Cannot safely schedule: require a new session instead of retrying early.
        }
        nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
        if (value.size() > 10 && value.find_first_not_of("0123456789") == std::string::npos) credentialsRejected = true;
        lastError = "Spotify limited token requests. Wait before reconnecting.";
        CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=429 retry_seconds=%lu", seconds);
      }
      if (httpStatus != 429) CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=%d retry_seconds=%u", httpStatus, delay);
      return;
    }
    auto responseBytes = response->bytes();
    if (responseBytes.empty()) {
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 empty response");
      return;
    }
    pb_istream_t stream = pb_istream_from_buffer(responseBytes.data(), responseBytes.size());
    if (!pb_decode(&stream, LoginResponse_fields, &loginResponse)) {
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 protobuf decode failed");
      return;
    }
    if (loginResponse.which_response == LoginResponse_ok_tag &&
        loginResponse.response.ok.access_token && loginResponse.response.ok.access_token[0]) {
      int expiresIn = loginResponse.response.ok.has_access_token_expires_in ?
          loginResponse.response.ok.access_token_expires_in : 3600;
      if (expiresIn <= 0) {
        CSPOT_LOG(error, "PLAYBACK AUTH: invalid token lifetime");
        return;
      }
      accessKey = loginResponse.response.ok.access_token;
      const long long lifetimeMs = static_cast<long long>(expiresIn) * 1000;
      const long long marginMs = std::min(30000LL, lifetimeMs / 10);
      expiresAt = ctx->timeProvider->getSyncedTimestamp() + lifetimeMs - marginMs;
      failures = 0; lastError.clear();
      nextAttempt = std::chrono::steady_clock::time_point{};
      CSPOT_LOG(info, "PLAYBACK AUTH: token accepted");
    } else if (loginResponse.which_response == LoginResponse_error_tag) {
      if (loginResponse.response.error == LoginError_INVALID_CREDENTIALS) {
        credentialsRejected = true;
        lastError = "Saved credentials cannot obtain a playback token. Account recovery is required.";
        CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 login5_error=%d; automatic retries stopped", int(loginResponse.response.error));
      } else {
        CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 login5_error=%d retry_seconds=%u", int(loginResponse.response.error), delay);
      }
    } else {
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 unsupported response_tag=%u", unsigned(loginResponse.which_response));
    }
  } catch (...) {
    CSPOT_LOG(error, "PLAYBACK AUTH: transport or encoding failure; retry delayed");
  }
}
