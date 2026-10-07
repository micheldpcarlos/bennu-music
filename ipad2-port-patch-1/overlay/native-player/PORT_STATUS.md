# iPad2MediaPlayer progress checkpoint

Updated 2026-10-06. Objective: Spotify search, playlists and playback on an iPad 2,
with sound emitted by the iPad and no Mac/other player running during normal use.

## Confirmed by device/host tests supplied by Michel

| Milestone | Evidence | Scope |
|---|---|---|
| Identified development device | iPad2,4 / K93aAP, iOS 9.3.5 (13G36) | Other models untested |
| Cydia/jailbreak and root SSH | Successful remote command execution | Distribution setup/reboot behavior still needs documenting |
| Native ARMv7 executable | hello-arm prints on iPad | `-marm` required in observed tests |
| Native audio | Quiet 440-Hz tone heard through iPad | AudioToolbox/CoreFoundation, not Linux |
| Native C++ baseline | `C++ runtime working; thread result=7` | LLVM 3.8.1 headers, iOS libc++ runtime |
| Backport basic operations | variant/optional/string_view probe ran; hash=777416557 | Simple operations, not entire player |
| CSpot host playback | Mac authenticated, fetched audio keys/CDN URLs; user heard sustained playback; Ctrl+C stopped it | Connect controller used |

## Current source baseline

- CSpot checkout: `1b07a9c00ba6d5e878e5b33dcbf89bff493cde26`.
- Bell submodule: `e83737367a08b5a5a1f652a7ecb97a0d926929dd` (recorded earlier).
- Working Mac branch now `ipad-armv7`; supplied archive includes uncommitted fixes.
- Host: Apple Silicon macOS, Xcode 27 / clang 21. Development folder:
  `~/Projects/Personal/ipad2MediaPlayer`.
- Python venv: `native-player/build-venv`.
- Retained fixes: disabled codec source filtering; nanopb MakeClass replacement;
  hash callback capture by value; removal of unconditional PortAudio error text.

## Prepared by this patch, with host-only validation

- Shared project namespace for backported variant/optional/string_view and byte/endian.
- C++14-compatible single-mutex locking and atomic initialization.
- Iterator-based JSON parsing, mutable C++14 string access, portable htons include.
- Virtual audio effect destructor and unsigned 16-bit byte-swap correction.
- Isolated SDK stub overlay normalizer; no changes to the original SDK.
- ARMv7 iOS 9 CMake toolchain and static, separately built Mbed TLS dependency.
- Experimental native AudioQueue sink and CLI target.
- Expanded probe passes locally in C++14/backport and C++20/standard modes.
- Ten DSP/container sources pass host C++14 syntax checking.

## Immediate continuation

1. Apply the bundle using its hash-checking installer; read `ios/README.md`.
2. Build and run the expanded compatibility probe on the iPad.
3. Build the full ARMv7 player on the Mac; retain configure/build logs.
4. Test Connect-authenticated Spotify audio on iPad, including a full track and next track.
5. Recheck host Mac CLI after shared source changes.
6. Implement and test independent authentication/session persistence and local playback control.
7. Build an iOS-9-compatible Safari interface for search/playlists/now playing.
8. Add process lifecycle, packaging and release gates from DISTRIBUTION.md.

## Unresolved; do not claim as supported

- Full ARMv7 CSpot/Bell/TLS build and native Spotify audio on iPad.
- AudioQueue callback pacing, buffering, interruptions and long sessions.
- Exception unwinding with backports in the expanded iPad probe.
- Credentials persistence without an external Spotify player; existing CLI credential
  loading does not prove a complete first-login/cache workflow.
- Independent local queue selection, search and playlist browsing.
- Web API availability/permissions and login compatibility in iOS 9 Safari.
- Background/locked-screen behavior, reboot startup, Wi-Fi recovery, power usage.
- iPad2,1 / iPad2,2 / iPad2,3 support.
- Installable .deb, uninstallation, licensing/source release and distribution channel.

## Earlier route

Linux/Cascadia is paused. Its upstream target is iPad mini 1 (`iPad2,5`/p105ap),
not the tested iPad2,4. Kernel checkout exists on a case-sensitive sparsebundle.
Do not flash mini firmware or treat its DTB/boot chain as correct for this iPad.
Current native route reuses Apple's working iOS device drivers and audio.
