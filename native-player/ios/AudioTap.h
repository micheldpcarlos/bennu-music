// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Called by the audio sink with interleaved 16-bit stereo frames at 44.1 kHz.
void ipad_audio_tap_write(const int16_t* samples, size_t frames);
// Fills `bands` (0..1, log-spaced spectrum) and `wave` (-1..1, recent mono waveform) for the UI.
// Returns 0 when no audio has been written recently (silence/paused).
int ipad_audio_tap_read(float* bands, int bandCount, float* wave, int waveCount, float* level);
#ifdef __cplusplus
}
#endif
