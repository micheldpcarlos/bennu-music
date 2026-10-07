// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <memory>
#include <mutex>
#include <string>
namespace cspot { struct Context; class AccessKeyFetcher; }
namespace bell { class SocketStream; }
namespace ipad_player {
// HTTP/1.1 GET client for Spotify's spclient host that keeps its TLS connection open
// between requests. On an iPad 2 the TLS handshake dominates request time, so a list
// of 50 tracks hydrates in seconds instead of a minute. One request at a time per
// instance; create several instances for parallelism.
class SpclientClient {
 public:
  struct Response { int status = 0; std::string body; };
  explicit SpclientClient(std::shared_ptr<cspot::Context> context);
  ~SpclientClient();
  // path starts with '/'. Sends the session bearer token. Throws on transport failure.
  Response get(const std::string& path, const std::string& accept = "application/json");
  static std::string resolveHost();  // "host:port", cached process-wide
 private:
  Response request(const std::string& path, const std::string& accept, const std::string& token);
  void connect();
  void disconnect();
  std::shared_ptr<cspot::AccessKeyFetcher> tokenFetcher;
  std::unique_ptr<bell::SocketStream> stream;
  std::string host; int port = 443;
  std::mutex mutex;
};
}
