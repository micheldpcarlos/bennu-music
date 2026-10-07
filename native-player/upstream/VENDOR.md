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

Licenses: cspot and bell are MIT; see their LICENSE files in place. The nonstd-lite libraries are
Boost Software License 1.0; mpark/variant is Boost Software License 1.0. New code in this
project is GPL-3.0-or-later as marked in file headers.

bell's own external submodules, unmodified:

- `native-player/cspot/cspot/bell/external/mdnssvc` — https://github.com/philippe44/mdnssvc (bell submodule, local changes: 0 files)
- `native-player/cspot/cspot/bell/external/nlohmann_json` — https://github.com/nlohmann/json (bell submodule, local changes: 0 files; docs/tests/tools excluded)
- `native-player/deps/mbedtls-3.6.7` — https://github.com/Mbed-TLS/mbedtls.git tag `mbedtls-3.6.7` (`068ff08`); local changes in `mbedtls-port.patch`
- `native-player/deps/mbedtls-3.6.7/framework` — https://github.com/Mbed-TLS/mbedtls-framework (mbedtls submodule, local changes: 0 files)
