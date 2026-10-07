# iPad 2 Spotify player — agent handoff

Updated: 2026-10-07. User: Michel Carlos. Continue in English.

## Start here

You are continuing an existing, working experimental native Spotify receiver/player on a jailbroken iPad 2. The user wants to choose music directly on the iPad, play it there, and keep playing with the screen off. A phone may be used for authorization and optional remote control, but must not be required to initiate every playback session. A Mac must not run an external player for production use.

**Immediate objective:** test one Spotify catalog search using the user's own registered application's OAuth token. If that works, implement separate catalog OAuth storage/refresh and connect it to the existing iPad QR setup flow. Preserve the already working CSpot playback credentials. Also fix app packaging so obsolete hashed executables do not accumulate.

The previous assistant was about to prepare the separate OAuth search probe when the user requested this handoff instead. **That probe has not been implemented.** Do not assume a separate catalog OAuth provider exists.

You should have direct project/Mac access and, ideally, SSH access to the iPad. Inspect the actual working tree before making changes: it is more authoritative than this document. Previous work was delivered as source patch archives because the assistant could not execute Xcode or operate the device directly.

## Environment and paths

ssh ipad password: alpine

| Item | Value |
|---|---|
| Mac project | `/Users/michelcarlos/Projects/Personal/ipad2MediaPlayer` |
| CSpot checkout | `native-player/cspot` |
| CSpot branch created during port | `ipad-armv7` — verify current branch |
| Initial CSpot commit | `1b07a9c00ba6d5e878e5b33dcbf89bff493cde26` |
| Device | Jailbroken iPad 2, ARMv7, iOS 9.3.5 |
| iPad SSH | `root@192.168.13.24`, legacy RSA host-key option needed |
| Main installed app | `/Applications/iPad2MediaPlayer.app` |
| App bundle ID | `org.ipad2mediaplayer.receiver` |
| Keychain access group | `PHOENIXDEV.org.ipad2mediaplayer.receiver` |
| Build venv | `native-player/build-venv` |
| Main app build | `bash native-player/ios/auth/build-login-app.sh` |
| Output app | `native-player/ios/build/iPad2MediaPlayer.app` |
| App log | `/var/mobile/Documents/cspot-app.log` |
| Source legacy SDK | `browser-port/legacy-sdks/iPhoneOS9.3.sdk` |
| Generated SDK overlay | `native-player/ios/build/iPhoneOS9.3.sdk` |
| Legacy C++ headers | `browser-port/toolchains/libcxx-3.8.1.src/include` |
| TLS source | `native-player/deps/mbedtls-3.6.7` |
| User timezone | America/Sao_Paulo |

The app runs from its SpringBoard icon. Running a plain SSH process was insufficient for reliable screen-off audio. Preserve the UIKit wrapper, background audio declaration and audio-session fixes.

Python was 3.14 on the Mac. Build dependencies include CMake, protobuf tooling, PyYAML, Jinja2 and setuptools pinned below 82 because the old nanopb generator imports pkg_resources. Read the actual requirements files before reinstalling dependencies. CMake policy compatibility is supplied by build scripts. Do not replace legacy headers with current Xcode libc++ headers without an ABI plan.

