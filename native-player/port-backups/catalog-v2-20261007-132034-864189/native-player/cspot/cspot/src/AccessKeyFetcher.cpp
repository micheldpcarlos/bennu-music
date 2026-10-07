#include "AccessKeyFetcher.h"

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

bool AccessKeyFetcher::isExpired() {
  if (accessKey.empty()) {
    return true;
  }

  if (ctx->timeProvider->getSyncedTimestamp() > expiresAt) {
    return true;
  }

  return false;
}

std::string AccessKeyFetcher::getAccessKey() {
  if (!isExpired()) {
    return accessKey;
  }

  updateAccessKey();

  return isExpired() ? std::string() : accessKey;
}

void AccessKeyFetcher::updateAccessKey() {
  bool expected = false;
  if (!keyPending.compare_exchange_strong(expected, true)) return;
  struct PendingGuard {
    std::atomic<bool>& flag;
    ~PendingGuard() { flag.store(false); }
  } pendingGuard{keyPending};
  if (std::chrono::steady_clock::now() < nextAttempt) return;
  // One request per attempt, with a cooldown even when transport throws.
  nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(5);
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
      nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(httpStatus == 429 ? 60 : 15);
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=%d; retry delayed", httpStatus);
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
      expiresAt = ctx->timeProvider->getSyncedTimestamp() + (static_cast<long long>(expiresIn) * 1000 / 2);
      nextAttempt = std::chrono::steady_clock::time_point{};
      CSPOT_LOG(info, "PLAYBACK AUTH: token accepted");
    } else if (loginResponse.which_response == LoginResponse_error_tag) {
      nextAttempt = std::chrono::steady_clock::now() + std::chrono::seconds(30);
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 login5_error=%d; retry in 30s", int(loginResponse.response.error));
    } else {
      CSPOT_LOG(error, "PLAYBACK AUTH: HTTP=200 unsupported response_tag=%u", unsigned(loginResponse.which_response));
    }
  } catch (...) {
    CSPOT_LOG(error, "PLAYBACK AUTH: transport or encoding failure; retry delayed");
  }
}
