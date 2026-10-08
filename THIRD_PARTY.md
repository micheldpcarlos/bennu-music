# Third-party software

Bennu Music is GPL-3.0-or-later (see `LICENSE`). It bundles the following components,
vendored under `native-player/` with their license files in place. Provenance (upstream
repositories and pinned commits) is recorded in `native-player/upstream/VENDOR.md`.

| Component | Path | License | Role |
|---|---|---|---|
| cspot | `native-player/cspot` | GPL-3.0-or-later | Spotify Connect protocol engine (heavily modified for iOS 9, see `upstream/cspot-port.patch`) |
| bell | `native-player/cspot/cspot/bell` | No license file upstream; distributed inside cspot by the same authors and treated under cspot's GPL-3.0 terms | Networking, audio codecs, HTTP, mDNS |
| Mbed TLS 3.6.7 | `native-player/deps/mbedtls-3.6.7` | Apache-2.0 | TLS and crypto |
| nanopb | `bell/external/nanopb` | zlib | Protocol buffers |
| nlohmann/json | `bell/external/nlohmann_json` | MIT | JSON |
| cJSON | `bell/external/cJSON` | MIT | JSON (used by cspot) |
| Tremor | `bell/external/tremor` | BSD-3-Clause | Vorbis decoding |
| libhelix-mp3 | `bell/external/libhelix-mp3` | RPSL / RCSL (RealNetworks) | MP3 decoding, compiled in because bell's stream reader includes it |
| civetweb | `bell/external/civetweb` | MIT | Embedded HTTP server for Spotify Connect pairing |
| mdnssvc | `bell/external/mdnssvc` | MIT | mDNS advertisement |
| fmt (headers only) | `bell/external/fmt/include` | MIT | Included by a bell header; formatting itself is disabled |
| optional-lite, string-view-lite | `native-player/compat/vendor` | BSL-1.0 | C++17 backports for the iOS 9 libc++ |
| mpark/variant | `native-player/compat/vendor/variant` | BSL-1.0 | C++17 backport |
| picohttpparser | inlined in `native-player/ios/SpclientClient.cpp` | MIT / Perl Artistic | HTTP/1.1 response parsing |

Not included in the repository and required to build: Apple's iOS 9.3 SDK (from Xcode 7.3,
subject to Apple's SDK license) and the LLVM 3.8.1 libc++ headers (Apache-2.0 with LLVM
exception / UIUC). See the README's Toolchain section.

Spotify is a trademark of Spotify AB. This project is not affiliated with or endorsed by
Spotify. It talks to Spotify's services the way the official clients do and needs a Spotify
Premium account.
