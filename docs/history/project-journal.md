# iPad 2 Media Player

Experimental Linux port for the iPad 2 family, intended to run Chromium for
Spotify web playback, YouTube, and other media websites.

**Status: research and host setup. No Linux boot, audio driver, or browser
playback has been validated on our device.**

Last handoff update: 2026-10-06.

## Confirmed development hardware

The owner ran these commands on their Mac with the iPad connected:

```sh
ideviceinfo -k ProductType
ideviceinfo -k HardwareModel
ideviceinfo -k ProductVersion
uname -m
sw_vers -productVersion
```

| Property | Reported value |
| --- | --- |
| Product type | `iPad2,4` |
| Hardware model | `K93aAP` |
| Installed iOS | `9.3.5` |
| Mac architecture | `arm64` (Apple Silicon) |
| macOS version | `26.6.2` |

- Device currently runs stock iOS 9.3.5.
- No Cydia or jailbreak installed.
- Cable-only kDFU requires a jailbreak first.
- Boot entry method remains undecided.

libirecovery identifies this device as the revised Wi-Fi iPad 2, board
`k93aap`, chip ID `0x8942` (S5L8942X).
An earlier identification as `iPad2,1` from the photo was incorrect; use the
internal readout above. Do not copy serial numbers or network addresses into
public reports.

## Project decisions

- Start with Linux boot and local audio, then networking, display/touch, and
  Chromium. The user explicitly prefers hardware work before a Spotify UI.
- Use existing A5 work as a foundation rather than creating a distribution
  from scratch. The exact userspace distribution remains undecided.
- Aim to cover the iPad 2 family eventually; prove each board separately.
- Prefer temporary boot and RAM/NFS storage during initial development.
- Chromium website playback is the desired experience. Spotify Soloist is a
  fallback, not the current primary implementation target.
- The user has Spotify Premium.

## Workspace layout

The canonical development folder on the owner's Mac is:

```text
<repo>
```

Keep this README at its root and the upstream checkout in `cascadia/`.
Use future `docs/`, `logs/`, and `patches/` directories for research notes,
sanitized results, and changes to the port. Those directories and patches
have not yet been created by this handoff.

## Candidate upstream: Project Cascadia

Repository: https://github.com/rzxvx/Project-Cascadia

The source inspected on 2026-10-06 documents:

- Linux 6.12 and Alpine userspace on the first-generation Wi-Fi iPad mini,
  `iPad2,5`, board `p105ap`, chip S5L8942X.
- macOS/arm64 as a verified build host, using Git, Python 3, rsync and Docker.
- USB console/networking, touch, Wi-Fi and an XFCE framebuffer desktop on its
  target. These are upstream reports, not our tests on the iPad 2.
- A cable-only kDFU route from jailbroken iOS, or checkm8 with a microcontroller.
- Firmware tooling pinned to `iPad2,5` and iOS firmware build
  `8.4.1 / 12H321`, including patches at exact iBEC addresses.
- GPL-2.0 licensing.

**The upstream mini boot configuration is not an iPad 2 port. Do not run its
`flash` command on our device until the boot chain and board configuration
have been adapted and reviewed.** Sharing the chip does not establish that
clocks, interrupts, peripherals, firmware patches or calibration are identical.

Upstream audio support was not established by this review. Its current README
does not substantiate working speaker/headphone playback for our target.
Charging, GPU acceleration and independent startup also need separate checks.

## Host setup and first diagnostics

From the project root, clone upstream into a subdirectory:

```sh
git clone https://github.com/rzxvx/Project-Cascadia.git cascadia
git -C cascadia rev-parse HEAD
cd cascadia
./cascadia doctor
```

Record the printed commit hash with the diagnostic output. The assistant's
separate workspace checkout was cloned and verified clean at
`7d3b5068b4b9b61461f6154316020da65be0f9a1` on 2026-10-06.
The owner's Mac checkout has not yet been verified. Compare its hash before
using this research as a baseline; review future upstream changes before use.

The inspected `doctor` implementation checks dependencies and local build
files. Missing kernel, rootfs, firmware or Legacy iOS Kit are expected on a
fresh checkout. No build or device boot has been attempted in this project.

