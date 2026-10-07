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
~/Projects/Personal/ipad2MediaPlayer
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