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
  uint32_t positionMs, durationMs;
  char title[256], artist[256], album[256], artwork[512], trackId[128], error[256];
} IPadPlayerSnapshot;
int ipad_player_search(const char* query);
int ipad_player_select_track(const char* uri);
uint64_t ipad_player_catalog_snapshot(char* output, uint32_t capacity);
void ipad_player_snapshot(IPadPlayerSnapshot* output);
int ipad_player_command(int command);
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
#ifdef __cplusplus
}
#include <functional>
#include <string>
namespace ipad_player {
// Install and drain on the engine's packet-dispatch thread. UIKit only queues.
void setControlHandler(std::function<bool(int)> handler);
void setCatalogHandlers(std::function<void(std::string, uint64_t)> search,
    std::function<bool(std::string)> play);
void publishCatalog(uint64_t request, const std::string& json);
void dispatchPending();
void clearControlHandler();
}
#endif
