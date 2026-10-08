# iPad 2 player checkpoint — 7 October 2026

## Confirmed on the iPad

- ARMv7 execution, C++ exceptions, threads, JSON, optional, variant, string views and byte order.
- Native CSpot Spotify playback through AudioQueue, with local now-playing metadata and controls.
- Background/screen-off playback after the audio fixes; pause/resume and next/previous after control serialization.
- Phone OAuth with PKCE, followed by OAuth AP login on the iPad and reusable-credential login on a fresh connection with the same account. That earlier test exchanged the OAuth code on the Mac and saved no credentials.

The persistent-login build and signing succeeded on the Mac. Keychain save, app restart login, and persistent playback still need device verification. The PHOENIXDEV entitlement namespace is a local jailbreak development configuration, not an Apple-issued distribution identity.

## New patch: QR on the iPad

Tap **Connect Spotify**, scan with a modern phone, and authorize. The phone's final loopback callback page fails to load because it points to the phone itself. Copy that complete address into the visible Mac prompt:

```sh
python3 native-player/ios/auth/forward-callback.py --ipad <ipad-ip>
```

Keep the iPad setup screen open. Its QR expires after ten minutes. Text pasted into the console is visible; avoid sharing terminal output. The Mac forwards the callback through SSH to a mobile-owned 0600 file inside a 0700 inbox. The iPad consumes and deletes the callback, checks its state and redirect, exchanges it using the verifier retained on the iPad, checks both OAuth and reusable CSpot login, then saves reusable credentials in Keychain. No client secret is used, and credentials are not included in app logs.

A player waiting for its first account connects automatically after storage succeeds. Replacing an account while playback is already running requires closing and reopening the app. This UIKit setup now uses saved credentials/QR authorization; the separate command-line player's original Connect pairing flow remains available.

The screen stays awake only while the QR sheet is open; closing it restores the previous idle-timer setting. Playback should still allow normal screen-off operation.

## Build and install

Prerequisite: the persistent-login patch is already applied. Use its signing wrapper:

```sh
source native-player/build-venv/bin/activate
bash native-player/ios/auth/build-login-app.sh
```

Close the installed player in the iPad app switcher, then:

```sh
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@<ipad-ip>:/Applications/
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

Open the app from its icon. Do not run its executable over SSH to test background behavior.

## Next device checks

1. QR scans in both orientations; denied authorization, expired QR and a callback from a previous QR show a useful error.
2. iOS 9 completes HTTPS token exchange. This is new and not yet verified; failures show HTTP/network status without response secrets.
3. Reusable login succeeds, Keychain save succeeds, and the waiting player connects.
4. Force-close/reopen and reboot/unlock: account restores without another phone authorization.
5. Local pause/resume, next/previous, manual lock, automatic sleep and long playback retain the earlier working behavior.
6. Logs show stage/status messages only. A forwarded callback is removed after consumption.

Host checks cover C++ syntax, the request encoder, callback validation and the patch installer. They do not replace compiling with Xcode or testing UIKit, QR rendering, TLS and Keychain on iOS 9.

## Roadmap

- **Later: HTTPS callback relay** with short-lived pairing sessions and authenticated one-time retrieval. The relay receives a callback, while the PKCE verifier stays on the iPad. This removes the manual Mac step; it does not host playback.
- On-device library/search/browsing and track selection, using a separate OAuth Web API token lifecycle where needed. This patch establishes account setup and existing playback controls; it does not add browsing.
- Logout/account switch, clear credentials, reconnect recovery, interruptions and network-change handling.
- Distribution checklist: reproducible dependency versions, all SDK normalization and port fixes in source, clean-machine build, real installation/signing instructions for the chosen jailbreak packaging route, dependency licenses/notices, crash symbol retention, battery/long-run tests, credential deletion, and a documented supported-device matrix. Review service and redistribution requirements before release.

No relay is included in this patch. The Mac is temporarily required for callback delivery during account setup, not for playback once the iPad is connected.
