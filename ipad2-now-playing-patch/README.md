# iPad 2 Now Playing patch

This adds an on-iPad Now Playing screen to the working native CSpot receiver: track title, artist, album, artwork, estimated elapsed time, and play/pause/previous/next buttons. Buttons call the existing native playback engine; the Mac does not serve or play audio.

This is an intermediate milestone. Account linking and initial song/queue selection still happen through Spotify on another device. On-iPad authentication, library browsing, search and selecting a new queue are not implemented yet. Previous/next navigate the queue supplied by Spotify. The progress bar is read-only and estimated between engine events.

## Apply and build on your Mac

Close the existing iPad Media Player app through the iPad app switcher before installing the update. Keep the existing SDK, dependencies and build scripts.

```bash
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-now-playing-patch.tar.gz
python3 ipad2-now-playing-patch/apply.py "$PWD" --check &&
python3 ipad2-now-playing-patch/apply.py "$PWD"

source native-player/build-venv/bin/activate
bash native-player/ios/app/build-app.sh
```

The installer checks every replacement against the supplied source snapshot before making changes and backs up replaced files under `native-player/port-backups/now-playing-*`. Reapplying an unchanged patch is safe. If preflight fails, keep the error and current source; do not bypass the check.

## Install on the iPad

Run only after the build reports `Signed experimental app`:

```bash
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

Launch the app from its iPad icon, select CSpot player in Spotify and start a song. Do not start an additional SSH player process; it would compete for the same discovery name and port.

## Device checks

1. Confirm the title, artist and artwork match the playing song.
2. Pause and resume using the iPad buttons; verify both audible output and Spotify's remote state.
3. Try next and previous, including the beginning/end of the supplied queue.
4. Rotate the iPad and confirm the controls remain usable.
5. Check both manual screen locking and automatic sleep for at least two minutes, including a track transition. Wake and confirm the screen reflects current playback.
6. Close and reopen the app and verify linking works again. Automatic reconnection/retry and credential persistence are not part of this patch.

If something fails:

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/cspot-app.log' | tail -100
```

The patch leaves AudioQueue sizing, priming, audio-session setup, background-audio declaration and auto-lock behavior unchanged. UI polling runs only while the app is active. Artwork loads asynchronously; a missing image does not block audio.

## Validation and next milestone

Host tests passed for command ordering, thread handoff, callback reentry, paused progress, bounded pending commands and failure cleanup. Installer tests cover clean application, reapplication and refusing modified source. UIKit compilation and device playback remain to be verified on the Mac/iPad.

Next: connect on-iPad authentication and account browsing to this same engine, then implement track/queue selection. Before distribution, consolidate the full build fixes, pin dependencies, package installation/uninstallation, preserve credentials safely, and verify background playback and recovery on a clean device. This experimental patch is not a distribution package.

Modified CSpot sources retain their upstream license; see LICENSE.md. New player bridge/UI code uses GPL-3.0-or-later. No Apple SDK or compiled binary is included.
