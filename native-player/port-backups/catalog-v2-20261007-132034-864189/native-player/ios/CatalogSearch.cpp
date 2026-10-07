// SPDX-License-Identifier: GPL-3.0-or-later
#include "CatalogSearch.h"
#include "AccessKeyFetcher.h"
#include "HTTPClient.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <vector>
namespace {
using JSON = nlohmann::json;
std::string message(const char* text) {
  return JSON{{"message", text}, {"tracks", JSON::array()}}.dump();
}
std::string percentEncode(const std::string& input) {
  const char* digits = "0123456789ABCDEF";
  std::string output;
  for (unsigned char byte : input) {
    if ((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
        (byte >= '0' && byte <= '9') || byte == '-' || byte == '_' || byte == '.' || byte == '~')
      output += static_cast<char>(byte);
    else { output += '%'; output += digits[byte >> 4]; output += digits[byte & 15]; }
  }
  return output;
}
std::string field(const JSON& object, const char* key, size_t limit = 1024) {
  auto found = object.find(key);
  if (found == object.end() || !found->is_string()) return {};
  auto value = found->get<std::string>();
  return value.size() <= limit ? value : std::string();
}
bool validID(const std::string& id) {
  return id.size() == 22 && id.find_first_not_of(
      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") == std::string::npos;
}
}
namespace ipad_player {
CatalogSearch::CatalogSearch(std::shared_ptr<cspot::Context> context)
    : tokenFetcher(new cspot::AccessKeyFetcher(context)) {}
CatalogSearch::~CatalogSearch() = default;
std::string CatalogSearch::search(const std::string& query) {
  try {
    std::lock_guard<std::mutex> lock(mutex);
    if (query.empty() || query.size() > 256) return message("Digite o nome de uma música ou artista.");
    const auto now = std::chrono::steady_clock::now();
    if (now < nextAttempt) return message("Aguarde alguns segundos antes de tentar novamente.");
    nextAttempt = now + std::chrono::seconds(5);
    const auto token = tokenFetcher->getAccessKey();
    if (token.empty()) return message("Token de catálogo indisponível. Consulte PLAYBACK AUTH no log.");
    auto response = bell::HTTPClient::get(
        "https://api.spotify.com/v1/search?type=track&limit=10&q=" + percentEncode(query),
        {{"Authorization", "Bearer " + token}, {"Accept", "application/json"}});
    const int status = response->statusCode();
    std::fprintf(stderr, "CATALOG: HTTP=%d\n", status);
    if (status == 429) {
      auto retry = response->header("retry-after");
      std::string value(retry.begin(), retry.end());
      long seconds = 30;
      if (!value.empty() && value.size() <= 3 && value.find_first_not_of("0123456789") == std::string::npos)
        seconds = std::max(5L, std::min(120L, std::strtol(value.c_str(), nullptr, 10)));
      nextAttempt = now + std::chrono::seconds(seconds);
      return message("Spotify limitou as buscas. Aguarde antes de tentar novamente.");
    }
    if (status == 401) return message("Spotify recusou o token da sessão. Consulte CATALOG no log.");
    if (status == 403) return message("Spotify negou acesso ao catálogo para esta sessão.");
    if (status != 200) return message("Busca indisponível no Spotify. Tente novamente mais tarde.");
    if (response->contentLength() > 131072) return message("Resposta de catálogo muito grande.");
    const auto bytes = response->bytes();
    if (bytes.size() > 131072) return message("Resposta de catálogo muito grande.");
    auto document = JSON::parse(bytes.begin(), bytes.end());
    if (!document.is_object() || !document.count("tracks") || !document["tracks"].is_object() ||
        !document["tracks"].count("items") || !document["tracks"]["items"].is_array())
      return message("Spotify retornou uma lista inválida.");
    auto tracks = JSON::array();
    for (const auto& item : document["tracks"]["items"]) {
      if (tracks.size() >= 10) break;
      if (!item.is_object()) continue;
      const auto id = field(item, "id", 22);
      const auto uri = field(item, "uri", 36);
      if (!validID(id) || uri != "spotify:track:" + id) continue;
      if (item.count("is_playable") && item["is_playable"].is_boolean() && !item["is_playable"].get<bool>()) continue;
      std::string artist;
      if (item.count("artists") && item["artists"].is_array()) {
        size_t count = 0;
        for (const auto& person : item["artists"]) {
          if (++count > 3) break;
          auto name = field(person, "name", 256);
          if (!name.empty()) { if (!artist.empty()) artist += ", "; artist += name; }
        }
      }
      const auto title = field(item, "name");
      std::string album;
      if (item.count("album") && item["album"].is_object()) album = field(item["album"], "name");
      tracks.push_back({{"uri", uri}, {"title", title.empty() ? "Sem título" : title},
          {"artist", artist.empty() ? "Artista desconhecido" : artist}, {"album", album},
          {"url", "https://open.spotify.com/track/" + id}});
    }
    std::fprintf(stderr, "CATALOG: tracks=%lu\n", static_cast<unsigned long>(tracks.size()));
    return JSON{{"message", tracks.empty() ? "Nenhuma música encontrada. Tente outra busca." :
        "Toque em uma música para reproduzir neste iPad."}, {"tracks", tracks}}.dump();
  } catch (...) {
    std::fprintf(stderr, "CATALOG: request or response failure\n");
    return "{\"message\":\"Falha ao consultar o Spotify. Tente novamente.\",\"tracks\":[]}";
  }
}
}
