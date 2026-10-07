# Phone QR authorization and iPad token compatibility test

This diagnostic leaves the working UIKit player and its source unchanged. It adds a separate command-line executable and a Mac helper. It does not play music, persist credentials, refresh tokens, or implement production pairing.

The Mac displays a QR code containing Spotify's official authorization URL and a PKCE challenge. Scan it with a modern phone browser. After approving, Spotify redirects to the already registered `http://127.0.0.1:8765/callback`. On a phone that address belongs to the phone, so the page cannot connect. This is expected: copy the **entire final browser address** and paste it into the hidden Mac prompt. Universal Clipboard can help. Do not paste the callback into ChatGPT. If the phone hides or removes the address after its error, this manual callback method cannot complete; report that behavior.

This is a manual cross-device test, not a seamless QR pairing flow. An automatic return from the phone needs an HTTPS callback relay and a registered redirect for that relay. No relay is included.

The helper verifies callback state, exchanges the code with PKCE S256, and sends the resulting access token directly through encrypted SSH standard input. It writes no token/refresh-token file and does not put secrets in command-line arguments. The authorization QR contains no password or access token. Its temporary image is deleted after the run.

The iPad probe tries OAuth-token AP authentication, extracts the canonical account identity and reusable credential type from APWelcome, closes the connection, and tests those returned credentials on a fresh connection. It prints only stages and outcomes. Credentials stay in process memory and are discarded at exit; this is not secure persistence or a memory-erasure guarantee. Do not run under verbose network tracing.

## Apply and build on the Mac

```bash
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-qr-token-test.tar.gz
python3 ipad2-qr-token-test/apply.py "$PWD" --check &&
python3 ipad2-qr-token-test/apply.py "$PWD"
source native-player/build-venv/bin/activate
python -m pip install -r native-player/ios/token-test/requirements.txt
bash native-player/ios/token-test/build-test.sh
```

The separate build directory reuses the existing normalized SDK, old libc++ headers, patched CSpot/Bell sources, and Mbed TLS checkout. It may compile the libraries again. It does not install or replace the working app. Only the diagnostic CMake target is built.

## Upload the diagnostic

```bash
scp -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/token-test/cspot-token-test \
  root@192.168.13.24:/tmp/cspot-token-test &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chmod 755 /tmp/cspot-token-test'
```

## Authorize with your phone

Confirm the developer dashboard has the exact registered redirect `http://127.0.0.1:8765/callback`, and your account is permitted for the development app. This uses public Client ID `8686d6b87e484c50a6f9ab93bcc099e7`; no client secret is needed.

```bash
python native-player/ios/token-test/authorize-and-test.py
```

A QR image opens on the Mac. Scan, sign in, approve, then copy/paste the final callback URL as described above. The paste is hidden. If SSH asks for the iPad's root password, enter it at its normal prompt. The iPad network experiment has a 90-second watchdog; phone authorization must be completed within ten minutes of starting the helper. Complete code exchange promptly because authorization codes are short-lived.

Report the `TOKEN TEST:` output and build errors only. Never share the callback URL, authorization code, access token, or credential bytes. A rejection is a valid test result: official Web API OAuth success does not establish compatibility with CSpot's unofficial protocol.

Expected success:

```text
TOKEN TEST: OAuth AP login passed; testing reusable credentials on a new connection
TOKEN TEST: PASS — OAuth login and fresh-connection reusable login; same canonical account.
```

Passing does not establish automatic refresh, playback from this login, long-term credential reuse, or reconnect after restarting the app. Those experiments follow before integrating login and secure storage into the player. The original player can stay installed; for an isolated diagnostic, leave it closed during this test.

## Implementation and validation

CSpot's login encoder has a fixed 512-byte authentication buffer. The diagnostic constructs a protobuf login request separately, with a 16 KiB upper bound, so larger OAuth tokens cannot overflow that buffer. It leaves the original encoder untouched. APWelcome is decoded with the project's existing generated schema and checked before reuse.

Host checks passed: callback/state rejection cases, PKCE RFC reference vector, compiled C++ request encoder with a 2048-byte credential and upper bound rejection, and shell syntax. C++ syntax was checked against project headers with mock TLS declarations. Installer clean application/reapplication and conflict guards were tested. Apple linking, QR rendering with the Mac dependency, and actual Spotify/iPad authentication remain to be verified.

Official flow: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow

New source: GPL-3.0-or-later. Packaging, Keychain persistence, automatic QR pairing, and distribution license review remain future work.
