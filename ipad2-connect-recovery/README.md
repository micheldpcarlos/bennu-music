# One-time Connect pairing and startup recovery

Requires the on-device QR patch and playback-token diagnostics already installed. Apply from the project root, build with the Keychain signing wrapper, and reinstall the app:

```sh
tar -xzf ~/Downloads/ipad2-connect-recovery.tar.gz
python3 ipad2-connect-recovery/apply.py "$PWD" --check &&
python3 ipad2-connect-recovery/apply.py "$PWD"
bash native-player/ios/auth/build-login-app.sh
```

Follow native-player/ios/auth/CONNECT-RECOVERY.md to enable the one-time pairing flag. Open the rebuilt iPad app and pair by selecting CSpot player from the official phone Spotify app, rather than scanning another QR. This is a controlled test of the formerly working credential path, not a verified playback fix. After successful login and credential storage, the flag is automatically removed and later launches use Keychain.
