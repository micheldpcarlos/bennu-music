// SPDX-License-Identifier: GPL-3.0-or-later
#include "PlayerBridge.h"
#include "Catalog.h"  // base62FromHex
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <deque>
#include <exception>
#include <map>
#include <mutex>
#include <atomic>
#include <random>
#include <sys/stat.h>
#include <fstream>
#include <string>
#include <thread>
#include <utility>

namespace {
std::mutex bridgeMutex;
IPadPlayerSnapshot state{};
std::deque<int> commands;
std::function<bool(int)> control;
std::function<bool(const std::vector<std::string>&, size_t, const std::string&)> playTracks;
std::function<void(uint32_t)> seekTrack;
std::function<void(const std::string&, const std::string&, const ipad_player::CatalogPublish&)> catalogService;
std::function<void()> stopHandler;
std::function<void()> dropHandler;
std::function<void(const std::vector<std::string>&)> enqueueTracks;
std::function<void(int)> setRepeatMode;
std::vector<std::string> pendingQueue; int pendingRepeat = -1;
std::function<void(uint32_t)> setRemoteVolume; long pendingVolume = -1; bool volumeKnown = false;
std::vector<std::string> queueUris; size_t queueIndex = 0; std::string queueContext;
std::function<void(bool)> discoverableHandler;
const char* kHiddenMarker = "/var/mobile/Documents/phoenix-hidden";
std::atomic<bool> stopFlag{false};
struct PendingPlay { std::vector<std::string> uris; size_t index = 0; std::string context; bool valid = false; };
PendingPlay pendingPlay;
bool pendingSeek = false; uint32_t pendingSeekMs = 0;
std::string queueJSON = "{\"uris\":[],\"index\":0,\"context\":\"\"}";
uint64_t queueRevision = 1;

struct CatalogEntry { std::string json; uint64_t revision = 0; bool done = false; uint64_t created = 0; };
std::mutex catalogMutex;
std::map<uint64_t, CatalogEntry> catalogResults;
uint64_t catalogNextId = 1, catalogRevision = 1;

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
void resetHandlersLocked() {
  commands.clear(); control = nullptr; playTracks = nullptr; seekTrack = nullptr;
  pendingPlay = PendingPlay{}; pendingSeek = false; pendingQueue.clear(); pendingRepeat = -1;
  enqueueTracks = nullptr; setRepeatMode = nullptr; dropHandler = nullptr; setRemoteVolume = nullptr; pendingVolume = -1;
}
bool validTrack(const std::string& uri) {
  return uri.size() == 36 && uri.compare(0, 14, "spotify:track:") == 0 &&
      uri.find_first_not_of("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", 14) == std::string::npos;
}
void publishCatalog(uint64_t id, const std::string& json, bool done) {
  std::lock_guard<std::mutex> lock(catalogMutex);
  auto found = catalogResults.find(id);
  if (found == catalogResults.end()) return;  // forgotten by the UI
  found->second.json = json; found->second.done = done; found->second.revision = ++catalogRevision;
}
}

