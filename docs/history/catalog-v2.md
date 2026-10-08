# Catalog v2: request control, caching and diagnostics

Apply this patch after `ipad2-catalog-picker`. It preserves the native playback engine, QR setup and existing account. It changes token acquisition and catalog request handling; it does not claim that Spotify has now granted catalog access.

## Changes

- Playback and search share one token provider per account session. Requests and token cache access are synchronized; concurrent consumers do not each authenticate separately.
- Refresh occurs shortly before token expiry instead of at half its lifetime.
- Explicit login5 INVALID_CREDENTIALS stops automatic token retries for that session. The Music screen reports account recovery is needed. Transient failures use increasing retry delays, capped at five minutes.
- Successful search results are cached for ten minutes, with up to eight queries retained in memory. Reopening Music remembers the last query and uses its cache. Cached results remain available during an API cooldown.
- A 429 honors numeric Retry-After values up to 2,147,483,647 seconds, without shortening them to two minutes. Oversized numeric values pause search instead of guessing an earlier retry. Missing/invalid headers use conservative backoff. The UI shows a countdown and disables Search during the wait.
- Catalog cooldowns survive app restarts. Only a deadline and a blocked flag are stored in `/var/mobile/Documents/cspot-catalog-policy.json`; no credentials, tokens or queries are written there.
- A recognized QUOTA_EXCEEDED reason without a usable retry interval pauses search for investigation. We do not invent a quota reset time.
- Safe diagnostics report request time, HTTP status, allowed error reason, retry seconds and server/fallback origin. No raw response, bearer token or query is logged.
- Music screen messages are in English. Its polling still reads local state only; it does not call Spotify every half second.

The catalog still uses the session's CSpot/login5 token, issued under CSpot's built-in Spotify web-client identity. This patch does not replace it with the OAuth token from your own developer app. Playback-token acceptance is not proof of public catalog permission. If Spotify still returns 429, 401 or 403, this version gives us evidence to decide the authorization change rather than retrying blindly.

## Build and install

Close iPad2MediaPlayer in the iPad app switcher first.

```sh
cd <repo>
tar -xzf ~/Downloads/ipad2-catalog-v2.tar.gz
python3 ipad2-catalog-v2/apply.py "$PWD" --check &&
python3 ipad2-catalog-v2/apply.py "$PWD"
source native-player/build-venv/bin/activate
bash native-player/ios/auth/build-login-app.sh

scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@<ipad-ip>:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

Open the app with the saved session, then Music. Let the initial search finish once. Do not re-pair or repeatedly reopen the app to bypass a wait. If it fails, collect:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'cat /var/mobile/Documents/cspot-app.log' |
  grep -E 'CATALOG:|PLAYBACK AUTH:|AUTH:|APP:' |
  tail -80
```

If a list loads, select a track locally, pause/resume, return to Music and confirm `cache hit; no network request`. Then test screen-off playback and closing/reopening with saved login. Local playback and catalog access remain unverified until these device tests pass.

## Recovery states

If login5 rejects credentials, more Search taps will not retry the rejected credentials. Recover the account through the previously working one-time Connect path; reconnecting with the same rejected account is not a fix.

If the catalog reports a quota restriction without a reset time, stop searching and inspect its reason. Do not delete the policy file just to bypass Spotify's restriction. After the authorization/quota cause is resolved, close the app and remove only `cspot-catalog-policy.json` to clear the recorded block. The policy contains no account credentials and does not affect Keychain.

## Validation performed here

- C++ syntax checks for token provider, TrackQueue, catalog, bridge and CLI integration passed.
- Actual token-provider test: twenty concurrent consumers share one request; valid-token cache reuse, refresh margin, permanent credential rejection and full-day Retry-After passed.
- Catalog tests using simulated HTTP: UTF-8 escaping, successful result cache, pacing, 24-hour cooldown, restart restoration, quota block restoration, oversized headers, malformed response and unavailable token passed.
- Existing playback-control bridge regression passed.
- Installer preflight, conflict protection without partial writes, backups and idempotence passed.

Objective-C/UIKit compilation, signing and real Spotify requests must be verified on your Mac/iPad. No credentials are included in this patch.