SSH/scp patterns:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24
scp -O -o HostKeyAlgorithms=+ssh-rsa LOCAL_FILE root@192.168.13.24:REMOTE_PATH
```

Passwords are entered interactively. No password, token, reusable credential or callback authorization code is included in this document.

## Verified results versus pending work

### Verified on the iPad by the user

- ARMv7 executable links and runs with C++ exceptions, threads, JSON, variant/optional/string-view backports and byte-order support.
- AudioQueue plays actual Spotify audio after Spotify Connect pairing.
- The UIKit player displays Now Playing metadata and supports local pause/resume and track changes after the serialization fix.
- Screen-off and locking playback work with the later audio/session/buffer fixes. Keep this as a regression requirement.
- The QR authorization flow runs on the iPad. The phone authorizes Spotify; a console helper forwards the final callback to the iPad; the iPad exchanges it.
- Reusable account credentials are saved and loaded from Keychain.
- OAuth AP login and reusable AP login on a fresh connection were tested.
- A later one-time Connect pairing restored working playback-token acquisition.
- Following that pairing, later app restarts loaded saved credentials and obtained login5 tokens successfully.
- Catalog v2 is installed and issuing its new diagnostic messages.

### Not yet established

- Any successful catalog search: every catalog response in the supplied device logs is HTTP 429.
- A complete independent flow: reopen app, search, select a track locally, and hear it without selecting CSpot from the phone.
- Public Web API access using the user's own registered app's OAuth token.
- A complete working playback path for reusable credentials originally derived from the OAuth QR login. AP acceptance alone did not establish this.
- Catalog OAuth access/refresh tokens stored independently from playback credentials.
- Relay-based authorization without console callback transfer.
- Distribution readiness or App Store installation.

Avoid repeating the earlier mistake of calling the app fully persistent/standalone just because AP login and token acquisition succeeded. Actual track selection and audible playback after restart are the acceptance test.

## Latest evidence and interpretation

The app log is append-only across many launches. Old errors before a later `APP: launched` are historical; do not treat them as current failures.

Earlier sequence:

1. Around 15:06–15:09 in the raw log, login5 returned HTTP 200 with `login5_error=1` repeatedly, roughly every 30 seconds. This was the OAuth-origin credential path. The code/schema identifies error 1 as INVALID_CREDENTIALS.
2. Around 15:17, one-time Connect pairing saved new reusable credentials and a token was accepted. The user confirmed actual audio, local controls and screen-off playback.
3. Around 15:18, a restart loaded saved credentials and obtained a token successfully. This proves saved token acquisition, not local track initiation.
4. Before catalog v2, playback and catalog had separate token fetchers: two token requests about eleven seconds apart were explained by those separate caches.

Latest session, with catalog v2:

```text
AUTH: loaded reusable credentials from Keychain
AUTH: account login passed and credentials saved; ready for playback
[2026-10-07 16:22:42.973] ... PLAYBACK AUTH: requesting login5 token
[2026-10-07 16:22:43.215] ... PLAYBACK AUTH: token accepted
CATALOG: sending search request epoch_seconds=1791390166
CATALOG: HTTP=429 epoch_seconds=1791390166
CATALOG: HTTP=429 reason=UNKNOWN retry_seconds=46 source=server blocked=0
...
CATALOG: sending search request epoch_seconds=1791393210
CATALOG: HTTP=429 epoch_seconds=1791393210
CATALOG: HTTP=429 reason=UNKNOWN retry_seconds=2 source=server blocked=0
```

Those two search requests were **3,044 seconds / 50 minutes 44 seconds apart**. The second was well beyond the first server cooldown. There is no search flood or duplicate token acquisition in that latest excerpt. `reason=UNKNOWN` means no recognized structured reason was extracted; it does not identify the server-side cause. No `CATALOG: HTTP=200` or `CATALOG: tracks=...` was observed.

Do not assert that the built-in Spotify client identity caused the 429: that remains a hypothesis. The next independent OAuth test is intended to isolate authorization/client behavior. Repeated arbitrary waits and re-pairing have not resolved catalog access.

Selecting an already connected iPad from the iPhone normally sends playback commands; it is not a reliable method to replace catalog authorization. A full Connect re-pairing may replace reusable playback credentials but still obtains tokens through CSpot's same client identity.

## Authentication paths — preserve this distinction

### Existing playback path

- `LoginBlob` → Spotify AP authentication → canonical reusable credentials → Keychain.
- `AccessKeyFetcher` uses login5 with CSpot's built-in Spotify web-client ID `65b708073fc0480ea92a077233ca87bd`.
- These credentials and tokens currently support the proven Connect-origin playback path.

### Planned catalog path

Use the user's registered Spotify developer application:

```text
Client ID: 8686d6b87e484c50a6f9ab93bcc099e7
Registered redirect: http://127.0.0.1:8765/callback
```

The client ID is public. Use authorization code + PKCE; do not introduce a client secret into the iPad app. Existing QR setup has worked with this application. Fresh catalog OAuth access and refresh tokens should have separate Keychain records and lifecycle from the CSpot reusable account record.

**Important:** the current QR flow converts an OAuth token into reusable AP credentials and saves the account through the existing AuthStore. Reusing that path unchanged for catalog login could overwrite the working Connect-origin playback account. Implement catalog authorization as a distinct flow/storage operation. It must not call the playback credential save API just to authorize search.

The phone's final callback points at its own loopback interface and therefore fails to load. For the temporary flow, copy the complete final address and forward it through the Mac console. This is expected. The user had trouble with hidden-input prompts and missing `http://`; support clipboard input or visible paste, normalize the absent scheme, and validate state/redirect strictly. Never put callback codes in shell arguments, logs or the handoff.

