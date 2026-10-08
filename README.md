# Bennu Music

A native Spotify player for the jailbroken iPad 2 (iOS 9.3.5, ARMv7). It is both a
**Spotify Connect receiver** (pick "Bennu Music" in the Spotify app on your phone) and a
**standalone player** with a Spotify-style interface: sign in once by scanning a QR code,
then browse, search and play on the iPad itself, with the screen off, no phone or computer
in the loop.

It is built on [cspot](https://github.com/feelfreelinux/cspot), ported to the 2016-era
toolchain that iOS 9 requires, with the browsing layer, authentication flow and UIKit app
written for this project. **A Spotify Premium account is required** (Spotify Connect and
audio streaming are Premium features).

<p align="center"><img src="native-player/ios/app/icon/AppIcon-152.png" width="76" alt="Bennu Music icon"></p>

## What it does

- **Home**: greeting, Recently played, Your playlists, Made for you (artist radios), New releases.
- **Search**: browse grid of genres, live search with Songs / Artists / Albums filters, recent searches.
- **Your Library**: Liked Songs, your playlists, recently played albums and artists.
- **Album, playlist, artist and Liked Songs pages** with Play and Shuffle; long-press a track for Play next, Go to album, Go to artist.
- **Now Playing**: artwork, scrubber with seek, shuffle, repeat (off / all / one), queue screen, lock-screen and Control Center controls.
- **Visualizations**: all Windows Media Player 9 built-ins (Alchemy, Ambience, Bars and Waves, Battery, Particle, Plenoptic, Spikes), reimplemented as a video-feedback engine on CoreGraphics, plus a Shuffle-all mode.
- **Spotify Connect volume** is the iPad's system volume: the phone's slider moves it, the hardware buttons update the phone, and the level is remembered across restarts.
- **Account**: profile photo and name, in-app sign-out, a switch for visibility on the local network (Spotify Connect pairing).
- **Resilience**: automatic reconnect after network loss, engine restart with backoff, per-feature circuit breakers for Spotify's internal endpoints.

## How it works

```
native-player/
├── cspot/                 Spotify Connect engine (vendored cspot + bell, see upstream/VENDOR.md)
├── deps/mbedtls-3.6.7/    TLS, built statically for ARMv7
├── compat/                C++17 backports for the iOS 9 libc++
├── ios/
│   ├── Catalog.cpp        Browsing data from Spotify's internal spclient endpoints
│   ├── SpclientClient.cpp Keep-alive HTTPS client used by the catalog
│   ├── PlayerBridge.cpp   C API between the engine thread and the UI
│   ├── IOSAudioQueueSink.cpp / AudioTap.cpp   AudioQueue output and the FFT tap for visualizations
│   ├── auth/              Device-authorization login, token exchange, Keychain storage
│   └── app/               The UIKit app (Objective-C, one screen per file under ui/)
└── toolchain/             (not in git) iOS 9.3 SDK and LLVM 3.8.1 libc++ headers
scripts/build.sh           Build and sign the bundle
scripts/install.sh         Install on the iPad over SSH
docs/                      Research notes and project history
```

**Engine.** cspot's CLI target runs on a background thread and handles the Spotify Connect
protocol (Mercury, Spirc, audio key, CDN fetch, Vorbis decoding). It is modified to compile
with C++14 and the old libc++ (`upstream/cspot-port.patch`), to reconnect on its own, to
support multi-track loads, seeking, queueing and repeat, and to expose everything through
`PlayerBridge`.

**Login.** The welcome screen runs Spotify's device-authorization flow (RFC 8628) and shows
the verification URL as a QR code. Approving it on a phone yields a token that the engine
turns into reusable credentials stored in the Keychain. Alternatively the iPad advertises
itself over mDNS and the Spotify app on the same network can pair with it. Only Spotify's own
client ids are allowed to use this flow, so the project uses the desktop client id; your own
developer app would be rejected. See `docs/ux-approach-research.md` for the research behind
this choice.

**Browsing.** Spotify's public Web API rate-limits this kind of client, so the catalog uses
the same internal endpoints the official clients use, authenticated with the session's own
token: `context-resolve` (search, albums, playlists, collections, radios), `metadata/4`
and `extended-metadata` (track details, batched 50 at a time), `recently-played`,
`playlist/v2` (your playlist list and covers), `user-profile-view`. Results are cached on
disk. Covers are rewritten to JPEG variants because iOS 9 cannot decode WebP, and
mosaic covers are composed on the device. See `docs/search-alternatives.md`.

**UI.** Frame-based UIKit (no Auto Layout, no storyboards), icons drawn at runtime,
images decoded off the main thread. The visualizer renders a half-resolution bitmap that
the GPU scales (`docs/visualization-research.md` documents the presets).

## Requirements

- An iPad 2 (or another ARMv7 device) on iOS 9.3.5, jailbroken, with OpenSSH installed and
  your SSH public key authorized for `root`.
- A Spotify Premium account.
- A Mac with Xcode command-line tools, CMake, Python 3 and [ldid](https://github.com/ProcursusTeam/ldid)
  (`brew install cmake ldid`).
- The iOS 9.3 SDK and LLVM 3.8.1 libc++ headers (see Toolchain). Current Xcode cannot target
  iOS 9 on its own.

## Toolchain

Two inputs are not in the repository because of their licenses and size. Put them here:

| Path | What | Where to get it |
|---|---|---|
| `native-player/toolchain/iPhoneOS9.3.sdk` | Apple's iOS 9.3 SDK | Inside Xcode 7.3 (`Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS9.3.sdk`) |
| `native-player/toolchain/libcxx-3.8.1.src` | LLVM 3.8.1 libc++ source (only `include/` is used) | https://releases.llvm.org/3.8.1/libcxx-3.8.1.src.tar.xz |

The build script creates a normalized overlay of the SDK under `native-player/ios/build/`
(text stubs rewritten so the modern linker accepts the ARMv7 exports); the original SDK is
not modified. `IPAD_ORIGINAL_SDK` and `IPAD_CXX_HEADERS` override the paths.

## Build

```sh
python3 -m venv native-player/build-venv
source native-player/build-venv/bin/activate
pip install -r native-player/ios/requirements-build.txt protobuf grpcio-tools
scripts/build.sh
```

The result is `native-player/ios/build/BennuMusic.app`, a bundle with one
executable named after its hash, signed with `ldid` and a private Keychain access group.

## Install

```sh
IPAD=root@<ipad address> scripts/install.sh
```

The script uploads the bundle next to the installed one, stops the app, swaps the
directories, refreshes the icon cache and verifies the result. The previous bundle is kept
as `BennuMusic.app.previous` for rollback. Open "Bennu Music" on the iPad: the
welcome screen explains both sign-in methods.

## Developer tools

The app registers the `bennu://` URL scheme so it can be driven over SSH with `uiopen`:

| URL | Effect |
|---|---|
| `bennu://screenshot` | Writes `Documents/bennu-screen.png` |
| `bennu://tab?n=0..2`, `bennu://back`, `bennu://scroll?y=800` | Navigation |
| `bennu://search?q=...`, `bennu://open?uri=spotify:album:...`, `bennu://play?uri=...` | Browsing and playback |
| `bennu://nowplaying`, `bennu://seek?ms=266000`, `bennu://volume?v=32768`, `bennu://repeat?mode=1`, `bennu://enqueue?uri=...` | Player |
| `bennu://viz?family=Battery%26preset=brightsphere`, `bennu://vizmenu` | Visualizer |
| `bennu://setup`, `bennu://signout`, `bennu://visible?on=0`, `bennu://drop` | Account, visibility, simulated connection loss |

Separate query parameters with `%26` when the URL goes through `ssh`; the iPad's shell
splits on `&` and `;`. The engine's log is `Documents/cspot-app.log`. Dropping a
`Documents/bennu-probe.txt` (one URL per line) makes the engine fetch each URL with the
session token at startup, which is how the catalog endpoints were explored.
`Documents/bennu-catalog-flags.json` (for example `{"search": false}`) disables a request
kind without a rebuild.

## Known limits

- No write operations yet (like, add to playlist, follow).
- Artist and album search is derived from matching tracks; artists with no matching tracks
  do not appear. Spotify's dedicated search endpoint rejects this client.
- Spotify changes its internal endpoints a few times a year. The catalog degrades
  per-feature (a screen says browsing is unavailable; Spotify Connect keeps working).
- Landscape layouts were only spot-checked.
- The visualizer presets follow the WMP wiki's descriptions; the original gallery images
  were not available, so they are interpretations.

## Documents

- `docs/ux-approach-research.md`: why device authorization with Spotify's client id, and the alternatives.
- `docs/search-alternatives.md`: how every catalog endpoint was found and what failed.
- `docs/visualization-research.md`: WMP 9 preset catalog and engine notes.
- `docs/history/`: dated checkpoints from the port, including the earlier Linux-boot route.
- `native-player/upstream/VENDOR.md`: provenance of vendored code and the port patches.
- `THIRD_PARTY.md`, `CONTRIBUTING.md`.

## License

GPL-3.0-or-later. See `LICENSE` and `THIRD_PARTY.md`. Not affiliated with Spotify.