## Boot route under investigation

1. Determine whether the device is already jailbroken (for example, whether
   Cydia is installed). The user has not answered this yet.
2. Check Legacy iOS Kit's kDFU procedure specifically for `iPad2,4` on iOS
   9.3.5. Cascadia's mini kDFU route is a candidate, not confirmed compatibility.
3. If hardware checkm8 is needed, Legacy iOS Kit recommends an original
   RP2040 Pico/Pico H with micro-USB. Its guide requires a powered micro-USB
   OTG Y adapter and the iPad's 30-pin USB cable. RP2350 Pico 2 is incompatible
   with the documented UF2 files. Use the `8942` variant for this device.
4. Extract and inspect the correct device's stock firmware/Apple device tree.
   Map firmware patches, memory layout and board-specific hardware before
   delivering an experimental kernel.

No external boot hardware has been confirmed available or purchased.

## Milestones

| Milestone | Required evidence |
| --- | --- |
| Board/boot adaptation | Correct `k93aap` description and model-specific firmware patches |
| Minimal Linux boot | Captured console log and repeatable temporary boot |
| Audio | Test tone and local file through a documented output, then sustained playback |
| Network and power | Reliable internet, measured charging/battery behavior |
| Graphics and input | Working display, touch and on-screen keyboard |
| Chromium | One tab, functional local media playback, measured responsiveness/memory use |
| Media websites | Low-resolution YouTube test and separately verified Spotify DRM playback |
| Family support | Repeat the documented tests on each additional revision |

Spotify web playback requires protected-content support such as Widevine.
A compatible ARM32 component has not been established for this setup.
Loading or signing into Spotify is not proof of playback. Hardware video
decoding is also unverified; do not promise smooth YouTube from browser
availability alone.

## Family compatibility matrix

All Linux features are currently untested by this project.

| Identifier | Board | Chip ID | Project status |
| --- | --- | --- | --- |
| `iPad2,1` | `k93ap` | `0x8940` | Future target; no test device confirmed |
| `iPad2,2` | `k94ap` | `0x8940` | Future target; no test device confirmed |
| `iPad2,3` | `k95ap` | `0x8940` | Future target; no test device confirmed |
| `iPad2,4` | `k93aap` | `0x8942` | Confirmed first development device |

Track speakers, headphones, Wi-Fi, touch, charging, graphics, browser media,
storage and boot method separately. Cellular data, cameras and Bluetooth are
outside the first release scope. iPad mini identifiers `iPad2,5`–`iPad2,7`
are different products.

## Next agent handoff

1. Read this README and inspect the actual `cascadia/` checkout.
2. Record its commit and the owner's `doctor` output.
3. Resolve jailbreak status and the exact kDFU/checkm8 boot route.
4. Inspect the firmware-building scripts and `p105ap` DTS for hardcoded
   assumptions; establish the corresponding `k93aap` data from evidence.
5. Work toward console boot before audio reverse-engineering.
6. Preserve logs, commands and patch history; update this README when facts
   change. Clearly distinguish upstream claims from owner-device tests.

The assistant session that wrote this README had no direct USB or filesystem
access to the owner's Mac. Commands must be run there by the owner or a local
agent. No public repository or release has been created.

## Primary references

