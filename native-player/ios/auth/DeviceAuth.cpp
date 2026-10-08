// SPDX-License-Identifier: GPL-3.0-or-later
#include "DeviceAuth.h"
#include "OAuthLogin.h"
#include "AuthStore.h"
#include "HTTPClient.h"
#include <nlohmann/json.hpp>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
namespace {
using JSON = nlohmann::json;
const char* kClientId = "65b708073fc0480ea92a077233ca87bd";  // Spotify desktop client
const char* kScopes = "streaming user-read-private playlist-read-private user-library-read user-read-recently-played";
std::mutex stateMutex;
std::string stateJSON = "{\"state\":\"idle\"}";
uint32_t stateRevision = 1;
std::atomic<bool> running{false}, cancelled{false};
std::string lastToken;  // kept only in memory, cleared on success
std::string encode(const std::string& input) {
  const char* digits = "0123456789ABCDEF"; std::string output;
  for (unsigned char c : input) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') output += static_cast<char>(c);
    else if (c == ' ') output += '+';
    else { output += '%'; output += digits[c >> 4]; output += digits[c & 15]; }
  }
  return output;
}
void setState(const JSON& state) {
  std::lock_guard<std::mutex> lock(stateMutex);
  stateJSON = state.dump(); ++stateRevision;
  std::fprintf(stderr, "DEVICE AUTH: state=%s\n", state.value("state", "").c_str());
}
std::string str(const JSON& object, const char* key) {
  auto found = object.find(key);
  return found != object.end() && found->is_string() ? found->get<std::string>() : std::string();
}
JSON postForm(const std::string& url, const std::string& body, int& status) {
  std::vector<uint8_t> payload(body.begin(), body.end());
  auto response = bell::HTTPClient::post(url, {{"Content-Type", "application/x-www-form-urlencoded"}, {"Accept", "application/json"}}, payload);
  status = response->statusCode();
  auto bytes = response->bytes();
  if (bytes.empty()) return JSON::object();
  try { return JSON::parse(bytes.begin(), bytes.end()); } catch (...) { return JSON::object(); }
}
void fail(const std::string& message) { setState({{"state", "failed"}, {"message", message}}); running = false; }
void exchange();
void run() {
  try {
    setState({{"state", "requesting"}});
    int status = 0;
    auto start = postForm("https://accounts.spotify.com/oauth2/device/authorize",
        "client_id=" + std::string(kClientId) + "&scope=" + encode(kScopes) + "&description=" + encode("Bennu Music"), status);
    if (status != 200) { fail("Spotify refused the sign-in request (HTTP " + std::to_string(status) + "). Try again later."); return; }
    const auto deviceCode = str(start, "device_code"), userCode = str(start, "user_code");
    auto url = str(start, "verification_uri_complete");
    if (url.empty()) url = str(start, "verification_uri");
    if (deviceCode.empty() || userCode.empty() || url.empty()) { fail("Unexpected sign-in response."); return; }
    int interval = start.value("interval", 5), expires = start.value("expires_in", 600);
    if (interval < 2) interval = 2;
    setState({{"state", "waiting"}, {"code", userCode}, {"url", url}, {"expires_in", expires}});
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(expires);
    std::string token;
    while (!cancelled) {
      for (int i = 0; i < interval * 4 && !cancelled; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(250));
      if (cancelled) break;
      if (std::chrono::steady_clock::now() > deadline) { fail("The code expired. Get a new code."); return; }
      auto poll = postForm("https://accounts.spotify.com/api/token",
          "grant_type=" + encode("urn:ietf:params:oauth:grant-type:device_code") + "&device_code=" + encode(deviceCode) + "&client_id=" + kClientId, status);
      if (status == 200) { token = str(poll, "access_token"); if (!token.empty()) break; fail("Token response had no access token."); return; }
      const auto error = str(poll, "error");
      if (error == "authorization_pending") continue;
      if (error == "slow_down") { interval += 5; continue; }
      if (error == "access_denied") { fail("Sign-in was declined on the phone."); return; }
      if (error == "expired_token") { fail("The code expired. Get a new code."); return; }
      std::fprintf(stderr, "DEVICE AUTH: token HTTP=%d error=%s\n", status, error.c_str());
      fail("Spotify rejected the sign-in (" + (error.empty() ? "HTTP " + std::to_string(status) : error) + ").");
      return;
    }
    if (cancelled) { setState({{"state", "idle"}}); running = false; return; }
    { std::lock_guard<std::mutex> lock(stateMutex); lastToken = token; }
    std::fill(token.begin(), token.end(), '\0');
    exchange();
  } catch (...) {
    fail("Network error during sign-in. Check Wi-Fi and try again.");
  }
  running = false;
}
// Turn the approved token into reusable AP credentials and store them.
void exchange() {
  std::string token;
  { std::lock_guard<std::mutex> lock(stateMutex); token = lastToken; }
  if (token.empty()) { fail("No approved sign-in to retry. Get a new code."); return; }
  setState({{"state", "verifying"}, {"retryable", true}});
  char credentials[4096] = {};
  int passed = ipad_oauth_reusable_credentials(token.c_str(), credentials, sizeof(credentials));
  if (!passed) { std::memset(credentials, 0, sizeof(credentials)); setState({{"state", "failed"}, {"retryable", true}, {"message", "Spotify approved the sign-in but the player login failed. Tap Retry login, or use Spotify Connect pairing."}}); running = false; return; }
  int saved = ipad_auth_save(credentials);
  std::memset(credentials, 0, sizeof(credentials));
  if (!saved) { fail("Keychain save failed."); return; }
  { std::lock_guard<std::mutex> lock(stateMutex); std::fill(lastToken.begin(), lastToken.end(), '\0'); lastToken.clear(); }
  setState({{"state", "done"}});
  running = false;
}
}
int ipad_device_auth_retry(void) {
  { std::lock_guard<std::mutex> lock(stateMutex); if (lastToken.empty()) return 0; }
  bool expected = false;
  if (!running.compare_exchange_strong(expected, true)) return 0;
  std::thread([]() { try { exchange(); } catch (...) { fail("Network error during sign-in."); } }).detach();
  return 1;
}
int ipad_device_auth_start(void) {
  bool expected = false;
  if (!running.compare_exchange_strong(expected, true)) return 0;
  cancelled = false;
  std::thread(run).detach();
  return 1;
}
uint32_t ipad_device_auth_status(char* output, uint32_t capacity) {
  if (!output || !capacity) return 0;
  std::lock_guard<std::mutex> lock(stateMutex);
  if (stateJSON.size() >= capacity) { output[0] = 0; return 0; }
  std::snprintf(output, capacity, "%s", stateJSON.c_str());
  return stateRevision;
}
void ipad_device_auth_cancel(void) { cancelled = true; }
