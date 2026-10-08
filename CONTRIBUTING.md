# Contributing

Thanks for looking at Phoenix Player. The project targets a single, very old device, so most of
the rules below exist to keep builds working on it.

## Ground rules

- **Never commit credentials.** No Spotify tokens, device-authorization codes, stored
  credential blobs, Keychain dumps or log excerpts containing them. The `.gitignore` blocks
  the usual file names, but check diffs anyway.
- **Playback credentials and catalog tokens stay separate.** Browsing uses the session's own
  token obtained from the engine; never persist a browsing token through `AuthStore`.
- **Audible playback after a cold start is the acceptance test.** A login that is accepted by
  the access point is not enough; the engine must play audio after the app is killed and
  reopened.

## Toolchain constraints

- iOS 9.3.5 on ARMv7 with the libc++ of 2016. C++14 only: no `std::optional`,
  `std::string_view` or `std::variant`; use the backports in `native-player/compat/vendor`
  through `CSpotCompat.h`.
- Objective-C UI is frame-based UIKit (no Auto Layout constraints, no storyboards, no asset
  catalogs); icons are drawn at runtime in `PhoenixTheme`.
- Each `.m` file under `native-player/ios/app/ui/` compiles to its own object through the glob
  in `application.cmake`; new screens need no CMake change. Array-typed properties are not
  available in that Objective-C dialect; use ivars.
- Never declare a UIView property named `frame` (it shadows UIView's setter).
- `-marm` is required; Thumb code crashed on the device.

## Workflow

1. `scripts/build.sh` builds and signs the bundle.
2. `IPAD=root@<ip> scripts/install.sh` installs it over SSH with a staged swap and keeps the
   previous bundle for rollback.
3. Drive the app remotely with the `phoenix://` URL scheme (see README, "Developer tools") and
   pull `Documents/phoenix-screen.png` for screenshots. Separate query parameters with `%26`
   when the URL passes through `ssh`.
4. The iPad shell lacks `tail`, `awk`, `wc` and `ps aux`; `cat` files and filter on the Mac.
5. The iPad drops Wi-Fi when locked unless audio is playing; keep something playing during
   long sessions.

## Commits

Describe the user-visible change and, when it is not obvious, why the previous behaviour was
wrong. Keep vendored trees untouched except through the port patches in
`native-player/upstream/`; if you must change cspot or bell, regenerate the patch there.