- [Cascadia README](https://github.com/rzxvx/Project-Cascadia)
- [Cascadia launcher](https://github.com/rzxvx/Project-Cascadia/blob/main/cascadia)
- [Cascadia quick start](https://github.com/rzxvx/Project-Cascadia/blob/main/docs/QUICKSTART.md)
- [Original iBSSloader work](https://github.com/teutekeune/iBSSloader)
- [Legacy iOS Kit A5 boot guide](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/checkm8-a5)
- [libirecovery device mapping](https://github.com/libimobiledevice/libirecovery/blob/master/src/libirecovery.c)
- [ARM32 Chromium package](https://packages.debian.org/trixie/armhf/chromium)
- [Spotify web playback requirements](https://support.spotify.com/us/article/web-player-help/)
- [Soloist downloads](https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates)



## Checkpoint — 2026-10-06

### Confirmed hardware
- iPad: iPad2,4; board K93aAP; iOS 9.3.5.
- Mac: Apple Silicon, arm64; reported macOS 26.6.2.
- Jailbreak status: still unknown.

### Development environment
- Cascadia cloned at:
  7d3b5068b4b9b61461f6154316020da65be0f9a1
- Git, Python 3, rsync and Docker daemon checks pass.
- GitHub kernel requests stalled; kernel.org download succeeded.
- Linux v6.12 downloaded, commit:
  adc218676eef25575469234709c2d87185ca223a
- Initial checkout had filename collisions on the Mac filesystem.
- Created linux-build.sparsebundle using “Case-sensitive APFS”.
- Mounted it at the project’s linux-build directory.
- Re-cloned the kernel locally into linux-build/linux.
- That checkout completed without collision warnings.

### Pending confirmation
The following commands were suggested, but their completion
has not yet been reported:
- Move cascadia/build/linux to build/linux-case-insensitive.
- Run Cascadia’s kernel command with KERNEL_SRC pointing
  to the case-sensitive linux-build/linux checkout.
- Run ./cascadia rootfs.

Keep the disk image mounted when using the kernel source.
After restarting the Mac, remount it from the project root:
hdiutil attach linux-build.sparsebundle -mountpoint "$PWD/linux-build"

### Next work
1. Confirm the kernel source link and rootfs preparation.
2. Establish jailbreak status and the kDFU/checkm8 boot route.
3. Adapt firmware patches and board configuration for K93aAP.
4. Prove minimal Linux boot, then local audio playback.
5. Add networking, display/touch, Chromium and media tests.

### Important limits
- No Linux build or boot validated on our iPad yet.
- Audio, charging, touch and media playback remain untested.
- Upstream firmware tooling targets iPad2,5, not our iPad2,4.
- Do not use the existing mini flash configuration on this device.

### Root filesystem completed
- ./cascadia rootfs succeeded.
- Alpine 3.24.1 armhf filesystem assembled.
- Shared-library dependency checks passed.
- Dropbear installed with the host's SSH public key.
- Generated build/out/initramfs.cpio.gz: approximately 14 MB.
- No kernel build or iPad boot attempted yet.

## Verified checkpoint — 2026-10-06

- Device: iPad2,4 / K93aAP, iOS 9.3.5, jailbroken.
- SSH access works.
- Xcode 27 clang generates ARMv7 code.
- Theos iPhoneOS9.3 SDK used for headers and linking.
- hello-arm runs successfully with -marm.
- Original Thumb build crashes; evidence supports an entry-mode mismatch.
- tone probe plays audible three-second PCM audio using AudioToolbox.
- Minimal TBD v4 device stubs enable framework linking.
- Legacy libSystem linker warnings remain.
- Spotify authentication, decoding and playback are not yet tested.
- Current direction: evaluate a native Spotify engine with a lightweight
  Safari interface, running independently of the Mac.

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


## Checkpoint — 2026-10-06

The native Spotify receiver and Now Playing interface are working on a jailbroken **iPad 2,4 running iOS 9.3.5**.

### Verified on the device

- Spotify discovery, authentication through another Spotify device, and direct streaming to the iPad.
- Native audio output without a continuously running Mac or external playback server.
- Playback with the screen off.
- Now Playing screen with track details, artwork and estimated progress.
- Local play/pause, next-track and previous-track controls.
- Pause/resume crash resolved after fixing concurrent track-list serialization.
- UI refresh corrected when restarting the same track.

### Implementation checkpoint

- ARMv7 build using the legacy iOS 9.3 SDK and compatible C++ headers/backports.
- UIKit app wrapper with background audio support.
- AudioQueue buffering and priming adjusted for screen-off playback.
- CFNetwork linked explicitly for artwork downloads.
- Track-list serialization protected by the queue lock; protobuf encoding records are local to each call.
- Playback-state updates and serialization protected by a frame mutex.
- Latest verified app executable: `ipad-player-741433a52b26`.

### Current limitations

Initial account linking and song/queue selection still require Spotify on another device. The iPad can control an existing queue, but on-iPad login, browsing, search and independent track selection are not implemented.

Progress is estimated and read-only. Automatic reconnection, credential persistence, long-duration reliability and battery consumption still need work.

### Next milestones

1. Commit this working source checkpoint.
2. Validate and implement on-iPad authentication.
3. Securely persist reusable credentials.
4. Add playlist browsing and track selection using the existing playback engine.
5. Add search, connection recovery and clearer error handling.
6. Consolidate the build fixes and prepare an installable package.

### Before distribution

- Pin dependency versions and document SDK/toolchain prerequisites.
- Verify a clean build includes every applied fix.
- Include required dependency licenses and notices.
- Package installation, updates and uninstallation.
- Protect stored credentials and remove sensitive authentication data from logs.
- Test queue boundaries, reconnects, audio interruptions and repeated app launches.
- Run extended screen-off playback and battery tests.

**Status:** experimental native player with verified local controls; fully independent on-iPad setup and browsing remain the next phase.
## Checkpoint — 2026-10-07

Source is now under version control: root repository on `main`, `native-player/cspot` on branch `ipad-armv7` (commit 3405325) with its `bell` submodule on a local `ipad-armv7` branch. Build output, the venv, `deps/` and the unrelated Linux/browser research trees are ignored.

### Installed on the iPad

Catalog v2 (`ipad2-catalog-v2`), executable `ipad-player-a80d3a7c76f9`. A rebuild from the checkpointed source reproduces that exact hash.

- Verified: Connect-origin playback, local pause/resume/track change, screen-off audio, saved credentials and login5 tokens after restart.
- Not verified: any successful catalog search. Every search with the CSpot login5 token returned HTTP 429, including two requests 50 minutes apart. Local track selection after a cold start is therefore still untested.

### Packaging fix

`app/build-app.sh` now starts from an empty staging bundle and `auth/build-login-app.sh` removes the plain-signed executable after producing the Keychain-signed one, so the bundle contains exactly one `ipad-player-*` executable (the previous bundle had eighteen). `auth/install-app.sh` uploads to a staging directory on the device and swaps it in, keeping the old bundle as `iPad2MediaPlayer.app.previous` for rollback. Keychain data is unaffected.

### Next experiment

`token-test/search-probe.py` authorizes with the user's own developer app (PKCE, phone QR, callback pasted visibly on the Mac) and makes one track search. It never contacts the iPad. Its outcome decides whether catalog search moves to a separate own-app OAuth token (handoff steps 3–5) or whether the problem is on the account/app side.

```sh
source native-player/build-venv/bin/activate
python3 native-player/ios/token-test/search-probe.py
```

### Verified on device — 2026-10-07 18:35 (executable `ipad-player-5e03a24d2cdf`)

First complete independent flow: cold start with saved Keychain credentials, search on the iPad, local track selection, audible playback. No phone or Mac involved. Log excerpt (no secrets):

```text
CATALOG: backend=context-resolve
PLAYBACK AUTH: token accepted
CATALOG: sending search request backend=context-resolve
CATALOG: spclient host=gue1-spclient.spotify.com:443
CATALOG: HTTP=200
CATALOG: context tracks=10 of 20
CATALOG: tracks=10
Load frame 1!  ->  Track name: A Morte do Vaqueiro  ->  AUDIO: queue running=1 status=0
```

Search uses the spclient context-resolve endpoint with the session's own login5 token (see `native-player/ios/catalog/SEARCH-ALTERNATIVES.md`). The public Web API path and the separate own-app OAuth plan are no longer required for search. `IPAD2-PLAYER-HANDOFF.md` predates this and is kept for history only.

Remaining acceptance tests: pause/resume and track change on a locally selected track, screen-off playback with a locally selected track, close/reopen then search again (cache hit expected), token expiry after one hour, and transient network failure. Known limits: tracks only (no album/artist/playlist browsing), ten results, one metadata request per result.

## Phoenix Player — 2026-10-07 evening

The app is now a Spotify-style player with its own browsing UI. Everything below was verified on the iPad through screenshots and logs taken over SSH, except where marked.

### What it does

- **Home**: greeting with your first name, Recently played shelf (Liked Songs, playlists, albums, artists), Your playlists shelf, account button.
- **Search**: live search as you type; Songs, Artists and Albums sections. Tapping a song plays the result list from that song.
- **Your Library**: Liked Songs, your playlists, recently played albums, artists and playlists.
- **Album, playlist and Liked Songs pages**: header with art, Play and Shuffle; track list with the playing track in green; tapping a track plays the list from there (previous/next move through it).
- **Artist page**: portrait, Popular tracks, Albums and Singles shelves, biography.
- **Now Playing**: full-screen art, scrubber with seek, shuffle, previous/play/next; mini player docked above the tabs on every screen.
- **Lock screen and Control Center** show the track and respond to play/pause/next/previous (not yet tested on device).
- **Welcome screen** opens by itself when no account is saved: scan a QR with the phone (Spotify's device-authorization flow with the desktop client id, no Mac relay) or pick "Phoenix Player" in the phone's Spotify device list; both work live. **Account screen** (profile photo on Home): name, photo, Sign out (returns to the welcome screen in-app; the engine disconnects and restarts), and a "Visible on this network" switch that starts or stops the Bonjour advertisement and pairing endpoint immediately. While signed in and visible, a pairing from another phone switches the account. Verified end to end on 2026-10-08: phone approval, token exchange, Keychain save, and after a restart login5 accepted the new credentials and an album played. One transient AP connection failure was seen; the screen offers Retry login, which reuses the approved token without a new scan.

### How it works

- `native-player/ios/Catalog.cpp` builds all browsing data from Spotify's internal spclient endpoints with the session's own token: `context-resolve` for search/album/playlist/collection/artist contexts, `metadata/4/{track,album,artist}` JSON for names and covers, `recently-played`, `user-profile-view`. Track metadata is cached on disk under `Documents/phoenix-cache/tracks`.
- `SpclientClient.cpp` keeps one TLS connection per instance and reuses it, which makes hydrating a 50-track playlist take seconds on the iPad 2 instead of a minute. Two connections work in parallel. Partial results are published while loading.
- `PlayerBridge` exposes `ipad_catalog_request`/`ipad_catalog_poll` (UI polls JSON), `ipad_player_play_tracks` (multi-track queue with optional shuffle), `ipad_player_seek`. `SpircHandler::loadTracks` loads a whole list as the Spirc queue.
- `app/ui/` holds the Objective-C screens (compiled one object each by `application.cmake`). `PhoenixTheme` draws all icons at runtime; `ImageCache` caches artwork in memory and on disk and composes 2×2 mosaics for `spotify:mosaic:` covers. Image ids with the WebP-only variant code are rewritten to the JPEG variant because iOS 9 cannot decode WebP.
- `auth/DeviceAuth.cpp` implements RFC 8628 against `accounts.spotify.com` with the desktop client id, then reuses `OAuthLogin.cpp` to turn the token into reusable AP credentials.

### Developer tools on the device

- `uiopen phoenix://` launches the app; `phoenix://screenshot` writes `Documents/phoenix-screen.png`; `phoenix://search?q=...`, `phoenix://open?uri=spotify:album:...;name=...`, `phoenix://play?uri=...`, `phoenix://nowplaying`, `phoenix://setup`, `phoenix://tab?n=2`, `phoenix://scroll?y=800`, `phoenix://back`. Use `;` between query parameters when sending through `su -c`.
- Dropping `Documents/phoenix-probe.txt` (one URL per line, optional `| Header: value`) makes the engine fetch each URL with the session token at startup and save the bodies as `phoenix-probe-N.out`.
- The iPad shell lacks `tail`, `awk`, `wc` and `ps aux`; fetch logs with `cat` and filter on the Mac.

### Added 2026-10-08

- **Reconnect**: the session reconnects by itself on network loss (cspot's MercurySession); startup retries the access point with backoff for about two minutes; the app restarts the engine with growing delays after any failure while an account exists; Home and Now Playing show "Reconnecting…".
- **Queue and repeat**: queue screen from Now Playing, long-press a track row for Play next / Go to album / Go to artist, repeat off/all/one (implemented in `TrackQueue` so the preloaded next track is correct).
- **Home**: "Made for you" artist radios and "New releases for you", derived from recently played artists.
- **Batched metadata**: `extended-metadata/v0/extended-metadata` (protobuf, kind TRACK_V4 = 10, response `extended_metadata=2 → extension_data=3 → {entity_uri=2, Any=3}`), 50 tracks per request. Liked Songs (439) loads in about 2.5 s with a cold cache.
- **Kill switches**: `Documents/phoenix-catalog-flags.json` (`{"search": false}`) disables a request kind; three consecutive failures pause a kind for five minutes; screens show "Browsing is unavailable right now. Your phone can still pick Phoenix Player."
- **Search**: browse grid of genre tiles, recent searches, filter pills (All/Songs/Artists/Albums), Cancel returns to browse.
- Dev actions: `phoenix://repeat?mode=1`, `phoenix://enqueue?uri=...`, `phoenix://drop` (simulates connection loss), `phoenix://visible?on=0`, `phoenix://signout`.
- **Visualizations** (top-right button on Now Playing): all Windows Media Player 9 built-ins, taken from the WMP Visualization Wiki's "Versions available in" fields: Alchemy (Random), Ambience (Random + 13), Bars and Waves (Bars, Ocean Mist, Fire Storm, Scope), Battery (Randomization + 25 named presets), Particle (Particle, Rotating Particle), Plenoptic (Random + 6), Spikes (Spikes, Amoeba). Musical Colors was dropped because WMP 9 did not ship it. "Shuffle all" (first family in the picker, with Every 15 seconds / Every 30 seconds / Every minute) jumps to a random preset of a random family at that interval and the corner label names the current one. Touching the screen closes the visualization; the last choice is remembered. The idle timer is disabled only while a visualization runs, so auto-lock works normally on every other screen.
  - `app/ui/VisualizerView.m` is one video-feedback engine, as Battery's registry layout describes it: each tick the previous frame is redrawn through a "shift" (zoom, swirl, kaleidoscope, starburst, tunnel, tile, twirl, scroll, shimmer, thingus, rotate, stretch) with a fade, then one or two "elements" (waveform, radar, dot plane, circle wave, edge gradient, scribble, edge trace, spectrum edge, galaxy, circles, bars, lines, amoeba, spikes, fountain, smoke circles, smoke lines, mirrored wave) are drawn on top. Presets are data (`PresetSpec`); Random presets re-roll every 25 s. Rendering is a half-resolution `CGBitmapContext` shown through `layer.contents` (the GPU scales it) at 30 fps for analyzers and 20 fps for feedback effects, which the iPad 2 handles without a CPU notice.
  - Audio comes from `ios/AudioTap.cpp`: the audio-queue sink writes PCM into a ring buffer and the view reads 48 log-spaced bands (vDSP FFT) plus a 128-sample waveform and a level.
  - `app/ui/VisualizerMenu.m` is the picker: one panel with families on the left and presets on the right, one tap selects and closes.
  - Pitfall fixed on 2026-10-08: a private `int frame` property in the view shadowed UIView's `frame` setter, so the view never resized and drew in the top-left quarter. Never name a UIView property `frame`.
  - Research notes with per-preset descriptions and a projectM/MilkDrop feasibility call (not viable on the iPad 2's GPU) are in `docs/VISUALIZATION-RESEARCH.md`. The wiki's screenshots sit behind Cloudflare and could not be fetched, so looks were tuned from wikitext descriptions and YouTube thumbnails.
  - Dev actions: `phoenix://viz?family=Battery%26preset=brightsphere`, `phoenix://vizmenu`. When sending through `ssh`, use `%26` between parameters: the remote shell splits on `&` and `;`.

### Known gaps

- No "add to playlist" or like/unlike yet (those need write endpoints).
- Your full playlist list comes from the `rootlist` endpoint, which only answers JSON when exactly one `Accept` header is sent (bell's HTTP client adds its own `*/*`, hence the earlier 500s). Radio playlists carry no cover and show a placeholder.
- Search for artists and albums is derived from the matching tracks, so obscure artists with no matching tracks will not appear. The `searchview` endpoint that would return them directly answers HTTP 400 now.
- Landscape layouts are implemented but were only checked in portrait.
