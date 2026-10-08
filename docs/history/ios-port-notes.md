# Experimental iPad 2 native player port

This is a development patch, not an installable release. It targets ARMv7 iOS 9
using the existing jailbroken iPad's Apple audio and networking libraries.
No Linux installation or Chromium port is involved in this route.

## First step after applying the bundle

Run on the Mac from `<repo>`:

```sh
source native-player/build-venv/bin/activate
python -m pip install -r native-player/ios/requirements-build.txt
bash native-player/ios/build-ipad.sh probe
```

The script creates a private, device-only SDK overlay under
`native-player/ios/build/iPhoneOS9.3.sdk`. It does not modify your old SDK or
previous probe stubs. The overlay symlinks headers to the original SDK and
rewrites only text stubs, retaining ARMv7 export sections. Keep the original SDK
at its existing path. An incomplete overlay is deliberately rejected on retry;
remove only that generated overlay directory before retrying normalization.

This probe tests the actual shared compatibility header used by the player,
including JSON parsing, exception handling, threads and big-endian round trips.
It expands on the earlier successful runtime and backport probes.

Upload and run the signed probe (replace IPAD_IP with your iPad's current address):

```sh
IPAD_IP=<ipad-ip>
scp -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/ipad-compatibility \
  "root@$IPAD_IP:/tmp/ipad-compatibility" &&
ssh -o HostKeyAlgorithms=+ssh-rsa "root@$IPAD_IP" \
  'chmod 755 /tmp/ipad-compatibility && /tmp/ipad-compatibility'
```

Expected: `Compatibility passed: variants, exceptions, optional, JSON, threads, byte order`.
This expanded probe has not yet run on the iPad. Its equivalent host tests passed.

## Build the experimental player after the expanded probe passes

```sh
bash native-player/ios/build-ipad.sh build
```

The script downloads a recursive Mbed TLS checkout pinned to `mbedtls-3.6.7` if
one is not supplied via `IPAD_MBEDTLS_SOURCE`. It builds static ARMv7 TLS libraries
inside the same cross-build. It never links the Mac's Homebrew ARM64 TLS or
PortAudio libraries into the iPad executable. Python/protoc execute on the Mac;
their generated C code compiles for ARMv7. Build logs are kept under `ios/build`.

The build reuses CSpot's tested CLI and Spotify Connect authentication flow with
a new AudioQueue sink. The sink has four bounded 8192-byte buffers and blocks
PCM producers until a buffer is returned. It accepts stereo 44.1-kHz signed
16-bit PCM. It uses the same legacy AudioSession API family as the successful
tone probe. This full sink and cross-build still require Mac/iPad verification.

Output: `native-player/ios/build/player/cspot-ipad`, signed with `ldid -S`.

```sh
scp -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/player/cspot-ipad "root@$IPAD_IP:/tmp/cspot-ipad" &&
ssh -o HostKeyAlgorithms=+ssh-rsa "root@$IPAD_IP" \
  'chmod 755 /tmp/cspot-ipad && /tmp/cspot-ipad -b 160'
```

At this stage a Spotify app is still used as a temporary controller for discovery,
authentication and playback validation. Independent login and playback controls
have NOT been implemented. The final product must play on the iPad with the Mac
and other playback controllers closed/off.

## Build prerequisites, not end-user prerequisites

- Existing Xcode command-line tools capable of ARMv7 compilation; tested host has
  Xcode 27, but the generated executable still needs iOS 9-compatible libraries.
- Existing `browser-port/legacy-sdks/iPhoneOS9.3.sdk`.
- Existing LLVM 3.8.1 libc++ headers at
  `browser-port/toolchains/libcxx-3.8.1.src/include`.
- Existing backports under `native-player/compat/vendor`.
- Project Python venv with setuptools >=77.0.1,<82, protobuf, grpcio-tools,
  and PyYAML >=6,<7. The old nanopb generator's MakeClass call is already patched
  in the submitted snapshot. Do not update the pinned Bell/nanopb submodules
  without carrying and revalidating that patch.
- CMake, Git and ldid; Mbed TLS source is obtained by the build script.

Override `IPAD_ORIGINAL_SDK`, `IPAD_CXX_HEADERS`, `IPAD_MBEDTLS_SOURCE`, or
`IPAD_BUILD_JOBS` when needed. Do not reuse the host `build-macos` directory for
iOS. `-marm` is intentional: the default Thumb probe crashed on the iPad.
No SDK binaries or headers are included in this patch bundle.

## Source layout and validation limits

`CSpotCompat.h` selects standard types normally and tested backports when
`CSPOT_LEGACY_IOS` is defined. It does not add names to namespace std. Existing
single-mutex scoped locks become explicit lock_guards. Byte and endian adapters
live in the project namespace. Backport versions must be captured in the release
source manifest (the submitted header hashes are recorded in this bundle).

Host tests passed with GCC 13: C++14/backports and C++20/standard types.
Ten DSP/container source syntax checks also passed in C++14/backport mode.
The AudioQueue implementation and complete iOS executable have NOT been compiled
or run in this environment, which has no macOS SDK or attached iPad.

CSpot is GPL-3.0-or-later; retain its license and release corresponding source
with distributions. Audit Bell and every bundled dependency before a release.
See `../PORT_STATUS.md` and `../DISTRIBUTION.md` for the handoff and release gates.
