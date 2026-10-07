# Persistent account login checkpoint

This patch integrates the **verified OAuth → reusable CSpot credential login** with the existing player. A separate Mac pairing helper displays the phone QR, verifies two AP logins, and transfers only reusable credentials over SSH. The player imports them into iOS Keychain and loads them on later launches.

The existing Now Playing controls, AudioQueue buffers, AVAudioSession setup and background playback files are not replaced. Three existing source files change: Session.cpp, CLI main.cpp and the app CMake file. The installer checks their exact expected contents before making changes and backs them up.

**Not yet verified:** Apple compilation of this patch, Keychain access under this jailbreak signing setup, playback with the stored account, and restart persistence. The prior separate test verified token login and reusable login on a new connection; it did not verify those additional behaviors.

## Apply and build

Save a copy of the current working app before rebuilding (the final copy command refuses an existing backup destination):

```bash
cd ~/Projects/Personal/ipad2MediaPlayer
python3 - <<'PY'
from pathlib import Path
import shutil
shutil.copytree(Path('native-player/ios/build/iPad2MediaPlayer.app'),
                Path('native-player/ios/build/iPad2MediaPlayer-before-login.app'))
print('Working app backed up.')
PY

tar -xzf ~/Downloads/ipad2-persistent-login.tar.gz
python3 ipad2-persistent-login/apply.py "$PWD" --check &&
python3 ipad2-persistent-login/apply.py "$PWD"
source native-player/build-venv/bin/activate
python -m pip install -r native-player/ios/auth/requirements.txt
bash native-player/ios/auth/build-pairing.sh &&
bash native-player/ios/auth/build-login-app.sh
```

If preflight reports a source mismatch, stop and share that filename. Do not bypass its check. The patch expects the successfully tested Now Playing/control fixes and the CFNetwork linkage fix.

## Install the app and diagnostic

Close the player through the iPad app switcher before updating/pairing.

```bash
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'

scp -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/pairing/cspot-pairing \
  root@192.168.13.24:/tmp/cspot-pairing &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chmod 755 /tmp/cspot-pairing'
```

## Pair once

```bash
python native-player/ios/auth/pair-player.py
```

Scan the QR with your phone, authorize, then copy the entire final failed loopback address onto the **Mac clipboard**. Press Enter at the prompt without pasting into the terminal. Missing `http://` is accepted. The helper checks state before exchanging the code. Use the newly generated QR for each run. The developer app's registered redirect remains `http://127.0.0.1:8765/callback`.

The helper prompts for the iPad SSH password as needed. It captures the diagnostic's private credential record rather than displaying it. Wait for:

```text
PAIRING: credentials transferred. Open the updated iPad player to import them into Keychain.
```

Open the app from its icon. It imports the pending credentials into Keychain, removes the temporary file after successful storage, connects with the saved account, and shows Ready. If no account is stored or pending, the original Spotify Connect discovery setup remains available; a successful discovery login also saves its returned credentials.

Do not run `/tmp/cspot-pairing --export-for-pairing` manually or paste its full output into chat: that mode emits private credentials for the helper to capture.

## Validate persistence and playback

1. Launch the updated app and confirm `AUTH:` reports import, Keychain load/save status 0, and successful account login.
2. Use Spotify on the phone to select this player and start a track. Check local pause/resume, next/previous, and screen-off playback.
3. Close Spotify on the phone and disconnect the Mac SSH session. Confirm an already playing track continues, including a track transition.
4. Force-close the iPad player and reopen it. Confirm it loads Keychain credentials and becomes Ready without scanning a QR or relinking the account. Starting a new song still uses Spotify remotely at this checkpoint because on-iPad browsing is not implemented.
5. Repeat after restarting the iPad and unlocking it once. Keychain availability is intentionally After First Unlock.

Collect only stage/status logs:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/cspot-app.log' | grep -E 'AUTH:|APP: engine|SESSION:|AUDIO:' | tail -60
```

If Keychain reports a nonzero status, share the status. This signing configuration has not yet been verified for Keychain access. The app stops with an account-storage error rather than saving credentials in a plaintext fallback. It does not silently discard an existing Keychain record if authentication fails.

## Storage behavior

The login build wrapper signs the app with a single private Keychain access group, matching its application identifier. `PHOENIXDEV` is a local namespace for this jailbreak development build, **not an Apple-issued developer team or provisioning profile**. Final supported distribution signing needs its own valid configuration. Whether this device accepts these entitlements remains to be tested; nonzero Keychain status stops account startup. Use `build-login-app.sh` for subsequent login builds to preserve the group.

The player stores a generic-password Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, a fixed service identifier and account key. Reusable username, credential type and bytes are kept together. Keychain synchronization is not requested; this item is tied to the device.

The developer SSH handoff temporarily stages a JSON record in `/var/mobile/Documents/phoenix-auth-inbox/credentials.json`, owned by mobile with mode 0600 inside a mode-0700 directory. **That temporary record is a plaintext file**, not Keychain storage. The app removes it only after a successful Keychain import. File type, owner, permissions, byte bounds, and JSON fields are validated; a symlink is refused. A failed import leaves the pending record for diagnosis/retry. If you abandon pairing, remove it:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'rm -f /var/mobile/Documents/phoenix-auth-inbox/credentials.json'
```

OAuth access and refresh tokens are not retained by this integration. Only reusable CSpot credentials are transferred to the player. Future Web API browsing needs a separate refresh-token lifecycle. Tokens/credentials remain in process memory during operations; this code does not promise complete memory erasure or security against a privileged attacker on a jailbroken device.

## Rollback

The original signed app backup remains local. To restore it while the iPad app is closed:

```bash
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer-before-login.app/. \
  root@192.168.13.24:/Applications/iPad2MediaPlayer.app/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

Source backups are listed by apply.py. The installer does not remove a Keychain item; an in-app account removal feature remains to be added before distribution.

## Mandatory follow-up before distribution

- Verify Keychain access with final app signing and entitlement configuration; test device reboot and account revocation.
- Test authenticated playback, local controls, background playback, reconnect, and track transitions from persistent login.
- Add an explicit account disconnect/logout action that removes Keychain credentials.
- Replace the manual developer SSH handoff with automatic QR pairing and a registered HTTPS callback; authenticate the device pairing and avoid staging plaintext credential files.
- Retain and refresh Web API credentials securely for on-iPad library browsing/search; integrate local song selection with the playback engine.
- Document account requirements, protocol compatibility limits, installation/signing, dependency versions and distribution licenses; provide privacy-safe diagnostics and recovery UI.

Host checks passed for modified C++ syntax with mocked platform declarations, actual Session/nanopb canonical-identity and credential-type updates, invalid-response and size-bound rejection, mocked pairing capture/redaction and handoff orchestration, and installer guards. Objective-C/Keychain behavior and Apple builds require device validation.

New source is GPL-3.0-or-later. Apple Keychain access-group reference: https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps

Official OAuth reference: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
