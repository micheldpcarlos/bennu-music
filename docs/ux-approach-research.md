# Bennu Music: UX approach research (login, browsing, playback)

Date: 2026-10-07. Scope: jailbroken iPad 2 (iOS 9.3.5) running a cspot-based Spotify client. Sources are linked inline with dates; items marked *hypothesis* are not verified on device.

## Executive summary

Recommendation, ranked: **D (hybrid) > A > C > B.** Keep Spotify Connect pairing as the primary account setup and add Spotify's **OAuth device-authorization flow using the desktop client ID** as a second, relay-free login (QR to `spotify.com/pair`). Keep on-device browsing on the internal spclient endpoints, but isolate that layer behind feature flags because Spotify broke librespot-class clients five times in the last 14 months. Option B is not viable as the main path: since 2026-08-10 Spotify's login5 rejects playback credentials derived from tokens of any client ID other than the one used at login5, custom developer-app client IDs are not allowed to use the device flow, and Development Mode now caps apps at 5 users, requires Premium, limits search to 10 results and removes batch/browse endpoints. Option C is the most robust and the only one Spotify officially endorses (its own "Soloist" receiver is exactly this), but it abandons the core goal of picking music on the iPad.

## Comparison

| Criterion | A: standalone, internal endpoints | B: own dev app + Web API | C: Connect-only receiver | D: C setup + A browsing + device-flow login |
|---|---|---|---|---|
| Setup friction | One-time Connect pairing from phone (works today) | QR + Mac relay today; no relay-free path with own client ID | Pick device in phone app; nothing else | Pairing or QR code at `spotify.com/pair`; no relay, no Mac |
| Robustness to Spotify changes | Low-medium: 5 server-side breaks since Aug 2025 | Low for playback (login5 blocked 2026-08-10); medium for Web API (policy churn) | High: zeroconf path survived every 2025-26 incident | Medium: Connect fallback always available |
| ToS exposure | Internal endpoints; Terms IV.2.1(b) reverse engineering; Policy III "replicate core experience" | Lowest for browsing; playback still needs librespot-class engine | Same engine as A; no undocumented catalog calls | Same as A |
| Features | Search, album, playlist, artist, liked, radio, recent work; rootlist 500; lyrics untested | Search (10 results), playlists (owned only), library; no batch, no browse categories, no top tracks | Whatever the phone app offers; iPad shows now playing only | Union of A and C |
| Offline / screen-off | Plays screen-off; no offline cache (Terms IV.3.2 Premium-only caching) | Same engine | Same | Same |
| Multi-user household | Re-pair per user; one account at a time | 5 allowlisted users max per client ID | Anyone on the LAN with Premium can pick the device | Re-pair or re-QR per user; new accounts may hit audio-key error #1649 |

## 1. Which approach gives the best and simplest UX

The deciding fact is what Spotify changed on 2026-08-10. librespot maintainers and go-librespot's author independently concluded that login5 now refuses a stored credential when the access token that produced it came from a client ID different from the one presented to login5 ([librespot #1737](https://github.com/librespot-org/librespot/issues/1737), 2026-08-13; [go-librespot #364](https://github.com/devgianlu/go-librespot/issues/364), 2026-08-12: "Spotify killed the authentication flow via Login5 when using stored credentials produced by the AP with an access token with a different client ID than the desktop one"). cspot's `AccessKeyFetcher.cpp` sends the desktop ID `65b708073fc0480ea92a077233ca87bd`, while the QR flow used your own app ID `8686d6b8...`, which is exactly the rejected combination. Connect pairing hands over a blob already bound to Spotify's own client, so it keeps working. This is why every community workaround in August 2026 was "remove the token config and pair via Connect" ([Volumio thread](https://community.volumio.com/t/new-2023-spotify-plugin/63381/779), 2026-08-12; [Music Assistant #6051](https://github.com/music-assistant/support/issues/6051), 2026-08-11).

For browsing, B's Web API is now a worse catalog than the internal one: new Development Mode apps get 1 client ID, 5 authorized users, Premium required, search `limit` max 10, and lose batch fetch, browse categories, artist top-tracks and other users' playlists ([Feb 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide); [Feb 6 2026 blog](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security); [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes); [Jul 23 2026 quota update](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates)). Extended quota requires a registered business with 250k MAU.