## Code map

Paths below are relative to the Mac project root. Verify their exact current content.

| File | Role / relevant behavior |
|---|---|
| `native-player/cspot/targets/cli/main.cpp` | Engine startup, Keychain load/save, optional Connect pairing, shared account context, bridge callbacks, packet dispatch loop |
| `native-player/ios/app/AppMain.mm` | UIKit application and engine-thread lifecycle |
| `native-player/ios/app/NowPlaying.inc` | Now Playing UI and Music button |
| `native-player/ios/app/CatalogPicker.h`, `.m` | Search/list UI. Header has C linkage guard for Objective-C++ callers |
| `native-player/ios/CatalogSearch.h`, `.cpp` | Public search request, result normalization/cache and persistent retry policy |
| `native-player/ios/PlayerBridge.h`, `.cpp` | Thread-safe UI snapshots and queued commands; engine calls happen outside bridge lock |
| `native-player/cspot/cspot/include/AccessKeyFetcher.h` | Shared provider factory and synchronized token cache |
| `native-player/cspot/cspot/src/AccessKeyFetcher.cpp` | login5 requests, expiry, retries, credential-rejection stop |
| `native-player/cspot/cspot/src/TrackQueue.cpp` | Playback uses `AccessKeyFetcher::forContext(ctx)` |
| `native-player/cspot/cspot/src/SpircHandler.cpp` | `loadTrackFromURI` now implements local track loading through normal LOAD frame handling |
| `native-player/cspot/cspot/src/TrackReference.cpp` | URI/GID conversion and safe nanopb track-list serialization |
| `native-player/ios/IOSAudioQueueSink.cpp` | AudioQueue output, buffer lifecycle and diagnostics |
| `native-player/ios/app/AppAudioSession.inc` | App audio-session behavior; preserve screen-off fixes |
| `native-player/ios/auth/QRSetup.h`, `.m` | On-device PKCE/QR and callback handling |
| `native-player/ios/auth/OAuthLogin.h`, `.cpp` | Existing OAuth-to-reusable-AP helper; not a catalog OAuth store |
| `native-player/ios/auth/AuthStore.h`, `.m` | Existing reusable playback account Keychain load/save |
| `native-player/ios/auth/forward-callback.py` | Mac callback transfer helper |
| `native-player/ios/token-test/authorize-and-test.py` | Earlier Mac QR OAuth/AP probe; inspect local edits before reuse |
| `native-player/ios/app/application.cmake` | Explicit Objective-C/Objective-C++ compilation and framework linkage |
| `native-player/ios/app/build-app.sh` | Generated app packaging |
| `native-player/ios/auth/build-login-app.sh` | Keychain signing wrapper; use for app builds |
| `native-player/ios/auth/Entitlements.plist` | App identity and Keychain group |
| `native-player/ios/normalize-sdk.py` | Legacy SDK stub normalization and needed exports |
| `native-player/ios/catalog/README.md`, `V2-CHECKPOINT.md` | Catalog checkpoint/testing notes |

## Current catalog v2 behavior

