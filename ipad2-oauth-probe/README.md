# iPad OAuth probe

This separate diagnostic app uses Client ID `8686d6b87e484c50a6f9ab93bcc099e7` and redirect URI `http://127.0.0.1:8765/callback`. Register that exact URI in the Spotify app settings and ensure your Spotify account is on the development app's user allowlist if required.

It opens the real Spotify authorization page inside iOS 9's SFSafariViewController, receives a callback on a listener bound only to the iPad's IPv4 loopback interface, verifies a fresh random state, exchanges the code with PKCE S256, then calls the profile endpoint. It uses no client secret and no running Mac/server. It requests streaming and read-only account/library/playlist scopes for this experimental player.

The probe does **not** authenticate CSpot, play audio, save credentials, or modify the existing player's source/app. Success proves OAuth and profile access only. Tokens remain in process memory and are not printed or saved. If Spotify's authorization page is broken on the old WebKit engine, this probe will not repair it; report that result instead of repeatedly rebuilding.

## Build

```bash
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-oauth-probe.tar.gz
python3 ipad2-oauth-probe/apply.py "$PWD" --check &&
python3 ipad2-oauth-probe/apply.py "$PWD"
bash native-player/ios/auth-probe/build-probe.sh
```

This reuses the existing normalized iOS 9.3 SDK. It does not rebuild the player or need additional Python dependencies. The source installer refuses to overwrite unexpected files and can be safely reapplied if unchanged.

## Install and test

```bash
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/oauth-probe/iPadOAuthProbe.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPadOAuthProbe.app && uicache'
```

Open **OAuth Probe** from the iPad icon and tap **Sign in to Spotify**. Complete authorization on the iPad; do not open its authorization URL on the Mac, since the callback belongs to the iPad. The app waits up to three minutes. Tap Done if the page is blank/broken; after cancellation, the Sign in button becomes available again.

Report the final status screen. It distinguishes a browser failure, missing callback, token-exchange failure and successful OAuth/profile access. HTTP 403 on the profile request can indicate a development-app user allowlist restriction. Keep authorization codes, tokens and client secrets private.

Logs are intentionally limited to stages, HTTP statuses and network error numbers:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/ipad-oauth-probe.log' | tail -40
```

If this succeeds, the next experiment passes the OAuth access token into CSpot, validates its returned canonical account identity and reusable credentials, then adds secure credential persistence. None of that is implemented in this probe.

## Limits and distribution

The diagnostic plist permits arbitrary loads so the loopback HTTP callback can be exercised on iOS 9; actual account/token/profile endpoints are fixed HTTPS URLs. This exception should be reviewed and narrowed before any production integration. The listener binds only to `127.0.0.1`, validates state and callback path, rejects duplicate parameters, limits request size and time, and does not log callback contents.

Host checks passed for installer application/reapplication and conflict rejection, shell syntax, app packaging and plist generation with mocked Apple build tools, the RFC 7636 PKCE reference vector, and configured Client ID/redirect constants. These checks do not execute the Objective-C implementation. UIKit/SafariServices compilation and OAuth behavior require the Mac/iPad and are not verified here. This is a diagnostic app, not a distribution-ready authentication implementation.

Sources: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow and https://developer.spotify.com/documentation/web-api/concepts/redirect_uri . New source is GPL-3.0-or-later.
