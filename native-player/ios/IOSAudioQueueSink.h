#pragma once
#include "AudioSink.h"
#include <AudioToolbox/AudioToolbox.h>
#include <array>
#include <condition_variable>
#include <mutex>

// Bounded blocking PCM sink. No network or decoder work runs in the callback.
class IOSAudioQueueSink : public AudioSink {
 public:
  IOSAudioQueueSink() = default;
  ~IOSAudioQueueSink() override;
  bool setParams(uint32_t sampleRate, uint8_t channels, uint8_t bits) override;
  void feedPCMFrames(const uint8_t* data, size_t bytes) override;
  // Spotify Connect volume, 0..65535, applied as a cubic gain on the AudioQueue.
  void volumeChanged(uint16_t volume) override;
 private:
  static constexpr size_t BufferCount = 16;
  static constexpr UInt32 BufferBytes = 8192;
  AudioQueueRef queue = nullptr;
  std::array<AudioQueueBufferRef, BufferCount> buffers{};
  std::array<bool, BufferCount> available{};
  std::mutex mutex;
  std::condition_variable ready;
  bool stopped = true;
  bool started = false;
  size_t primedBuffers = 0;
  bool sessionActive = false;
  uint16_t volume = 65535;
  void applyVolume();
  static void consumed(void* context, AudioQueueRef, AudioQueueBufferRef buffer);
  void close();
};