- A registry returns one `AccessKeyFetcher` per live Context. Playback and catalog share its mutex-protected token cache.
- Token refresh now occurs shortly before expiry, rather than at half the lifetime.
- Explicit INVALID_CREDENTIALS stops further automatic token retries in that session. Transient failures back off up to five minutes.
- The current catalog still consumes that login5 token. **This is the authorization path to replace for catalog only.**
- Search endpoint: `GET https://api.spotify.com/v1/search?type=track&limit=10&q=...`.
- Successful results cache for ten minutes, with up to eight queries in memory. Reopening Music remembers the last query. UI polling reads only local state.
- A 429 reads the full numeric Retry-After up to 2,147,483,647 seconds. Oversized numeric values pause rather than guess a shorter wait.
- Catalog policy persists only deadline/blocked state in `/var/mobile/Documents/cspot-catalog-policy.json`. No token/query/account is stored there.
- Recognized QUOTA_EXCEEDED without a usable reset interval pauses searches pending investigation.
- Error reason logs are allowlisted, not raw response contents. Search logs include epoch seconds.
- Local selection queues a URI through the bridge. `SpircHandler::loadTrackFromURI` validates a 22-character base62 track ID, pads its GID to 16 bytes, creates a one-track LOAD frame with non-null context and position zero, and reuses normal engine handling.
- The search results are **not** a playlist/autoplay queue. Selecting a result starts one track. Full local queue/playlist support remains future work.

Keep playback controls and frame mutations serialized on the engine packet-dispatch thread. Earlier direct/control races crashed nanopb encoding during pause→play. Do not reintroduce calls from UIKit to mutable engine state directly.

## Recommended next implementation sequence

1. **Inspect and checkpoint the working tree.** Identify current branch, staged/untracked files, local README updates and all nested repositories/submodules. Preserve user changes. Do not assume old tar manifests are suitable as an editing mechanism now that you have direct access.
2. **Run a fresh isolated OAuth search probe on the Mac.** Use the user's own client ID and PKCE; open a QR for phone authorization; validate callback state and exact registered redirect; exchange code; make exactly one track-search request. Do not SSH the token to the existing playback account importer. Keep tokens in memory for this probe. Print track metadata on success or safe HTTP/retry/error reason on failure. No automatic retry. Inspect current Spotify application access/allowlist/quota configuration if its token also fails; verify current rules with official documentation rather than assuming a specific cause.
3. **If the probe succeeds, create separate catalog token storage on iPad.** Access token, refresh token and expiry belong to separate Keychain records. Preserve bundle identity/access group. Refresh with the user's client ID, handle rotated refresh tokens, and serialize concurrent refresh operations. Clear/recover catalog credentials without erasing playback credentials.
4. **Adapt the existing on-device QR setup for catalog authorization.** The verifier stays on iPad. The temporary Mac callback helper may remain until relay work. Separate setup states for playback account and catalog access; do not describe one as proving the other.
5. **Change CatalogSearch to the new catalog OAuth provider.** Retain caching, request pacing and safe diagnostics. Scope persisted cooldown to the authorization/client generation so a known restriction from the old path is not blindly attributed to the new path. Do not delete a real current cooldown just to retry early.
6. **Clean generated app packaging.** Build into a fresh staging bundle or remove only obsolete generated executables while preserving resources and the current CFBundleExecutable. Confirm Info.plist targets the newly signed executable. Reinstall in a way that does not keep merging old binaries forever; preserve account data/Keychain and keep rollback practical.
7. **Run device acceptance tests below.** Update the project README with actual results and unresolved issues.

## Build and install reference

```sh
cd ~/Projects/Personal/ipad2MediaPlayer
source native-player/build-venv/bin/activate
bash native-player/ios/auth/build-login-app.sh
```

The wrapper checks app identity, signs with Keychain entitlements and gives the executable a hash-based name. The user's last copy uploaded approximately eighteen old `ipad-player-*` binaries, because previous generated bundles and remote copies accumulated them. This is a packaging cleanup issue; it did not explain the catalog 429, since v2 diagnostic messages proved v2 was running.

Close the app from the iPad app switcher before installation. Previous installation pattern:

```sh
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

Use a cleaner staged installation for the next version rather than simply continuing that merge pattern. Do not delete unrelated applications or user data.

Optional one-time playback recovery marker: `/var/mobile/Documents/cspot-use-connect-pairing`. When present it forces original Connect pairing; successful login removes it. Do not create it merely to troubleshoot catalog access. Independent saved-login testing requires it to be absent.

Safe focused diagnostics:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/cspot-app.log' |
  grep -E 'CATALOG:|PLAYBACK AUTH:|AUTH:|APP:|AUDIO:|Track failed' |
  tail -100
```

