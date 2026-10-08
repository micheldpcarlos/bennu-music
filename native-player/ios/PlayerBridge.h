// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
enum IPadPlayerState { IPadWaiting = 0, IPadConnecting = 1, IPadReady = 2, IPadFailed = 3 };
enum IPadPlayerCommand { IPadTogglePause = 1, IPadPrevious = 2, IPadNext = 3 };
typedef struct IPadPlayerSnapshot {
  int state, hasTrack, paused, loading, pending;
  int reconnecting, repeat;   // repeat: 0 off, 1 all, 2 one
  uint32_t positionMs, durationMs;
  uint32_t volume;            // Spotify Connect volume 0..65535 = the iPad's system volume
  char title[256], artist[256], album[256], artwork[512], trackId[128], error[256];
} IPadPlayerSnapshot;

// --- Catalog (browsing data). Requests run on worker threads; the UI polls for results. ---
// kind: "search" (query), "album" (id), "artist" (id), "playlist" (id), "collection", "recent",
// "profile", "context" (uri), "tracks" (comma-separated uris). Returns 0 when the player is not ready.
uint64_t ipad_catalog_request(const char* kind, const char* argument);
int ipad_catalog_kind_enabled(const char* kind);   // 0 when the flags file or the circuit breaker paused this kind
// Copies the latest JSON for a request when its revision is newer than `since`. Returns the new
// revision, or 0 if nothing changed / unknown request / buffer too small. *done is set when final.
uint64_t ipad_catalog_poll(uint64_t request, uint64_t since, char* output, uint32_t capacity, int* done);
void ipad_catalog_forget(uint64_t request);

// --- Playback ---
void ipad_player_snapshot(IPadPlayerSnapshot* output);
int ipad_player_command(int command);
// json: {"uris":[...], "index":n, "context":"spotify:album:...", "shuffle":false}
int ipad_player_play_tracks(const char* json);
int ipad_player_seek(uint32_t positionMs);
int ipad_player_set_repeat(int mode);
// json: {"uris":[...]} inserted right after the playing track ("play next").
int ipad_player_queue_tracks(const char* json);
// Developer aid: drops the access-point socket so the session's reconnect path runs.
void ipad_engine_drop_connection(void);
// Current queue as JSON {"uris":[...],"index":n,"context":"..."} (what was last loaded locally).
uint64_t ipad_player_queue(char* output, uint32_t capacity);

// Sign-out: asks the running engine to disconnect; the app restarts it, which then waits
// for a new account (QR sign-in or Connect pairing).
void ipad_engine_stop(void);
int ipad_engine_stop_requested(void);
void ipad_engine_stop_clear(void);
// Network visibility: whether the iPad advertises itself for Spotify Connect pairing on the LAN.
int ipad_engine_discoverable(void);
// Spotify Connect volume (0..65535) mirrors the iPad's system volume. The engine calls
// ipad_player_volume when the phone moves the slider (the UI then sets the system volume);
// the UI calls ipad_player_report_volume when the system volume changes (the engine tells the phone).
uint32_t ipad_player_saved_volume(void);
void ipad_player_volume(uint32_t volume);
void ipad_player_report_volume(uint32_t volume);
void ipad_engine_set_discoverable(int on);

// --- Engine -> bridge notifications ---
void ipad_player_waiting(void);
void ipad_player_connecting(void);
void ipad_player_failed(const char* error);
void ipad_player_ready(void);
void ipad_player_track(const char* id, const char* title, const char* artist,
    const char* album, const char* artwork, uint32_t durationMs);
void ipad_player_paused(int paused);
void ipad_player_position(uint32_t positionMs);
void ipad_player_loading(uint32_t positionMs);
void ipad_player_inactive(void);
void ipad_player_reconnecting(int reconnecting);
#ifdef __cplusplus
}
#include <functional>
#include <string>
#include <vector>
namespace ipad_player {
// Install and drain on the engine's packet-dispatch thread. UIKit only queues.
void setControlHandler(std::function<bool(int)> handler);
void setPlaybackHandlers(std::function<bool(const std::vector<std::string>&, size_t, const std::string&)> play,
                         std::function<void(uint32_t)> seek);
void setQueueHandlers(std::function<void(const std::vector<std::string>&)> enqueue, std::function<void(int)> repeat);
void setVolumeHandler(std::function<void(uint32_t)> handler);
void setDropHandler(std::function<void()> handler);
// Catalog service: (kind, argument, publish(json, done)). Invoked on a worker thread per request.
using CatalogPublish = std::function<void(const std::string&, bool)>;
void setCatalogService(std::function<void(const std::string&, const std::string&, const CatalogPublish&)> service);
void setStopHandler(std::function<void()> handler);
void setDiscoverableHandler(std::function<void(bool)> handler);
bool stopRequested();
void dispatchPending();
void clearControlHandler();
}
#endif
