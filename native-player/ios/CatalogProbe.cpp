// SPDX-License-Identifier: GPL-3.0-or-later
#include "CatalogProbe.h"
#include "AccessKeyFetcher.h"
#include "CSpotContext.h"
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
    if (!line.empty() && line[0] != '#' && line.compare(0, 8, "https://") == 0 && line.size() < 1024) urls.push_back(line);  // "URL | Header: value" allowed
  }
  std::remove(listPath.c_str());
  if (urls.empty()) return;
  auto fetcher = cspot::AccessKeyFetcher::forContext(context);
  const std::string username = context->config.username;
  std::thread([fetcher, urls, username]() {
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
        std::string accept = "application/json";
        auto bar = url.find(" | ");
        if (bar != std::string::npos) {
          auto extra = url.substr(bar + 3); url.erase(bar);
          auto colon = extra.find(": ");
          if (colon != std::string::npos) {
            if (extra.substr(0, colon) == "Accept") accept = extra.substr(colon + 2);
            else headers.push_back({extra.substr(0, colon), extra.substr(colon + 2)});
          }
        }
        headers.push_back({"Accept", accept});
        auto response = bell::HTTPClient::get(url, headers);
        const int status = response->statusCode();
        auto bytes = response->bytes();
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
