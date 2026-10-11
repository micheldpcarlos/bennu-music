# Vendored upstream sources

These trees were git clones; on 2026-10-07 their nested repositories were dissolved and the
files committed directly to this repository, because the port modifies them heavily and will
not track upstream. The patches here are the full diff of the port against the upstream
commit at the time, for reference or for re-deriving the changes on a newer upstream.

| Tree | Upstream | Base commit | Patch |
|---|---|---|---|
| `native-player/cspot` | https://github.com/feelfreelinux/cspot | `1b07a9c00ba6d5e878e5b33dcbf89bff493cde26` | `cspot-port.patch` |
| `native-player/cspot/cspot/bell` | https://github.com/feelfreelinux/bell | `e83737367a08b5a5a1f652a7ecb97a0d926929dd` | `bell-port.patch` |
| `native-player/compat/vendor/optional-lite` | https://github.com/nonstd-lite/optional-lite | `99ad1fa` | unmodified |
| `native-player/compat/vendor/string-view-lite` | https://github.com/nonstd-lite/string-view-lite | `59b11b7` | unmodified |
| `native-player/compat/vendor/variant` | https://github.com/mpark/variant | `23cb94f` | unmodified |

Licenses: cspot is GPL-3.0-or-later (its LICENSE.md is in place). bell ships no license file; it is by the same authors and is distributed inside cspot, and this project treats it under cspot's GPL-3.0 terms. See THIRD_PARTY.md at the repository root for the full list. The nonstd-lite libraries are
Boost Software License 1.0; mpark/variant is Boost Software License 1.0. New code in this
project is GPL-3.0-or-later as marked in file headers.

bell's own external submodules, unmodified:

- `native-player/cspot/cspot/bell/external/mdnssvc` — https://github.com/philippe44/mdnssvc (bell submodule, local changes: 0 files)
- `native-player/cspot/cspot/bell/external/nlohmann_json` — https://github.com/nlohmann/json (bell submodule, local changes: 0 files; docs/tests/tools excluded)
- `native-player/deps/mbedtls-3.6.7` — https://github.com/Mbed-TLS/mbedtls.git tag `mbedtls-3.6.7` (`068ff08`), unmodified (an earlier patch installer had appended notes to its README; reverted)
- `native-player/deps/mbedtls-3.6.7/framework` — https://github.com/Mbed-TLS/mbedtls-framework (mbedtls submodule, local changes: 0 files)


Pruned on 2026-10-08 to keep the repository small: bell externals the iOS build does not use (opus, opencore-aacdec, alac, portaudio, mqtt, fmt's sources and docs), test suites, examples and documentation of nanopb, cJSON, tremor, nlohmann_json and the compat headers, the esp32 target, and Mbed TLS's test framework data, docs and programs. Restore from upstream at the pinned commits if ever needed.

Keep-alive change (2026-10-11): cspot answered each access-point Ping with an immediate Pong echoing the ping data; the server dropped about one session an hour. MercurySession now sends a 4-byte zero Pong 60 s after the Ping, as librespot does since PR #1359 (2024-10). Also changed in the vendored engine: PlaybackState publishes the track list and shuffle/repeat flags, TrackQueue implements shuffle with a restorable order, TrackPlayer/CDNAudioFile retry network failures instead of throwing through libvorbis.
