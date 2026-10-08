// SPDX-License-Identifier: GPL-3.0-or-later
#include "SpclientClient.h"
#include "AccessKeyFetcher.h"
#include "HTTPClient.h"
#include "SocketStream.h"
#include "picohttpparser.h"
#include <nlohmann/json.hpp>
#include <cstdio>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
namespace ipad_player {
namespace {
std::mutex hostMutex;
std::string cachedHost;
}
std::string SpclientClient::resolveHost() {
  std::lock_guard<std::mutex> lock(hostMutex);
  if (!cachedHost.empty()) return cachedHost;
  try {
    auto response = bell::HTTPClient::get("https://apresolve.spotify.com/?type=spclient");
    if (response->statusCode() == 200 && response->contentLength() <= 16384) {
      const auto bytes = response->bytes();
      auto document = nlohmann::json::parse(bytes.begin(), bytes.end());
      if (document.is_object() && document.count("spclient") && document["spclient"].is_array() &&
          !document["spclient"].empty() && document["spclient"][0].is_string()) {
        auto host = document["spclient"][0].get<std::string>();
        if (host.size() <= 128 && host.find_first_not_of(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:") == std::string::npos)
          cachedHost = host;
      }
    }
  } catch (...) { /* fall back below */ }
  if (cachedHost.empty()) cachedHost = "spclient.wg.spotify.com:443";
  std::fprintf(stderr, "CATALOG: spclient host=%s\n", cachedHost.c_str());
  return cachedHost;
}
SpclientClient::SpclientClient(std::shared_ptr<cspot::Context> context)
    : tokenFetcher(cspot::AccessKeyFetcher::forContext(context)) {}
SpclientClient::~SpclientClient() { disconnect(); }
void SpclientClient::connect() {
  disconnect();
  auto resolved = resolveHost();
  auto colon = resolved.rfind(':');
  host = colon == std::string::npos ? resolved : resolved.substr(0, colon);
  port = colon == std::string::npos ? 443 : std::atoi(resolved.c_str() + colon + 1);
  stream.reset(new bell::SocketStream());
  if (stream->open(host, port, true) != 0 || !stream->isOpen()) { stream.reset(); throw std::runtime_error("spclient connect failed"); }
}
void SpclientClient::disconnect() {
  if (stream) { try { stream->close(); } catch (...) {} stream.reset(); }
}
SpclientClient::Response SpclientClient::get(const std::string& path, const std::string& accept) {
  return post(path, "", "", accept);
}
SpclientClient::Response SpclientClient::post(const std::string& path, const std::string& body, const std::string& contentType, const std::string& accept) {
  if (path.empty() || path[0] != '/' || path.size() > 2048) throw std::invalid_argument("bad path");
  const auto token = tokenFetcher->getAccessKey();
  if (token.empty()) throw std::runtime_error("no session token");
  const std::string method = contentType.empty() ? "GET" : "POST";
  std::lock_guard<std::mutex> lock(mutex);
  for (int attempt = 0; attempt < 2; ++attempt) {
    try {
      if (!stream || !stream->isOpen()) connect();
      return request(method, path, accept, token, body, contentType);
    } catch (...) {
      disconnect();
      if (attempt == 1) throw;
    }
  }
  throw std::runtime_error("unreachable");
}
SpclientClient::Response SpclientClient::request(const std::string& method, const std::string& path, const std::string& accept, const std::string& token, const std::string& body, const std::string& contentType) {
  auto& s = *stream;
  s << method << " " << path << " HTTP/1.1\r\nHost: " << host << "\r\nConnection: keep-alive\r\nAccept: " << accept
    << "\r\nAuthorization: Bearer " << token;
  if (method == "POST") s << "\r\nContent-Type: " << contentType << "\r\nContent-Length: " << body.size();
  s << "\r\n\r\n";
  if (method == "POST" && !body.empty()) s.write(body.data(), static_cast<std::streamsize>(body.size()));
  s.flush();
  if (!s.good()) throw std::runtime_error("write failed");
  // Headers: read line by line into a buffer until picohttpparser accepts it.
  std::string head; head.reserve(2048);
  int status = 0, minor = 0; const char* message = nullptr; size_t messageLength = 0;
  phr_header headers[48]; size_t headerCount = 0;
  for (;;) {
    char line[1024];
    s.getline(line, sizeof(line));
    auto got = s.gcount();
    if (!s.good() || got <= 0) throw std::runtime_error("header read failed");
    size_t previous = head.size();
    size_t length = static_cast<size_t>(got) - 1;        // stored characters, newline excluded
    while (length && (line[length - 1] == '\r' || line[length - 1] == '\n')) --length;
    head.append(line, length); head += "\r\n";
    headerCount = sizeof(headers) / sizeof(headers[0]);
    int parsed = phr_parse_response(head.data(), head.size(), &minor, &status, &message, &messageLength, headers, &headerCount, previous);
    if (parsed > 0) break;
    if (parsed == -1) throw std::runtime_error("bad response");
    if (head.size() > 16384) throw std::runtime_error("headers too large");
  }
  long contentLength = -1; bool chunked = false, close = false;
  for (size_t i = 0; i < headerCount; ++i) {
    std::string name(headers[i].name, headers[i].name_len), value(headers[i].value, headers[i].value_len);
    for (auto& c : name) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    for (auto& c : value) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (name == "content-length") contentLength = std::atol(value.c_str());
    else if (name == "transfer-encoding" && value.find("chunked") != std::string::npos) chunked = true;
    else if (name == "connection" && value.find("close") != std::string::npos) close = true;
  }
  Response response; response.status = status;
  const size_t limit = 2 * 1024 * 1024;
  if (chunked) {
    for (;;) {
      char line[64]; s.getline(line, sizeof(line));
      if (!s.good()) throw std::runtime_error("chunk size read failed");
      size_t size = std::strtoul(line, nullptr, 16);
      if (size == 0) { s.getline(line, sizeof(line)); break; }  // trailing CRLF after last chunk
      if (response.body.size() + size > limit) throw std::runtime_error("body too large");
      size_t offset = response.body.size(); response.body.resize(offset + size);
      s.read(&response.body[offset], static_cast<std::streamsize>(size));
      if (!s.good()) throw std::runtime_error("chunk read failed");
      s.getline(line, sizeof(line));  // CRLF after chunk data
    }
  } else if (contentLength > 0) {
    if (static_cast<size_t>(contentLength) > limit) throw std::runtime_error("body too large");
    response.body.resize(static_cast<size_t>(contentLength));
    s.read(&response.body[0], contentLength);
    if (!s.good()) throw std::runtime_error("body read failed");
  } else if (contentLength < 0 && status != 204 && status != 304) {
    close = true;  // unknown length: read to end and drop the connection
    char chunk[4096];
    while (s.read(chunk, sizeof(chunk)) || s.gcount() > 0) {
      response.body.append(chunk, static_cast<size_t>(s.gcount()));
      if (response.body.size() > limit) throw std::runtime_error("body too large");
      if (!s.good()) break;
    }
  }
  if (close) disconnect();
  return response;
}
}
