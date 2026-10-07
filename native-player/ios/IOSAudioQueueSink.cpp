#ifdef CSPOT_IOS_APP
bool ipadAppActivateAudioSession();
void ipadAppDeactivateAudioSession();
#endif
#include "PlaybackMetrics.h"
#include "IOSAudioQueueSink.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <stdexcept>

namespace {

void logAudioInterruption(void*, UInt32 state) {
  std::fprintf(stderr, "AUDIO: session interruption %s\n",
      state == kAudioSessionBeginInterruption ? "began" : "ended");
}
void logQueueState(void*, AudioQueueRef queue, AudioQueuePropertyID) {
  UInt32 running = 0;
  UInt32 size = sizeof(running);
  OSStatus status = AudioQueueGetProperty(
      queue, kAudioQueueProperty_IsRunning, &running, &size);
  std::fprintf(stderr, "AUDIO: queue running=%u status=%ld\n",
      static_cast<unsigned>(running), static_cast<long>(status));
}
bool ok(OSStatus status, const char* operation) {
  if (status == noErr) return true;
  std::fprintf(stderr, "%s failed: %ld\n", operation, static_cast<long>(status));
  return false;
}
}
IOSAudioQueueSink::~IOSAudioQueueSink() { close(); }

void IOSAudioQueueSink::close() {
  {
    std::lock_guard<std::mutex> lock(mutex);
    stopped = true;
  }
  ready.notify_all();
  if (queue) {
    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);
    queue = nullptr;
  }
  if (sessionActive) {
#ifdef CSPOT_IOS_APP
    ipadAppDeactivateAudioSession();
#else
    AudioSessionSetActive(false);
#endif
    sessionActive = false;
  }
  buffers.fill(nullptr);
  available.fill(false);
  started = false;
  primedBuffers = 0;
}

bool IOSAudioQueueSink::setParams(uint32_t rate, uint8_t channels, uint8_t bits) {
  close();
  // CliPlayer supplies interleaved stereo signed 16-bit PCM at 44.1 kHz.
  if (rate != 44100 || channels != 2 || bits != 16) return false;
#ifdef CSPOT_IOS_APP
  if (!ipadAppActivateAudioSession()) return false;
#else
  static const OSStatus initialized = AudioSessionInitialize(nullptr, nullptr, logAudioInterruption, nullptr);
  if (!ok(initialized, "AudioSessionInitialize")) return false;
  UInt32 category = kAudioSessionCategory_MediaPlayback;
  if (!ok(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                  sizeof(category), &category), "Audio category")) return false;
  if (!ok(AudioSessionSetActive(true), "Audio session activation")) return false;
#endif
  sessionActive = true;

  AudioStreamBasicDescription format{};
  format.mSampleRate = rate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  format.mBytesPerPacket = format.mBytesPerFrame = channels * bits / 8;
  format.mFramesPerPacket = 1;
  format.mChannelsPerFrame = channels;
  format.mBitsPerChannel = bits;
  // NULL run loop requests AudioQueue's internal callback thread.
  if (!ok(AudioQueueNewOutput(&format, consumed, this, nullptr, nullptr, 0, &queue),
          "AudioQueueNewOutput")) { close(); return false; }
  ok(AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, logQueueState, nullptr), "Queue state listener");
  for (size_t i = 0; i < BufferCount; ++i) {
    if (!ok(AudioQueueAllocateBuffer(queue, BufferBytes, &buffers[i]),
            "AudioQueueAllocateBuffer")) { close(); return false; }
    available[i] = true;
  }
  {
    std::lock_guard<std::mutex> lock(mutex);
    stopped = false;
  }
  ipad_metrics::startReporter();
  std::puts("iPad AudioQueue ready: 44100 Hz, stereo, 16-bit PCM");
  return true;
}

void IOSAudioQueueSink::consumed(void* context, AudioQueueRef, AudioQueueBufferRef buffer) {
  ipad_metrics::consumed(buffer->mAudioDataByteSize);
  auto* self = static_cast<IOSAudioQueueSink*>(context);
  {
    std::lock_guard<std::mutex> lock(self->mutex);
    for (size_t i = 0; i < BufferCount; ++i) {
      if (self->buffers[i] == buffer) { self->available[i] = true; break; }
    }
  }
  self->ready.notify_one();
}

void IOSAudioQueueSink::feedPCMFrames(const uint8_t* data, size_t bytes) {
  if (bytes % 4) throw std::runtime_error("PCM data is not stereo-frame aligned");
  while (bytes) {
    size_t slot;
    {
      std::unique_lock<std::mutex> lock(mutex);
      ipad_metrics::waiting(true);
      ready.wait(lock, [this] {
        return stopped || std::any_of(available.begin(), available.end(), [](bool free) { return free; });
      });
      ipad_metrics::waiting(false);
      if (stopped) throw std::runtime_error("AudioQueue is stopped");
      slot = static_cast<size_t>(std::find(available.begin(), available.end(), true) - available.begin());
      available[slot] = false;
    }
    AudioQueueBufferRef buffer = buffers[slot];
    UInt32 count = static_cast<UInt32>(std::min(bytes, static_cast<size_t>(BufferBytes)));
    std::memcpy(buffer->mAudioData, data, count);
    buffer->mAudioDataByteSize = count;
    if (!ok(AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr), "AudioQueueEnqueueBuffer")) {
      close(); throw std::runtime_error("Cannot enqueue audio");
    }
    ipad_metrics::enqueued(count);
    if (!started && ++primedBuffers >= 8) {
      if (!ok(AudioQueueStart(queue, nullptr), "AudioQueueStart")) {
        close(); throw std::runtime_error("Cannot start audio");
      }
      started = true;
    }
    data += count;
    bytes -= count;
  }
}
