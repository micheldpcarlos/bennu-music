# Background playback checkpoint — 2026-10-06 (São Paulo)

Device: iPad2,4 / K93aAP, iOS 9.3.5, jailbroken. Build host: Apple Silicon Mac,
Xcode 27, legacy iOS 9.3 SDK overlay, LLVM libc++ 3.8.1 headers.

## Confirmed on the device

- C, C++ runtime, threads, exceptions, backported variant/optional/string_view,
  JSON and byte-order compatibility probes pass.
- AudioQueue tone works. Full ARMv7 CSpot builds and starts.
- Bonjour advertises `_spotify-connect._tcp`, CPath `/spotify_info`, port 7864.
- Spotify authorization, audio-key retrieval, CDN access, decoding, and audible
  playback work on the iPad. The Mac is not the playback engine.
- Detached command-line process stays alive during screen-off failures.
- Manual screen-off stops sound; automatic screen sleep can produce cutting.
- Diagnostics report initial queue running=1, with no captured interruption or
  queue-stop event in the supplied excerpt. This does not prove queue health.

## Required fixes already applied on the user's Mac

- ARM mode (`-marm`), legacy libc++ headers, C++14 backports.
- Corrected SDK ARMv7 stubs and added libSystem memory/string exports to both
  libSystem aliases: memcmp, memcpy, memmove, memset, memchr, strchr, strcmp,
  strncmp. Normalizer repair must remain reproducible.
- Mbed TLS `MBEDTLS_PLATFORM_MS_TIME_ALT`, project-owned Mach timer source.
- Explicit lock_guard template types, `<cmath>` in Compressor, removed unused
  string_view include in CDNAudioFile, brace-initialized pendingSeekPositionMs.
- Direct iOS libsystem_dnssd stub linking, CLI MACOSX_BUNDLE FALSE.
- Value capture of hashFunc; audio PCM buffer uses 32 chunks rather than 128K
  chunks (the latter requested 539,754,496 bytes).
- Free-space check is capacity minus size, not size minus capacity.
- Replaced executable filenames when deploying to avoid observed Killed:9 after
  overwriting an existing executable. This is an observed workaround, not a
  proven general diagnosis of signing behavior.

## This patch's experiment

Add a separate UIKit executable, start the same engine on a worker thread,
retain a UIKit main run loop, and declare UIBackgroundModes=audio. Install in
/Applications using the existing jailbreak, refresh application registration,
and launch from the iPad Home screen. Background audio is NOT yet confirmed.
No private sleep-prevention entitlement or display wake lock is added.

This patch adds the app wrapper only. It requires the current working source
with the fixes listed above; it is not a replacement for port patch 1 or a
complete standalone source distribution. A final release must consolidate all
patches, toolchain inputs, dependency revisions and licenses into one build.

## Release work still required

- Test screen lock, automatic sleep, Home/background, route changes, headphone
  removal, Wi-Fi recovery, app relaunch, reboot, and sustained memory/CPU usage.
- Remove dependency on an external Spotify controller for ordinary use: search,
  playlists, local transport control and reusable authentication are unfinished.
- Implement interruption/underrun recovery and accurate Spotify playback state.
- Package install/update/uninstall and preserve user credentials safely.
- Test other iPad 2 variants; only iPad2,4 is confirmed. Jailbreak required.
- Ship GPL corresponding source and dependency notices; do not redistribute
  Apple's legacy SDK. The receiver and placeholder app are experimental.
