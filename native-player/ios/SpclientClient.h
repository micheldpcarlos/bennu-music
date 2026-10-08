// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>
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
  Response post(const std::string& path, const std::string& body, const std::string& contentType, const std::string& accept = "application/json");
  static std::string resolveHost();  // "host:port", cached process-wide
  // One-shot request to any https URL with a size limit and read timeout; Connection: close.
  static Response fetch(const std::string& method, const std::string& url, const std::vector<std::pair<std::string, std::string>>& headers,
                        const std::string& body = "", size_t limit = 2 * 1024 * 1024, int timeoutSeconds = 20);
 private:
  Response request(const std::string& method, const std::string& path, const std::string& accept, const std::string& token, const std::string& body, const std::string& contentType);
  static Response readResponse(bell::SocketStream& stream, size_t limit, bool& close);
  void connect();
  void disconnect();
  std::shared_ptr<cspot::AccessKeyFetcher> tokenFetcher;
  std::unique_ptr<bell::SocketStream> stream;
  std::string host; int port = 443;
  std::mutex mutex;
};
}