Do not collect/paste raw CDN URLs, OAuth codes, tokens, auth blobs or unredacted credential storage. Keep catalog diagnostics distinct from playback-token diagnostics.

## Acceptance tests and evidence to retain

- Fresh own-app OAuth search returns HTTP 200 and a non-empty list of real track metadata.
- Catalog QR login and refresh preserve the working playback Keychain account.
- No second simultaneous token exchange for concurrent consumers; no duplicate request on reopening a cached search.
- Full Retry-After respected, including long intervals and across app restart; quota restrictions handled visibly.
- Open iPad app from a terminated state using saved credentials. Search and select a song locally. Hear audio without selecting CSpot from the phone.
- Pause→resume repeatedly, change track locally and from optional remote control. No crash, locked controls or stale metadata.
- Manual lock, automatic lock and unlock→lock transitions maintain audio without stuttering.
- Close/reopen and select a different track locally again. Then test token expiry/refresh and transient network failure.
- Generated/installed bundle contains the current executable and intended resources, without obsolete hashed executable accumulation.
- Record build identity, exact tests and device outcomes in README. Do not claim runtime validation from host mocks alone.

## Previous validation and port pitfalls

Host checks passed for catalog v2 C++ syntax, token sharing under twenty concurrent consumers, one network request, expiry margin, rejected-credential stop, full-day Retry-After, cached results, persistent cooldown/quota state, malformed responses, existing bridge controls and patch-installer guards. Real UIKit/Xcode compilation was done by the user; real public API success was not observed.

Preserve these existing fixes:

- Legacy SDK .tbd files with mixed device/simulator architectures needed normalization. Both libSystem aliases needed missing memory/string exports. Do not casually revert the SDK overlay generator.
- CSpot's modern C++ types use backports under the legacy libc++ ABI. Do not inject compatibility types into std indiscriminately.
- `CliPlayer`'s callback captured the hash functor by dangling reference; it was changed to capture by value.
- `CentralAudioBuffer` constructor takes a chunk count, not a byte budget. `128 * 1024` attempted a roughly 540 MB allocation. The legacy iPad path uses a small bounded chunk count. Inspect the current buffer/audio fixes before changing it.
- Atomic initialization was changed to direct brace initialization for old libc++.
- DNS-SD links against the legacy iOS `libsystem_dnssd.tbd`, not a desktop `dns_sd` library.
- CoreGraphics, CFNetwork and other wrapper frameworks were added for symbols exposed by the old SDK layout.
- Plain command-line output uses MACOSX_BUNDLE FALSE; the UIKit wrapper is packaged separately.
- Explicit C linkage guards are required for Objective-C functions invoked by Objective-C++.
- Serialization fixes cover track-reference protobuf encoding and mutable playback/frame access. These were verified by the user after a pause/resume crash.

## Delivered patch history

The Mac working tree should contain these changes already; verify rather than reapply blindly:

1. `ipad2-port-patch-1`
2. Background wrapper plus later audio-session/playback-metrics fixes
3. `ipad2-now-playing-patch`
4. `ipad2-control-serialization-fix`
5. Persistent login and `ipad2-on-device-qr`
6. `ipad2-playback-token-diagnostics`
7. `ipad2-connect-recovery`
8. `ipad2-catalog-picker`
9. **`ipad2-catalog-v2` — latest installed version**

There were also manual fixes between archives; the repository is the authoritative integration. Exact-hash archive installers created backups under `native-player/port-backups`. Keep those backups until the source is cleanly checkpointed.

## Reference URLs

- CSpot: https://github.com/feelfreelinux/cspot
- Spotify search: https://developer.spotify.com/documentation/web-api/reference/search
- PKCE: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
- Token refresh: https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens
- Rate limits: https://developer.spotify.com/documentation/web-api/concepts/rate-limits
- Quota modes: https://developer.spotify.com/documentation/web-api/concepts/quota-modes
- 2026 quota update: https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates
- Related login5 externally authenticated credential report: https://github.com/librespot-org/librespot/issues/1737 — supporting context, not proof of this device's exact cause.

The user prefers concrete progress and minimal repeated confirmation. Continue implementation and reversible verification within the stated project scope, explain material findings clearly, and keep secrets out of outputs.