namespace {
// Per-kind health: a flags file can switch a kind off; three consecutive failures pause it for five minutes.
struct KindHealth { int failures = 0; std::chrono::steady_clock::time_point pausedUntil{}; };
std::mutex healthMutex;
std::map<std::string, KindHealth> kindHealth;
bool kindDisabledByFlags(const std::string& kind) {
  try {
    std::ifstream file("/var/mobile/Documents/phoenix-catalog-flags.json");
    if (!file) return false;
    auto flags = nlohmann::json::parse(file);
    return flags.is_object() && flags.count(kind) && flags[kind].is_boolean() && !flags[kind].get<bool>();
  } catch (...) { return false; }
}
const char* kUnavailable = "{\"error\":\"Browsing is unavailable right now. Your phone can still pick Phoenix Player in Spotify.\",\"unavailable\":true,\"loading\":false}";
}
uint64_t ipad_catalog_request(const char* kind, const char* argument) {
  if (!kind || !*kind) return 0;
  std::string kindText(kind), argumentText(argument ? argument : "");
  if (kindText.size() > 32 || argumentText.size() > 20000) return 0;
  bool paused = kindDisabledByFlags(kindText);
  {
    std::lock_guard<std::mutex> lock(healthMutex);
    auto& health = kindHealth[kindText];
    if (!paused && health.pausedUntil > std::chrono::steady_clock::now()) paused = true;
  }
  if (paused) {
    uint64_t id;
    std::lock_guard<std::mutex> lock(catalogMutex);
    id = catalogNextId++;
    CatalogEntry entry; entry.created = id; entry.json = kUnavailable; entry.done = true; entry.revision = ++catalogRevision;
    catalogResults[id] = entry;
    std::fprintf(stderr, "CATALOG: %s paused (kill switch or repeated failures)\n", kindText.c_str());
    return id;
  }
  std::function<void(const std::string&, const std::string&, const ipad_player::CatalogPublish&)> service;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    if (state.state != IPadReady || !catalogService) return 0;
    service = catalogService;
  }
  uint64_t id;
  {
    std::lock_guard<std::mutex> lock(catalogMutex);
    id = catalogNextId++;
    if (catalogResults.size() >= 24) catalogResults.erase(catalogResults.begin());
    CatalogEntry entry; entry.created = id; entry.json = "{\"loading\":true}"; entry.revision = ++catalogRevision;
    catalogResults[id] = entry;
  }
  std::thread([service, id, kindText, argumentText]() {
    const auto started = Clock::now();
    auto recordFailure = [kindText]() {
      std::lock_guard<std::mutex> lock(healthMutex);
      auto& health = kindHealth[kindText];
      if (++health.failures >= 3) {
        health.pausedUntil = std::chrono::steady_clock::now() + std::chrono::minutes(5);
        health.failures = 0;
        std::fprintf(stderr, "CATALOG: %s paused for 5 minutes after repeated failures\n", kindText.c_str());
      }
    };
    try {
      service(kindText, argumentText, [id, kindText, started](const std::string& json, bool done) {
        publishCatalog(id, json, done);
        if (done) {
          std::fprintf(stderr, "CATALOG: %s done bytes=%lu ms=%lld\n", kindText.c_str(), static_cast<unsigned long>(json.size()),
              static_cast<long long>(std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - started).count()));
          std::lock_guard<std::mutex> lock(healthMutex); kindHealth[kindText].failures = 0;
        }
      });
    } catch (const std::exception& error) {
      std::fprintf(stderr, "CATALOG: %s request failed: %s\n", kindText.c_str(), error.what());
      recordFailure();
      publishCatalog(id, std::string("{\"error\":\"") + "Could not load from Spotify." + "\",\"loading\":false}", true);
    } catch (...) {
      std::fprintf(stderr, "CATALOG: %s request failed\n", kindText.c_str());
      recordFailure();
      publishCatalog(id, "{\"error\":\"Could not load from Spotify.\",\"loading\":false}", true);
    }
  }).detach();
  return id;
}
uint64_t ipad_catalog_poll(uint64_t request, uint64_t since, char* output, uint32_t capacity, int* done) {
  if (!output || !capacity) return 0;
  std::lock_guard<std::mutex> lock(catalogMutex);
  auto found = catalogResults.find(request);
  if (found == catalogResults.end() || found->second.revision <= since) return 0;
  if (found->second.json.size() >= capacity) { output[0] = 0; return 0; }
  std::snprintf(output, capacity, "%s", found->second.json.c_str());
  if (done) *done = found->second.done ? 1 : 0;
  return found->second.revision;
}
void ipad_catalog_forget(uint64_t request) {
  std::lock_guard<std::mutex> lock(catalogMutex);
  catalogResults.erase(request);
}

