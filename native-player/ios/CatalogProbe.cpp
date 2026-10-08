// SPDX-License-Identifier: GPL-3.0-or-later
#include "CatalogProbe.h"
#include "AccessKeyFetcher.h"
#include "CSpotContext.h"
#include "SpclientClient.h"
#include "HTTPClient.h"
#include <nlohmann/json.hpp>
#include <cstdio>
#include <fstream>
#include <string>
#include <thread>
#include <vector>
namespace ipad_player {
void runCatalogProbeIfRequested(std::shared_ptr<cspot::Context> context) {
  const std::string listPath = "/var/mobile/Documents/phoenix-probe.txt";
  std::ifstream list(listPath);
  if (!list) return;
  std::vector<std::string> urls;
  for (std::string line; std::getline(list, line);) {
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
    if (!line.empty() && line[0] != '#' && (line.compare(0, 8, "https://") == 0 || line.compare(0, 13, "POST https://") == 0) && line.size() < 8192) urls.push_back(line);  // "URL | Header: value", "POST URL | Body-Hex: .. | Content-Type: .."
  }
  std::remove(listPath.c_str());
  if (urls.empty()) return;
  auto fetcher = cspot::AccessKeyFetcher::forContext(context);
  const std::string username = context->config.username;
  auto spclient = std::make_shared<SpclientClient>(context);
  std::thread([fetcher, urls, username, spclient]() {
    const auto token = fetcher->getAccessKey();
    if (token.empty()) { std::fprintf(stderr, "PROBE: no session token\n"); return; }
    int index = 0;
    for (auto url : urls) {
      ++index;
      for (auto at = url.find("{username}"); at != std::string::npos; at = url.find("{username}")) url.replace(at, 10, username);
      // Log only the path, never query parameters that could carry identifiers.
      auto pathStart = url.find('/', 8);
      auto label = pathStart == std::string::npos ? url : url.substr(pathStart, 80);
      try {
        bell::HTTPClient::Headers headers{{"Authorization", "Bearer " + token}};
        std::string accept = "application/json", bodyHex, contentType;
        bool isPost = url.compare(0, 5, "POST ") == 0;
        if (isPost) url.erase(0, 5);
        for (auto bar = url.find(" | "); bar != std::string::npos; bar = url.find(" | ")) {
          auto extra = url.substr(bar + 3); url.erase(bar);
          auto next = extra.find(" | "); if (next != std::string::npos) { url += " | " + extra.substr(next + 3); extra.erase(next); }
          auto colon = extra.find(": ");
          if (colon == std::string::npos) continue;
          auto key = extra.substr(0, colon), value = extra.substr(colon + 2);
          if (key == "Accept") accept = value; else if (key == "Body-Hex") bodyHex = value; else if (key == "Content-Type") contentType = value;
          else headers.push_back({key, value});
        }
        headers.push_back({"Accept", accept});
        std::string requestBody;
        for (size_t i = 0; i + 1 < bodyHex.size(); i += 2) requestBody += static_cast<char>(std::stoul(bodyHex.substr(i, 2), nullptr, 16));
        int status = 0; std::vector<uint8_t> bytes;
        if (isPost && url.find("spclient") != std::string::npos) {
          auto path = url.substr(url.find('/', 8));
          auto response = spclient->post(path, requestBody, contentType.empty() ? "application/x-protobuf" : contentType, accept);
          status = response.status; bytes.assign(response.body.begin(), response.body.end());
        } else if (url.find("spclient") != std::string::npos && headers.size() == 2) {
          // Single Accept header through the keep-alive client (bell adds its own "*/*" first).
          auto path = url.substr(url.find('/', 8));
          auto response = spclient->get(path, accept);
          status = response.status; bytes.assign(response.body.begin(), response.body.end());
        } else {
          auto response = bell::HTTPClient::get(url, headers);
          status = response->statusCode(); bytes = response->bytes();
        }
        std::string keys;
        try {
          auto document = nlohmann::json::parse(bytes.begin(), bytes.end());
          if (document.is_object()) {
            for (auto it = document.begin(); it != document.end(); ++it) { if (!keys.empty()) keys += ','; keys += it.key().substr(0, 32); if (keys.size() > 300) { keys += ",..."; break; } }
          } else if (document.is_array()) keys = "[array " + std::to_string(document.size()) + "]";
        } catch (...) { keys = bytes.empty() ? "(empty)" : "(not json)"; }
        std::fprintf(stderr, "PROBE %d: %s HTTP=%d bytes=%lu keys=%s\n", index, label.c_str(), status,
            static_cast<unsigned long>(bytes.size()), keys.c_str());
        std::ofstream body("/var/mobile/Documents/phoenix-probe-" + std::to_string(index) + ".out", std::ios::binary | std::ios::trunc);
        body << "URL: " << url << "\nHTTP: " << status << "\n\n";
        body.write(reinterpret_cast<const char*>(bytes.data()), std::min<size_t>(bytes.size(), 400000));
      } catch (...) {
        std::fprintf(stderr, "PROBE %d: %s request failed\n", index, label.c_str());
      }
    }
    std::fprintf(stderr, "PROBE: done (%d urls)\n", index);
  }).detach();
}
}
