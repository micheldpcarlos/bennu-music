# Connect credential recovery — 7 October 2026

## Verified checkpoint

The on-device QR exchanges OAuth successfully, checks OAuth and reusable AP login, and stores credentials in Keychain. Logs confirm reload from Keychain and subsequent successful AP login on multiple launches. Startup sometimes fails before login with a socket connection error. After successful login, Connect song commands and metadata arrive, but login5 returns HTTP 200 with INVALID_CREDENTIALS (error 1), preventing audio loading. QR-based full playback remains unverified.

An upstream librespot report describes the same OAuth → reusable AP success → login5 INVALID_CREDENTIALS sequence since August 2026: https://github.com/librespot-org/librespot/issues/1737 . This is corroboration, not proof that the root cause is identical or a confirmed server-side diagnosis. Retrying invalid credentials does not establish playback capability.

## Recovery test

This patch restores the original local Connect pairing path behind an explicit one-time flag. Saved QR credentials stay in Keychain until a new Connect login successfully saves its credentials. It does not remove QR setup or send credentials to the Mac. The HTTP pairing blob is separate from the engine blob; pairing requests are serialized and repeated successful submissions are ignored. Playback-token diagnostics and cooldowns remain in place.

Enable the test before opening the rebuilt app:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'touch /var/mobile/Documents/cspot-use-connect-pairing && chown mobile:mobile /var/mobile/Documents/cspot-use-connect-pairing && chmod 600 /var/mobile/Documents/cspot-use-connect-pairing'
```

Open iPad2MediaPlayer from its icon and select **CSpot player** in the official Spotify phone app on the same local network. Use the main player screen; do not open its QR sheet for this test. Initial pairing uses the phone. The native iPad engine performs playback and remains independent of a Mac player.

After successful AP login and Keychain storage, the flag is deleted automatically. If pairing fails before storage, it remains for retry. To cancel the mode without replacing credentials:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'rm -f /var/mobile/Documents/cspot-use-connect-pairing'
```

Close and reopen the app after changing the flag. If Connect-paired audio succeeds, test closing/reopening again without the flag and then screen-off playback. Confirm PLAYBACK AUTH reports token accepted. AP login alone is not sufficient to validate recovery.

## Startup recovery

The app makes up to three pre-login connection attempts, with delays of two and four seconds. Each failed session is discarded before the next attempt. The socket connector now tries every resolved address and safely handles a failed DNS lookup. Authentication rejection is not silently retried or replaced with insecure storage. These changes do not guarantee a total connection-time bound or add full mid-playback reconnect recovery.

Host validation: modified main and socket C++ syntax; actual socket implementation with controlled DNS/socket failures (first address fails, second succeeds; all addresses fail; DNS fails); address-list/socket cleanup; patch preflight, backups, reapplication and conflict guards. Device Connect pairing and playback recovery are not yet tested.

## Next decisions

- If Connect credentials work but QR credentials do not, preserve Connect pairing for usable playback while investigating the OAuth-to-playback credential exchange.
- If both fail, inspect the login5 protocol/token path before changing identity or retrying authorization again.
- Expose failed/buffering playback distinctly from reported remote play state; Spotify progress alone is not evidence of audio output.
- Build the callback relay later. It replaces manual OAuth callback forwarding and cannot repair a rejected playback credential.
