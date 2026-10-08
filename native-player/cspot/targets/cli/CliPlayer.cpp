#ifdef CSPOT_IOS_APP
#include "PlayerBridge.h"
#endif
#ifdef CSPOT_ENABLE_IOS_SINK
#include "PlaybackMetrics.h"
#endif
#include "CSpotCompat.h"
#include "CliPlayer.h"

#include <cstdint>      // for uint8_t
#include <functional>   // for __base
#include <iostream>     // for operator<<, basic_ostream, endl, cout
#include <memory>       // for shared_ptr, make_shared, make_unique
#include <mutex>        // for scoped_lock
#include <type_traits>  // for remove_extent_t
#include <utility>      // for move
#include <vector>       // for vector

#include "BellDSP.h"             // for BellDSP, BellDSP::FadeEffect, BellDS...
#include "BellUtils.h"           // for BELL_SLEEP_MS
#include "CentralAudioBuffer.h"  // for CentralAudioBuffer::AudioChunk, Cent...
#include "Logger.h"
#include "SpircHandler.h"  // for SpircHandler, SpircHandler::EventType
#include "StreamInfo.h"    // for BitWidth, BitWidth::BW_16
#include "TrackPlayer.h"   // for TrackPlayer

CliPlayer::CliPlayer(std::unique_ptr<AudioSink> sink,
                     std::shared_ptr<cspot::SpircHandler> handler)
    : bell::Task("player", 1024, 0, 0) {
  this->handler = handler;
  this->audioSink = std::move(sink);
#ifdef CSPOT_IOS_APP
  // Start at the level the phone last set; the engine reports the same value to Spotify.
  this->audioSink->volumeChanged(static_cast<uint16_t>(std::min<uint32_t>(ipad_player_saved_volume(), 65535)));
#endif

  this->centralAudioBuffer =
      std::make_shared<bell::CentralAudioBuffer>(
#ifdef CSPOT_LEGACY_IOS
          32
#else
          128 * 1024
#endif
      );

#ifndef BELL_DISABLE_CODECS
  this->dsp = std::make_shared<bell::BellDSP>(this->centralAudioBuffer);
#endif

  auto hashFunc = std::hash<cspot_compat::string_view>();

  this->handler->getTrackPlayer()->setDataCallback(
      [this, hashFunc](uint8_t* data, size_t bytes, cspot_compat::string_view trackId) {
        auto hash = hashFunc(trackId);

        size_t written = this->centralAudioBuffer->writePCM(data, bytes, hash);
#ifdef CSPOT_ENABLE_IOS_SINK
        ipad_metrics::decoded(written);
#endif
        return written;
      });

  this->isPaused = false;

  this->handler->setEventHandler(
      [this](std::unique_ptr<cspot::SpircHandler::Event> event) {
#ifdef CSPOT_IOS_APP
        // Mirror events; preserve the engine's existing audio handler below.
        switch (event->eventType) {
          case cspot::SpircHandler::EventType::TRACK_INFO: {
            const auto& track = cspot_compat::get<cspot::TrackInfo>(event->data);
            ipad_player_track(track.trackId.c_str(), track.name.c_str(),
                track.artist.c_str(), track.album.c_str(), track.imageUrl.c_str(), track.duration);
            break;
          }
          case cspot::SpircHandler::EventType::PLAY_PAUSE:
            ipad_player_paused(cspot_compat::get<bool>(event->data));
            break;
          case cspot::SpircHandler::EventType::PLAYBACK_START: {
            int position = cspot_compat::get<int>(event->data);
            ipad_player_loading(position < 0 ? 0 : static_cast<uint32_t>(position));
            break;
          }
          case cspot::SpircHandler::EventType::SEEK: {
            int position = cspot_compat::get<int>(event->data);
            ipad_player_position(position < 0 ? 0 : static_cast<uint32_t>(position));
            break;
          }
          case cspot::SpircHandler::EventType::DISC:
            ipad_player_inactive();
            break;
          default: break;
        }
#endif
        switch (event->eventType) {
          case cspot::SpircHandler::EventType::PLAY_PAUSE:
            if (cspot_compat::get<bool>(event->data)) {
              this->pauseRequested = true;
            } else {
              this->isPaused = false;
              this->pauseRequested = false;
            }
            break;
          case cspot::SpircHandler::EventType::FLUSH: {
            this->centralAudioBuffer->clearBuffer();
            break;
          }
          case cspot::SpircHandler::EventType::DISC:
            this->centralAudioBuffer->clearBuffer();
            break;
          case cspot::SpircHandler::EventType::SEEK:
            this->centralAudioBuffer->clearBuffer();
            break;
          case cspot::SpircHandler::EventType::PLAYBACK_START:
            this->isPaused = true;
            this->playlistEnd = false;
            this->centralAudioBuffer->clearBuffer();
            this->trackNotificationPending = true;
            break;
          case cspot::SpircHandler::EventType::DEPLETED:
            this->playlistEnd = true;
            break;
          case cspot::SpircHandler::EventType::VOLUME: {
            int volume = cspot_compat::get<int>(event->data);
            if (volume < 0) volume = 0;
            if (volume > 65535) volume = 65535;
            this->audioSink->volumeChanged(static_cast<uint16_t>(volume));
#ifdef CSPOT_IOS_APP
            ipad_player_volume(static_cast<uint32_t>(volume));
#endif
            break;
          }
          default:
            break;
        }
      });
  startTask();
}

void CliPlayer::feedData(uint8_t* data, size_t len) {}

void CliPlayer::runTask() {
  std::vector<uint8_t> outBuf = std::vector<uint8_t>(1024);

  std::lock_guard<decltype(runningMutex)> lock(runningMutex);
  bell::CentralAudioBuffer::AudioChunk* chunk;

  size_t lastHash = 0;

  while (isRunning) {
    if (!this->isPaused) {
      chunk = this->centralAudioBuffer->readChunk();

      if (this->pauseRequested) {
        this->pauseRequested = false;
        std::cout << "Pause requested!" << std::endl;
#ifndef BELL_DISABLE_CODECS
        auto effect = std::make_unique<bell::BellDSP::FadeEffect>(
            44100 / 2, false, [this]() { this->isPaused = true; });
        this->dsp->queryInstantEffect(std::move(effect));
#else
        this->isPaused = true;
#endif
      }

      if (!chunk || chunk->pcmSize == 0) {
#ifdef CSPOT_ENABLE_IOS_SINK
      ipad_metrics::emptyRead();
#endif
        if (this->playlistEnd) {
            this->handler->notifyAudioEnded();
            this->playlistEnd = false;
        }
        BELL_SLEEP_MS(10);
        continue;
      } else {
        // A restart of the same track still needs a metadata/playback notification.
        // Consume the flag separately: short-circuiting on the hash would notify twice.
        bool restarted = this->trackNotificationPending.exchange(false);
        if (lastHash != chunk->trackHash || restarted) {
          std::cout << " Last hash " << lastHash << " new hash "
                    << chunk->trackHash << std::endl;
          lastHash = chunk->trackHash;
          this->handler->notifyAudioReachedPlayback();
        }

#ifndef BELL_DISABLE_CODECS
        this->dsp->process(chunk->pcmData, chunk->pcmSize, 2, 44100,
                           bell::BitWidth::BW_16);
#endif
        this->audioSink->feedPCMFrames(chunk->pcmData, chunk->pcmSize);
      }
    } else {
      BELL_SLEEP_MS(10);
    }
  }
}

void CliPlayer::disconnect() {
  isRunning = false;
  std::lock_guard<decltype(runningMutex)> lock(runningMutex);
}