void ipad_engine_stop(void) {
  std::function<void()> handler;
  { std::lock_guard<std::mutex> lock(bridgeMutex); stopFlag = true; handler = stopHandler; }
  std::fprintf(stderr, "APP: engine stop requested\n");
  if (handler) { try { handler(); } catch (...) {} }
}
int ipad_engine_stop_requested(void) { return stopFlag ? 1 : 0; }
void ipad_engine_drop_connection(void) {
  std::function<void()> handler;
  { std::lock_guard<std::mutex> lock(bridgeMutex); handler = dropHandler; }
  if (handler) { try { handler(); } catch (...) {} }
}
int ipad_player_set_repeat(int mode) {
  if (mode < 0 || mode > 2) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (state.state != IPadReady || !setRepeatMode) return 0;
  pendingRepeat = mode; state.repeat = mode;
  return 1;
}
int ipad_player_queue_tracks(const char* json) {
  if (!json) return 0;
  std::vector<std::string> uris;
  try {
    auto document = nlohmann::json::parse(json);
    if (!document.is_object() || !document.count("uris") || !document["uris"].is_array()) return 0;
    for (const auto& item : document["uris"]) if (item.is_string() && validTrack(item.get<std::string>())) uris.push_back(item.get<std::string>());
  } catch (...) { return 0; }
  if (uris.empty()) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (state.state != IPadReady || !state.hasTrack || !enqueueTracks) return 0;
  pendingQueue.insert(pendingQueue.end(), uris.begin(), uris.end());
  return 1;
}
void ipad_player_reconnecting(int reconnecting) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.reconnecting = reconnecting ? 1 : 0;
}
int ipad_engine_discoverable(void) { struct stat info; return stat(kHiddenMarker, &info) == 0 ? 0 : 1; }
void ipad_engine_set_discoverable(int on) {
  if (on) std::remove(kHiddenMarker); else { std::ofstream marker(kHiddenMarker); marker << "hidden"; }
  std::function<void(bool)> handler;
  { std::lock_guard<std::mutex> lock(bridgeMutex); handler = discoverableHandler; }
  if (handler) { try { handler(on != 0); } catch (...) { std::fprintf(stderr, "APP: visibility change failed\n"); } }
}
void ipad_engine_stop_clear(void) { stopFlag = false; }
void ipad_player_snapshot(IPadPlayerSnapshot* output) {
  if (!output) return;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  *output = state;
  output->positionMs = currentPosition();
  output->pending = static_cast<int>(commands.size()) + (pendingPlay.valid ? 1 : 0);
}
int ipad_player_command(int command) {
  if (command < IPadTogglePause || command > IPadNext) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (!control || state.state != IPadReady || !state.hasTrack || state.loading || commands.size() >= 8) return 0;
  commands.push_back(command);
  return 1;
}
int ipad_player_play_tracks(const char* json) {
  if (!json) return 0;
  PendingPlay play;
  try {
    auto document = nlohmann::json::parse(json);
    if (!document.is_object() || !document.count("uris") || !document["uris"].is_array()) return 0;
    for (const auto& item : document["uris"]) {
      if (!item.is_string()) continue;
      auto uri = item.get<std::string>();
      if (validTrack(uri)) play.uris.push_back(uri);
      if (play.uris.size() >= 500) break;
    }
    if (play.uris.empty()) return 0;
    play.index = document.count("index") && document["index"].is_number_unsigned() ? document["index"].get<size_t>() : 0;
    if (play.index >= play.uris.size()) play.index = 0;
    play.context = document.count("context") && document["context"].is_string() ? document["context"].get<std::string>() : "";
    if (play.context.size() > 200) play.context.clear();
    if (document.count("shuffle") && document["shuffle"].is_boolean() && document["shuffle"].get<bool>() && play.uris.size() > 1) {
      std::swap(play.uris[0], play.uris[play.index]);
      std::shuffle(play.uris.begin() + 1, play.uris.end(), std::mt19937(static_cast<unsigned>(Clock::now().time_since_epoch().count())));
      play.index = 0;
    }
  } catch (...) { return 0; }
  play.valid = true;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (state.state != IPadReady || !playTracks) return 0;
  pendingPlay = std::move(play);
  return 1;
}
int ipad_player_seek(uint32_t positionMs) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (!seekTrack || state.state != IPadReady || !state.hasTrack) return 0;
  if (state.durationMs && positionMs > state.durationMs) positionMs = state.durationMs;
  pendingSeek = true; pendingSeekMs = positionMs;
  // Optimistic position so the scrubber does not jump back while the engine seeks.
  state.positionMs = positionMs; positionAt = Clock::now();
  return 1;
}
uint64_t ipad_player_queue(char* output, uint32_t capacity) {
  if (!output || !capacity) return 0;
  std::lock_guard<std::mutex> lock(bridgeMutex);
  if (queueJSON.size() >= capacity) { output[0] = 0; return 0; }
  std::snprintf(output, capacity, "%s", queueJSON.c_str());
  return queueRevision;
}

