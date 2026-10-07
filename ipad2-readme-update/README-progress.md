<!-- ipad2-media-progress:start -->
## Project status — 6 October 2026

We have an experimental native Spotify Connect receiver running on a jailbroken
iPad 2. The iPad performs streaming, decoding and audio playback itself. A Mac
is used to build and install it; it does not need to remain running for playback.
A phone or computer running Spotify currently selects music and controls the
receiver. Standalone search, playlists and playback selection on the iPad are
not implemented yet.

### Verified hardware and software

| Item | Tested configuration |
| --- | --- |
| iPad | iPad2,4, hardware K93aAP |
| Operating system | iOS 9.3.5 (13G36), jailbroken |
| Engine | CSpot with Bell, native ARMv7 port |
| Audio | Apple AudioQueue, 44.1 kHz stereo, signed 16-bit PCM |
| Test bitrate | 160 kbps |
| Application | UIKit wrapper with `UIBackgroundModes=audio` |
| Audio session | AVAudioSession Playback category, Default mode |
| Build host | Apple Silicon Mac, Xcode 27, normalized iOS 9.3 SDK |
| C++ compatibility | C++14, LLVM libc++ 3.8.1 headers, backported types |

CSpot base revision: `1b07a9c00ba6d5e878e5b33dcbf89bff493cde26`.
Bell base revision: `e83737367a08b5a5a1f652a7ecb97a0d926929dd`.
The working tree contains additional local port changes beyond these revisions.

### Confirmed results

- C and C++ executables run on the iPad. Tests cover threads, exceptions,
  variant, optional, string views, JSON and byte order.
- The app builds, signs, installs in `/Applications/iPad2MediaPlayer.app`, and
  launches from the Home screen.
- Spotify discovers the receiver via Bonjour, authenticates, obtains audio
  keys, downloads tracks and plays audible music on the iPad.
- Screen-off playback worked after increasing AudioQueue capacity and adding
  startup prefill. This is a successful device test, not a completed endurance
  or battery validation campaign.

The earlier screen-off failure occurred while decoder and queue counters
continued at approximately the expected PCM rate. The measured hardware I/O
interval increased from 23.22 ms in the foreground to 92.88 ms in the background.
The previous four queued 4 KiB chunks held only about one background I/O interval.
Increasing queue capacity to sixteen buffers and priming eight before starting
resolved the reported test. With normal full chunks, this gives approximately
371 ms of queued PCM capacity and 186 ms of startup prefill. Actual occupancy
depends on chunk sizes. Both buffering and AVAudioSession changes remain in the
working build; they should be retained until independently tested otherwise.

### Required port fixes to preserve

1. Compile ARMv7 using `-marm`; the initial Thumb executable failed at runtime.
2. Use the legacy SDK overlay and libc++ headers with C++14 backports rather than
   linking ARMv7 against the current iOS SDK.
3. Normalize device architecture sections in SDK stubs. Preserve repaired
   libSystem memory/string exports in both alias stubs; do not redistribute
   Apple's SDK.
4. Use a project-owned Mach timer through Mbed TLS's
   `MBEDTLS_PLATFORM_MS_TIME_ALT`; iOS 9 lacks `clock_gettime`.
5. Preserve explicit lock_guard types, atomic brace initialization, missing math
   includes and other C++ compatibility changes.
6. Link iOS DNS-SD through the normalized `libsystem_dnssd` stub. The app also
   needs UIKit, Foundation, CoreGraphics, AVFoundation and AudioToolbox.
7. Capture the track hash functor by value. Allocate the central PCM buffer in
   chunks: 32 chunks, rather than the previous 128K chunks / 515 MiB allocation.
8. Calculate central-buffer free space as capacity minus size. Retry when full
   rather than silently consuming decoded PCM that was not stored.
9. Preserve sixteen AudioQueue buffers and the eight-buffer startup prefill.
10. Launch the UIKit app via SpringBoard with background audio declared; retain
    AVAudioSession setup and the main app run loop.
11. Sign the executable and refresh app registration during installation.
    Fresh executable filenames avoided an observed `Killed: 9` problem after
    overwriting a previously deployed binary. This workaround's exact cause has
    not been independently established.

Build the current app from the project root:

```sh
source native-player/build-venv/bin/activate
bash native-player/ios/app/build-app.sh
```

Output: `native-player/ios/build/iPad2MediaPlayer.app`.
Current device log: `/var/mobile/Documents/cspot-app.log`.
The HTTP discovery endpoint is `/spotify_info` on port 7864; it is not yet a
local search or playback-control API. Credentials and temporary CDN URLs must
not be included in public source snapshots or issue logs.

### Current limitations

- Spotify on another device supplies selection and transport controls.
- The placeholder iPad screen does not implement search, playlists or transport.
- One launch failed with a Spotify-server connection exception; restarting the
  app recovered. Automatic reconnect and user-visible error recovery are pending.
- Pause/resume behavior, long playlists, interruptions, Wi-Fi recovery, route
  changes and battery consumption still need systematic testing.
- Only iPad2,4 has been tested. Other iPad 2 variants are planned, unverified.
- The original Linux/Cascadia and Chromium experiments are paused. Neither is
  required by the current working native playback path.
- The port is a sequence of local patches. A clean, consolidated, reproducible
  source release and installer are not yet ready.

### Roadmap toward a standalone player

1. **Checkpoint and consolidate the working port.** Record all source changes,
   dependency revisions, toolchain requirements and license notices. Rebuild
   from the consolidated tree. Preserve a known working device installation.
2. **Validate playback reliability.** Run a playlist for at least 30 minutes
   with the display off; check track changes, pause/resume, backgrounding,
   repeated screen wake/lock, speaker/headphone routes and Wi-Fi interruption.
   Check memory and battery use. Remove high-frequency diagnostic logging after
   diagnosis, retaining concise error and lifecycle logs.
3. **Add on-iPad engine controls.** First play one known Spotify track URI from
   an on-device control without another Spotify app selecting it. Implement
   local play/pause, next/previous and seeking where the engine supports them.
   The existing `SpircHandler::loadTrackFromURI` is currently an empty stub;
   having a Connect receiver does not automatically provide standalone control.
4. **Add reusable authentication and reconnect.** Confirm engine credentials can
   be safely saved and reused across app launches. Provide retry/status behavior
   and clean teardown. Initial account linking may still require another device;
   routine playback should not require it to remain running.
5. **Build an iOS 9-compatible interface.** Start with a small UIKit UI for
   playback and status. Add search and playlist browsing through an appropriate
   Spotify metadata/authentication integration. Verify available endpoints and
   developer-account restrictions before committing to that design. The Web API
   is not the audio-streaming engine; keep audio in the native CSpot pipeline.
6. **Prepare distribution.** Package install/update/uninstall, credential
   preservation, source and notices, supported-device requirements and a tested
   recovery procedure. Expand the hardware test matrix before claiming support
   for most iPad 2 models. Confirm independent app-launch and reboot behavior.

The next implementation milestone is local playback of a known track on the
iPad without a live Spotify controller. It proves the missing standalone
control path before investing in a complete browsing interface.
<!-- ipad2-media-progress:end -->