Legal exposure is similar for A, C and D because all stream through a reverse-engineered engine; only B's browsing half is "clean". The Developer Terms prohibit reverse engineering (IV.2.1(b)) but do license streaming SDAs "for private personal use" (III.1.1) ([terms](https://developer.spotify.com/terms)); the Developer Policy bars products that "replicate ... a core user experience of Spotify" (III) ([policy](https://developer.spotify.com/policy)). In practice Spotify's enforcement against librespot-class clients across 2025-26 has been technical (closing flows), not account bans; I found no credible 2025-26 reports of Premium accounts being restricted for using librespot, Raspotify or Volumio. Risk of account restriction is low but non-zero. *Hypothesis.*

## 2. OAuth/QR specifics

**Device authorization grant (RFC 8628) exists and is the right tool.** Endpoints are `POST https://accounts.spotify.com/oauth2/device/authorize` (returns `user_code`, `device_code`, `verification_uri_complete` = `https://spotify.com/pair?code=XXXXXX`, `interval` 5 s) and `POST https://accounts.spotify.com/api/token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code`, polled until it stops returning `authorization_pending`. No headers, PKCE, secret or cookies are needed. Field names are exactly RFC 8628 ([librespot docs/device-authorization.md](https://github.com/librespot-org/librespot/blob/dev/docs/device-authorization.md), probed 2026-08-18; merged in [PR #1745](https://github.com/librespot-org/librespot/pull/1745), 2026-08-22). go-librespot shipped the same as `credentials.type: device_auth` and serves the code at `GET /auth/code` for a UI ([README](https://github.com/devgianlu/go-librespot)).

**But only allowlisted client IDs may use it.** Your own developer app gets `unauthorized_client`. The desktop ID (`65b708073fc0480ea92a077233ca87bd`) works, as do PlayStation, Xbox, Samsung TV, Android TV, LG TV and Wear OS IDs; Android and iOS IDs do not. A 2023 community request to open the flow to custom apps is unanswered ([community thread](https://community.spotify.com/t5/Spotify-for-Developers/Device-Authorization-Grant-authentication-flow-for-custom/m-p/5485468)). Request only the scopes you need (`streaming`, `playlist-read-private`, `user-library-read`, `user-read-recently-played`); one unrecognised scope fails the whole request.

**UX on the iPad:** show a QR encoding `verification_uri_complete` plus the six-character code as text. The phone scans it, approves in the Spotify app or web, and the iPad's poll returns an access and refresh token. No Mac, no loopback, no in-app browser.

**Alternatives considered:** a custom-scheme redirect (`com.example://callback`) is still allowed for registered apps ([Feb 2025 blog](https://developer.spotify.com/blog/2025-02-12-increasing-the-security-requirements-for-integrating-with-spotify); [redirect URI docs](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)), and an HTTPS relay page on your own domain that displays the `code` for typing would also work. Both still tie the token to your own client ID, which cannot yield playback credentials, so they only help the Web API half. The desktop ID's authorization-code flow is pinned to `http://127.0.0.1:8898/login` (see librespot `examples/get_creds.rs`, [PR #1744](https://github.com/librespot-org/librespot/pull/1744)), which brings back the relay problem. The device flow sidesteps all of this.

## 3. Why OAuth-derived credentials fail login5, and the fix

Mechanism (confirmed by maintainers, exact server rule unpublished): AP login with `AUTHENTICATION_SPOTIFY_TOKEN` succeeds and returns reusable stored credentials, but login5's `StoredCredential` exchange now checks that the `client_id` in the request matches the client that minted the originating token. cspot always sends the desktop ID, so credentials minted from your dev-app token are `INVALID_CREDENTIALS` (error 1). Connect-pairing credentials originate from Spotify's own apps and pass.

Known fixes, in order of confidence:

1. **Obtain the OAuth token under the desktop client ID**, then AP-login with it, reconnect with the returned stored credentials, store those in Keychain, and call login5 with the same desktop ID. This is what librespot's device flow and `get_creds.rs` do; the issue reporter confirmed "the device pair flow works well for my use case" ([#1737](https://github.com/librespot-org/librespot/issues/1737), 2026-08-27). cspot's existing login5 code should then work unchanged.
2. *Hypothesis:* use the OAuth access token directly as the spclient/dealer bearer and skip login5. During the 2026-09-29 login5 outage one tester found spclient and `connect-state` accepted the raw OAuth token, but the device did not appear in the phone app ([#1771](https://github.com/librespot-org/librespot/issues/1771)). Not a production path.
3. Using your own developer app ID for playback: no known fix; go-librespot's author calls the change "structural and definitive".

So B's login becomes viable for playback only by borrowing the desktop ID, at which point the token is not from "your app" and the Web API treats it as unregistered (your observed 429). Holding two tokens (desktop ID for playback, own app for Web API) is possible but inherits B's 5-user and endpoint limits.

## 4. What comparable projects do (2025-2026)

- **librespot 0.8.0** (2025-11-10) removed password login entirely. Options: zeroconf discovery (default), `--enable-oauth` (loopback redirect, stdin fallback for headless) and, since 2026-08-22, `--enable-device-auth` ([CHANGELOG](https://github.com/librespot-org/librespot/blob/dev/CHANGELOG.md)).
- **go-librespot**: `zeroconf` (optionally persisting credentials), `interactive` (user copies the redirect URL and curls it on the device) and `device_auth` ([README](https://github.com/devgianlu/go-librespot)).
- **Raspotify / Spotifyd**: librespot underneath; zeroconf is the documented default and Premium is required ([Raspotify README](https://github.com/dtcooper/raspotify)).
- **Music Assistant 2.10**: OAuth for the library plus a "one-time playback approval" (Connect-style) for librespot, or the official **Spotify Soloist** engine ([docs](https://www.music-assistant.io/music-providers/spotify/)).
- **Spotify Soloist** (2026-08-13): official headless Connect receiver for Linux (ARMv7, AArch64, x86_64), proprietary binary, API key from the developer dashboard, Premium to set up, builds expire after 90 days, WebSocket API for control only, no catalog browsing ([blog](https://developer.spotify.com/blog/2026-08-13-introducing-spotify-soloist); [docs](https://developer.spotify.com/documentation/soloist)). It cannot run on iOS 9, but it signals Spotify's direction: offer an official C-style receiver while closing private endpoints.

What users report as most reliable: zeroconf/Connect pairing, every time. It was the workaround for the Aug 2025 metadata 500s, the Aug 2026 login5 change, and the Sep 2026 outage. The device flow is too new (6 weeks) to have a track record but rests on the same desktop-ID credentials. One caveat for households: Premium accounts created roughly since late 2024 fail audio-key retrieval in librespot with no fix ([#1649](https://github.com/librespot-org/librespot/issues/1649), pinned; [#1735](https://github.com/librespot-org/librespot/issues/1735), 2026-08-03). cspot likely shares this. *Hypothesis.*

## 5. Robustness of spclient and login5

Spotify-side breakages affecting librespot-class clients:

| Date | Change | Time to community fix |
|---|---|---|
| 2025-08-05 | spclient metadata HTTP 500 after Ads API sunset ([#1527](https://github.com/librespot-org/librespot/issues/1527)) | 2 days (PR #1528) |
| 2025-08-12 | keymaster token endpoint 403; login5 becomes mandatory ([#1532](https://github.com/librespot-org/librespot/issues/1532)) | weeks, in dev only |
| 2025-11 | context/metadata shape changes ([#1623](https://github.com/librespot-org/librespot/issues/1623), [#1625](https://github.com/librespot-org/librespot/issues/1625)) | fixed in 0.8.0 |
| 2026-08-10 | login5 rejects foreign-client-ID stored credentials ([#1737](https://github.com/librespot-org/librespot/issues/1737)) | 12 days (device flow) |
| 2026-09-29 | login5 503 for several hours ([#1771](https://github.com/librespot-org/librespot/issues/1771)) | self-resolved |

Roughly one incident every 2-4 months, each needing a code change within days. Upstream cspot has had no commits since 2024-07-12 and its password-login issue ([#177](https://github.com/feelfreelinux/cspot/issues/177)) is open, so you are maintaining the fork alone and porting librespot fixes by hand. For option A this means: keep every spclient call behind a thin adapter with per-endpoint kill switches and a visible "catalog unavailable, Connect still works" state, track librespot's CHANGELOG monthly, and never let a catalog failure block Connect playback.

## Suggested next steps

- Implement the device-authorization flow in the iPad app with the desktop client ID: QR of `verification_uri_complete`, 5 s polling, then AP token login, stored-credential reconnect, Keychain save. Retire the Mac relay and the own-app QR flow.
- Keep Connect pairing as the first option on the setup screen and as the recovery path; the two flows produce interchangeable credentials.
- Keep spclient browsing but route it through one adapter with feature flags and diagnostics; fail soft to a "pick from your phone" screen.
- Test a second household account through the device flow and check for audio-key errors on newer accounts before promising multi-user support.
- For the private playlist list, try the protobuf rootlist endpoint with an explicit `Accept: application/protobuf` and the `decorate` parameters librespot uses, since the JSON variant returns 500. *Hypothesis.*
- Review librespot and go-librespot issues monthly; a break there usually precedes the same break in cspot by hours.
