# ARMv7 port patch 1

Base: Michel's source snapshot supplied on 2026-10-06.

- Introduces CSpotCompat.h without extending namespace std; selects tested
  backports only for CSPOT_LEGACY_IOS and otherwise standard C++20 types.
- Replaces single-mutex scoped_lock declarations with explicit lock_guard types.
- Uses C++14-compatible atomic initialization and writable string access.
- Uses JSON iterator ranges instead of relying on a modern string_view adapter.
- Removes Intel-specific endian include in Apple mDNS implementation.
- Fixes unsigned 16-bit BinaryStream swapping and AudioEffect base destruction.
- Lets parent CMake select C++14 and supplies static target-based Mbed TLS.
- Adds an isolated SDK normalizer, expanded probe, ARMv7 toolchain and experimental
  AudioQueue sink; preserves the host PortAudio path.

Not implemented: independent login/queue control, Safari frontend, background
lifecycle or end-user package. Complete iOS build/device test still pending.
