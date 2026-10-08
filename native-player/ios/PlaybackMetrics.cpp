// SPDX-License-Identifier: GPL-3.0-or-later
#include "PlaybackMetrics.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <mutex>
#include <thread>
#include <sys/time.h>

namespace {
std::atomic<uint32_t> decodedBytes{0}, queuedBytes{0}, consumedBytes{0};
std::atomic<uint32_t> emptyReads{0};
std::atomic<bool> waitingForQueue{false};
std::once_flag reporterOnce;
long long milliseconds() {
  timeval now{};
  gettimeofday(&now, nullptr);
  return static_cast<long long>(now.tv_sec) * 1000 + now.tv_usec / 1000;
}
void report() {
  uint32_t previousDecoded = 0, previousQueued = 0, previousConsumed = 0;
  uint32_t previousEmpty = 0;
  long long previousTime = milliseconds();
  for (;;) {
    std::this_thread::sleep_for(std::chrono::seconds(30));  // diagnostics only; 2 s filled the log
    const long long now = milliseconds();
    const uint32_t d = decodedBytes.load(std::memory_order_relaxed);
    const uint32_t q = queuedBytes.load(std::memory_order_relaxed);
    const uint32_t c = consumedBytes.load(std::memory_order_relaxed);
    const uint32_t e = emptyReads.load(std::memory_order_relaxed);
    std::fprintf(stderr,
      "METRICS: epoch_ms=%lld interval_ms=%lld decoded=%u queued=%u consumed=%u empty_reads=%u waiting=%u\n",
      now, now - previousTime, static_cast<unsigned>(d - previousDecoded),
      static_cast<unsigned>(q - previousQueued), static_cast<unsigned>(c - previousConsumed),
      static_cast<unsigned>(e - previousEmpty),
      waitingForQueue.load(std::memory_order_relaxed) ? 1u : 0u);
    previousTime = now;
    previousDecoded = d; previousQueued = q; previousConsumed = c; previousEmpty = e;
  }
}
}
namespace ipad_metrics {
void startReporter() {
  std::call_once(reporterOnce, [] { std::thread(report).detach(); });
}
void decoded(std::size_t bytes) { decodedBytes.fetch_add(static_cast<uint32_t>(bytes), std::memory_order_relaxed); }
void enqueued(std::size_t bytes) { queuedBytes.fetch_add(static_cast<uint32_t>(bytes), std::memory_order_relaxed); }
void consumed(std::size_t bytes) { consumedBytes.fetch_add(static_cast<uint32_t>(bytes), std::memory_order_relaxed); }
void emptyRead() { emptyReads.fetch_add(1, std::memory_order_relaxed); }
void waiting(bool value) { waitingForQueue.store(value, std::memory_order_relaxed); }
}
