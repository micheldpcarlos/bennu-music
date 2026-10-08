// SPDX-License-Identifier: GPL-3.0-or-later
#include "AudioTap.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <mutex>
#include <vector>
namespace {
const int kRing = 4096;            // mono samples kept (~93 ms)
const int kFFT = 1024;
float ring[kRing];
int ringHead = 0;
std::mutex ringMutex;
std::chrono::steady_clock::time_point lastWrite;
FFTSetup fftSetup = nullptr;
std::vector<float> window, realPart, imagPart, magnitudes;
}
void ipad_audio_tap_write(const int16_t* samples, size_t frames) {
  if (!samples || !frames) return;
  std::lock_guard<std::mutex> lock(ringMutex);
  for (size_t i = 0; i < frames; ++i) {
    float mono = (samples[i * 2] + samples[i * 2 + 1]) * (0.5f / 32768.0f);
    ring[ringHead] = mono; ringHead = (ringHead + 1) % kRing;
  }
  lastWrite = std::chrono::steady_clock::now();
}
int ipad_audio_tap_read(float* bands, int bandCount, float* wave, int waveCount, float* level) {
  if (bandCount <= 0 || !bands) return 0;
  float samples[kFFT];
  bool fresh;
  {
    std::lock_guard<std::mutex> lock(ringMutex);
    fresh = std::chrono::steady_clock::now() - lastWrite < std::chrono::milliseconds(400);
    int start = (ringHead - kFFT + kRing) % kRing;
    for (int i = 0; i < kFFT; ++i) samples[i] = ring[(start + i) % kRing];
  }
  if (!fresh) { std::fill(bands, bands + bandCount, 0.0f); if (wave) std::fill(wave, wave + waveCount, 0.0f); if (level) *level = 0; return 0; }
  if (wave && waveCount > 0) {
    for (int i = 0; i < waveCount; ++i) wave[i] = samples[i * kFFT / waveCount];
  }
  float rms = 0; for (float s : samples) rms += s * s; rms = std::sqrt(rms / kFFT);
  if (level) *level = std::min(1.0f, rms * 4.0f);
  if (!fftSetup) {
    fftSetup = vDSP_create_fftsetup(10, kFFTRadix2);  // 2^10 = 1024
    window.resize(kFFT); vDSP_hann_window(window.data(), kFFT, vDSP_HANN_NORM);
    realPart.resize(kFFT / 2); imagPart.resize(kFFT / 2); magnitudes.resize(kFFT / 2);
  }
  float windowed[kFFT];
  vDSP_vmul(samples, 1, window.data(), 1, windowed, 1, kFFT);
  DSPSplitComplex split{realPart.data(), imagPart.data()};
  vDSP_ctoz(reinterpret_cast<const DSPComplex*>(windowed), 2, &split, 1, kFFT / 2);
  vDSP_fft_zrip(fftSetup, &split, 1, 10, kFFTDirection_Forward);
  vDSP_zvmags(&split, 1, magnitudes.data(), 1, kFFT / 2);
  // Log-spaced bands from ~40 Hz to ~16 kHz, with a gentle log scale for display.
  const float binHz = 44100.0f / kFFT;
  float low = 40.0f, high = 16000.0f;
  for (int b = 0; b < bandCount; ++b) {
    float f0 = low * std::pow(high / low, static_cast<float>(b) / bandCount);
    float f1 = low * std::pow(high / low, static_cast<float>(b + 1) / bandCount);
    int i0 = std::max(1, static_cast<int>(f0 / binHz)), i1 = std::max(i0 + 1, static_cast<int>(f1 / binHz));
    float peak = 0; for (int i = i0; i < i1 && i < kFFT / 2; ++i) peak = std::max(peak, magnitudes[i]);
    float db = 10.0f * std::log10(peak / (kFFT * kFFT) + 1e-9f);   // roughly -90..0
    bands[b] = std::max(0.0f, std::min(1.0f, (db + 70.0f) / 70.0f));
  }
  return 1;
}
