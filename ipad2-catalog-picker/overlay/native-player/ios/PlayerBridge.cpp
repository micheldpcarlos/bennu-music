// SPDX-License-Identifier: GPL-3.0-or-later
#include "PlayerBridge.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <deque>
#include <exception>
#include <mutex>
#include <string>
#include <utility>

namespace {
std::mutex bridgeMutex;
IPadPlayerSnapshot state{};
std::deque<int> commands;
std::function<bool(int)> control;
std::function<void(std::string, uint64_t)> searchCatalog;
std::function<bool(std::string)> selectTrack;
std::string searchQuery, selectedURI, catalogJSON;
uint64_t catalogRequest = 0, catalogRevision = 0;
bool catalogBusy = false;

using Clock = std::chrono::steady_clock;
Clock::time_point positionAt = Clock::now();
uint32_t currentPosition() {
  uint64_t position = state.positionMs;
  if (state.hasTrack && !state.paused && !state.loading) {
    auto delta = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - positionAt).count();
    if (delta > 0) position += static_cast<uint64_t>(delta);
  }
  if (state.durationMs) position = std::min<uint64_t>(position, state.durationMs);
  return static_cast<uint32_t>(std::min<uint64_t>(position, UINT32_MAX));
}
void freezePosition() { state.positionMs = currentPosition(); positionAt = Clock::now(); }
template <size_t N> void copyText(char (&output)[N], const char* input) {
  std::snprintf(output, N, "%s", input ? input : "");
}
}
int ipad_player_search(const char* query) {
  if (!query || !*query || std::string(query).size() > 256) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (state.state != IPadReady || !searchCatalog || catalogBusy) return 0;
  searchQuery = query; catalogBusy = true; ++catalogRequest;
  catalogJSON = "{\"message\":\"Buscando no Spotify…\",\"tracks\":[]}";
  ++catalogRevision; return 1;
}
int ipad_player_select_track(const char* input) {
  if (!input) return 0;
  std::string uri(input);
  if (uri.size() != 36 || uri.compare(0, 14, "spotify:track:") != 0 ||
      uri.find_first_not_of("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", 14) != std::string::npos) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (state.state != IPadReady || !selectTrack || !selectedURI.empty()) return 0;
  selectedURI = uri; return 1;
}
uint64_t ipad_player_catalog_snapshot(char* output, uint32_t capacity) {
  if (!output || !capacity) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (catalogJSON.size() >= capacity) { output[0] = 0; return 0; }
  std::snprintf(output, capacity, "%s", catalogJSON.c_str()); return catalogRevision;
}
void ipad_player_snapshot(IPadPlayerSnapshot* output) {
  if (!output) return;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  *output = state;
  output->positionMs = currentPosition();
  output->pending = static_cast<int>(commands.size());
}
int ipad_player_command(int command) {
  if (command < IPadTogglePause || command > IPadNext) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (!control || state.state != IPadReady || !state.hasTrack || state.loading || commands.size() >= 8) return 0;
  commands.push_back(command);
  return 1;
}
void ipad_player_waiting() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state = {}; state.paused = 1; commands.clear(); control = nullptr;
  selectedURI.clear(); searchQuery.clear(); searchCatalog = nullptr; selectTrack = nullptr;
  catalogBusy = false; ++catalogRequest; catalogJSON.clear(); ++catalogRevision;
  positionAt = Clock::now();
}
void ipad_player_connecting() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.state = IPadConnecting;
}
void ipad_player_failed(const char* error) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  freezePosition(); state.state = IPadFailed; state.paused = 1;
  state.loading = 0; commands.clear(); control = nullptr;
  selectedURI.clear(); searchQuery.clear(); searchCatalog = nullptr; selectTrack = nullptr;
  catalogBusy = false; ++catalogRequest; catalogJSON.clear(); ++catalogRevision;
  copyText(state.error, error);
}
void ipad_player_ready() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.state = IPadReady; state.error[0] = '\0';
}
void ipad_player_track(const char* id, const char* title, const char* artist,
    const char* album, const char* artwork, uint32_t duration) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  freezePosition();
  copyText(state.trackId, id); copyText(state.title, title);
  copyText(state.artist, artist); copyText(state.album, album); copyText(state.artwork, artwork);
  state.durationMs = duration; state.hasTrack = 1; state.loading = 0;
  positionAt = Clock::now();
}
void ipad_player_paused(int paused) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  freezePosition(); state.paused = paused ? 1 : 0;
}
void ipad_player_position(uint32_t position) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.positionMs = position; positionAt = Clock::now();
}
void ipad_player_loading(uint32_t position) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.positionMs = position; state.loading = 1; positionAt = Clock::now();
}
void ipad_player_inactive() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  freezePosition(); state.paused = 1; state.hasTrack = 0; state.loading = 0; commands.clear();
}
namespace ipad_player {
void setControlHandler(std::function<bool(int)> handler) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  control = std::move(handler);
}
void clearControlHandler() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  commands.clear(); control = nullptr;
  selectedURI.clear(); searchQuery.clear(); searchCatalog = nullptr; selectTrack = nullptr;
  catalogBusy = false; ++catalogRequest; catalogJSON.clear(); ++catalogRevision;
}
void setCatalogHandlers(std::function<void(std::string, uint64_t)> search,
    std::function<bool(std::string)> play) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  searchCatalog = std::move(search); selectTrack = std::move(play);
}
void publishCatalog(uint64_t request, const std::string& json) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (request != catalogRequest || !catalogBusy) return;
  catalogJSON = json.size() < 65536 ? json : "{\"message\":\"Resposta muito grande.\",\"tracks\":[]}";
  catalogBusy = false; ++catalogRevision;
}
void dispatchPending() {
  std::string query, uri;
  uint64_t request = 0;
  std::function<void(std::string, uint64_t)> search;
  std::function<bool(std::string)> play;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    query.swap(searchQuery); uri.swap(selectedURI);
    request = catalogRequest; search = searchCatalog; play = selectTrack;
  }
  if (!query.empty() && search) {
    try { search(query, request); }
    catch (...) { publishCatalog(request, "{\"message\":\"Busca indisponível.\",\"tracks\":[]}"); }
  }
  if (!uri.empty() && play) {
    try { if (!play(uri)) std::fprintf(stderr, "CATALOG: selected track unavailable\n"); }
    catch (...) { std::fprintf(stderr, "CATALOG: local track load failed\n"); }
  }

  for (;;) {
    int command;
    std::function<bool(int)> handler;
    {
      std::lock_guard<std::mutex> lock(bridgeMutex);
      if (commands.empty() || !control) return;
      command = commands.front(); commands.pop_front(); handler = control;
    }
    // Never hold the UI mutex while the engine invokes playback event callbacks.
    try {
      if (!handler(command)) std::fprintf(stderr, "UI: command %d unavailable\n", command);
    } catch (const std::exception& error) {
      std::fprintf(stderr, "UI: command %d failed: %s\n", command, error.what());
    }
  }
}
}
