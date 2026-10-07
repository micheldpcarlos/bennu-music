# On-device QR setup patch

Prerequisite: apply the persistent-login patch first. This patch contains source, not a prebuilt app. It does not include a relay.

From the project root:

```sh
tar -xzf ~/Downloads/ipad2-on-device-qr.tar.gz
python3 ipad2-on-device-qr/apply.py "$PWD" --check &&
python3 ipad2-on-device-qr/apply.py "$PWD"
source native-player/build-venv/bin/activate
bash native-player/ios/auth/build-login-app.sh
```

Installation and the device checklist are in `native-player/ios/auth/README.md`. Open the installed app, tap Connect Spotify, scan the QR, then run:

```sh
python3 native-player/ios/auth/forward-callback.py --ipad 192.168.13.24
```

Paste the complete phone callback at the visible prompt. The Mac forwards it; the iPad exchanges it and stores the reusable account. Keep the setup sheet open until it reports success.

Host verification passed: modified C++ syntax, OAuth request encoder/credential limits, callback boundaries, shell syntax and installer guards. Objective-C/UIKit compilation and runtime are unverified here because Xcode and the iOS SDK are on your Mac. iOS 9 HTTPS exchange, Keychain persistence, and playback regression checks remain mandatory.