static const char* kVolumeFile = "/var/mobile/Documents/phoenix-volume";
uint32_t ipad_player_saved_volume() {
  { std::lock_guard<std::mutex> lock(bridgeMutex); if (volumeKnown) return state.volume; }
  FILE* f = std::fopen(kVolumeFile, "r");
  if (!f) return 65535;
  unsigned value = 65535;
  if (std::fscanf(f, "%u", &value) != 1) value = 65535;
  std::fclose(f);
  return value > 65535 ? 65535 : value;
}
static void persistVolume(uint32_t volume) {
  FILE* f = std::fopen(kVolumeFile, "w");
  if (!f) return;
  std::fprintf(f, "%u\n", (unsigned)volume);
  std::fclose(f);
}
void ipad_player_volume(uint32_t volume) {   // from the engine: the phone moved the slider
  if (volume > 65535) volume = 65535;
  { std::lock_guard<std::mutex> lock(bridgeMutex); state.volume = volume; volumeKnown = true; }
  persistVolume(volume);
}
void ipad_player_report_volume(uint32_t volume) {   // from the UI: the system volume changed
  if (volume > 65535) volume = 65535;
  { std::lock_guard<std::mutex> lock(bridgeMutex); state.volume = volume; volumeKnown = true; pendingVolume = volume; }
  persistVolume(volume);
}
void ipad_player_waiting() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  uint32_t volume = state.volume;   // the system volume outlives engine restarts
  state = {}; state.paused = 1; state.volume = volume; resetHandlersLocked(); catalogService = nullptr; stopHandler = nullptr;
  positionAt = Clock::now();
}
void ipad_player_connecting() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  state.state = IPadConnecting;
}
void ipad_player_failed(const char* error) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  freezePosition(); state.state = IPadFailed; state.paused = 1;
  state.loading = 0; resetHandlersLocked(); catalogService = nullptr;
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
  // The engine reports the 128-bit GID as hex; the UI works with base62 ids from URIs.
  std::string trackId = id ? id : "";
  if (trackId.size() == 32) { auto converted = ipad_player::base62FromHex(trackId); if (!converted.empty()) trackId = converted; }
  copyText(state.trackId, trackId.c_str()); copyText(state.title, title);
  copyText(state.artist, artist); copyText(state.album, album); copyText(state.artwork, artwork);
  state.durationMs = duration; state.hasTrack = 1;
  // An explicit load reports its start position first (PLAYBACK_START -> ipad_player_loading).
  // A natural transition to the next track reports only TRACK_INFO, and the engine's own
  // position is 0 there, so start from 0 instead of carrying the previous track's position.
  if (!state.loading) state.positionMs = 0;
  state.loading = 0;
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
void setPlaybackHandlers(std::function<bool(const std::vector<std::string>&, size_t, const std::string&)> play,
                         std::function<void(uint32_t)> seek) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  playTracks = std::move(play); seekTrack = std::move(seek);
}
void setCatalogService(std::function<void(const std::string&, const std::string&, const CatalogPublish&)> service) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  catalogService = std::move(service);
}
void clearControlHandler() {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  resetHandlersLocked(); catalogService = nullptr; stopHandler = nullptr;
}
void setQueueHandlers(std::function<void(const std::vector<std::string>&)> enqueue, std::function<void(int)> repeat) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  enqueueTracks = std::move(enqueue); setRepeatMode = std::move(repeat);
}
void setVolumeHandler(std::function<void(uint32_t)> handler) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  setRemoteVolume = std::move(handler);
}
void setDropHandler(std::function<void()> handler) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  dropHandler = std::move(handler);
}
void setDiscoverableHandler(std::function<void(bool)> handler) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  discoverableHandler = std::move(handler);
}
void setStopHandler(std::function<void()> handler) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  stopHandler = std::move(handler);
}
bool stopRequested() { return stopFlag; }
void dispatchPending() {
  PendingPlay play; bool seek = false; uint32_t seekMs = 0;
  std::function<bool(const std::vector<std::string>&, size_t, const std::string&)> playHandler;
  std::function<void(uint32_t)> seekHandler;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    if (pendingPlay.valid) { play = std::move(pendingPlay); pendingPlay = PendingPlay{}; }
    if (pendingSeek) { seek = true; seekMs = pendingSeekMs; pendingSeek = false; }
    playHandler = playTracks; seekHandler = seekTrack;
  }
  if (play.valid && playHandler) {
    try {
      if (playHandler(play.uris, play.index, play.context)) {
        nlohmann::json queue{{"uris", play.uris}, {"index", play.index}, {"context", play.context}};
        std::lock_guard<std::mutex> lock(bridgeMutex);
        queueUris = play.uris; queueIndex = play.index; queueContext = play.context;
        queueJSON = queue.dump(); ++queueRevision;
      } else std::fprintf(stderr, "CATALOG: local track load unavailable\n");
    } catch (const std::exception& error) { std::fprintf(stderr, "CATALOG: local track load failed: %s\n", error.what()); }
    catch (...) { std::fprintf(stderr, "CATALOG: local track load failed\n"); }
  }
  if (seek && seekHandler) {
    try { seekHandler(seekMs); } catch (...) { std::fprintf(stderr, "UI: seek failed\n"); }
  }
  std::vector<std::string> toQueue; int repeatMode = -1;
  std::function<void(const std::vector<std::string>&)> enqueueHandler; std::function<void(int)> repeatHandler;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    toQueue.swap(pendingQueue); repeatMode = pendingRepeat; pendingRepeat = -1;
    enqueueHandler = enqueueTracks; repeatHandler = setRepeatMode;
  }
  if (!toQueue.empty() && enqueueHandler) {
    try {
      enqueueHandler(toQueue);
      std::lock_guard<std::mutex> lock(bridgeMutex);
      // Mirror the insertion in the queue snapshot, right after the playing track.
      size_t at = 0;
      std::string current = state.trackId;
      for (size_t i = 0; i < queueUris.size(); ++i) if (queueUris[i].size() == 36 && queueUris[i].compare(14, 22, current) == 0) { at = i + 1; break; }
      if (at == 0) at = std::min(queueIndex + 1, queueUris.size());
      queueUris.insert(queueUris.begin() + at, toQueue.begin(), toQueue.end());
      queueJSON = nlohmann::json{{"uris", queueUris}, {"index", queueIndex}, {"context", queueContext}}.dump(); ++queueRevision;
    } catch (...) { std::fprintf(stderr, "UI: add to queue failed\n"); }
  }
  if (repeatMode >= 0 && repeatHandler) { try { repeatHandler(repeatMode); } catch (...) {} }
  long volumeToSend = -1; std::function<void(uint32_t)> volumeHandler;
  { std::lock_guard<std::mutex> lock(bridgeMutex); volumeToSend = pendingVolume; pendingVolume = -1; volumeHandler = setRemoteVolume; }
  if (volumeToSend >= 0 && volumeHandler) { try { volumeHandler((uint32_t)volumeToSend); } catch (...) {} }
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
