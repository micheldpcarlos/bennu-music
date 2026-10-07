# Distribution checklist

This checklist separates developer experiments from mandatory user setup.
No installable release exists yet. Mark a gate confirmed only after the listed
behavior is tested, and retain logs/device model/version with the result.

## Product requirements

- [ ] Search, choose tracks, browse/play playlists and control playback on the iPad.
- [ ] Sound comes from the iPad speakers/headphone output.
- [ ] Normal use works with the Mac powered off and all external Spotify controllers closed.
- [ ] Independent sign-in/session restoration works after process/device restart.
- [ ] Spotify Premium requirement and account setup are documented.

## Expected end-user prerequisites (provisional)

| Item | Status | Release evidence needed |
|---|---|---|
| Supported iPad model / iOS version | iPad2,4 on 9.3.5 tested for probes only | Full player test per model/version |
| Jailbreak/Cydia | Needed by current development route | Repeatable install and reboot tests |
| Wi-Fi and Spotify Premium | Required by tested host playback | Native authentication/streaming tests |
| Initial login authorization | Unresolved | Safe repeatable first-login and renewal flow |
| SSH | Development-only today | End-user .deb install must not require SSH |
| Mac/Xcode/Python/Docker | Development-only | Prebuilt package works without them |
| External Spotify app/controller | Temporary test tool today | Must not be required for ordinary playback |

## Packaging and operation gates

- [ ] Installable ARMv7 package (.deb if using Cydia), version/dependency metadata,
      service ownership, file permissions and clean upgrade/removal behavior.
- [ ] App icon or local Safari launch entry; interface works with iOS 9 JavaScript/CSS.
- [ ] One player process; bounded buffering; clear startup/auth/audio errors.
- [ ] Audio works with headphones, screen lock, interruptions and route changes.
- [ ] Reboot startup after the supported jailbreak is active; crash restart/backoff.
- [ ] Wi-Fi drop/rejoin, expired authentication, pause/resume/seek/next-track tests.
- [ ] Long playback test on the 512-MB device; record memory/CPU/power/heat behavior.
- [ ] Document recovery and removal without modifying iOS system audio libraries.
- [ ] Validate iPad2,1/2/3 separately before saying "most iPad 2 models supported".

## Credentials, interface and release source

- [ ] Credentials kept out of logs, URLs, screenshots and release archives; restrict
      saved session files and provide logout/delete behavior.
- [ ] No Spotify client secret embedded in a distributable UI/binary; choose and
      validate the appropriate authorization flow for native engine and Web API.
- [ ] Define local UI/control access, bind scope and request protection separately
      from any LAN-visible Spotify discovery/auth endpoint.
- [ ] Pin CSpot, Bell, all submodules, backports, TLS and build-tool versions; publish
      a source manifest, reproducible build instructions and checksums.
- [ ] Preserve CSpot GPL-3.0-or-later license and provide corresponding source and
      build/install scripts; audit licenses for Bell, codecs and all dependencies.
- [ ] Review applicable Spotify developer requirements for the chosen integration
      and distribution; do not infer permission from a successful experiment.
- [ ] Never redistribute Apple's SDK or the normalized SDK overlay. Developers
      obtain their own SDK; users receive only the finished package and sources.
- [ ] Publish known limitations and a hardware test matrix with every release.

## Confirmed so far

Mac CSpot playback, ARMv7 C++ baseline, basic backports and native iPad tone audio.
These are feasibility milestones. They do not fulfill the product/release gates.
