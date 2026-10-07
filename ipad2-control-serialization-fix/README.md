# Local control serialization fix

Apply this after the Now Playing patch. It targets the source snapshot you supplied plus that patch; it leaves your additional CFNetwork linkage intact.

The symbolicated iPad crash passed through `setPause -> sendCmd -> pbEncodeTrackList -> TrackReference` copy. Inspection found two unsafe paths: serialization borrowed the live track vector without its mutation lock, and encoders on different threads shared a static `TrackRef` with pointers into temporary records.

This fix keeps the track queue locked for the complete frame encoding, makes the protobuf record local to each call, and protects frame setters/serialization with a separate recursive mutex. The lock order is queue then frame; frame methods never acquire a queue lock. Notifications are sent after those locks are released. Existing AudioQueue and AVAudioSession settings are unchanged.

A second fix refreshes playback metadata when restarting the same track. Previously, the unchanged track hash prevented the notification that clears the Now Playing screen's loading state. The restart flag is consumed once even if the hash also changed, avoiding duplicate queue advancement.

## Apply and build

```bash
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-control-serialization-fix.tar.gz
python3 ipad2-control-serialization-fix/apply.py "$PWD" --check &&
python3 ipad2-control-serialization-fix/apply.py "$PWD"
source native-player/build-venv/bin/activate
bash native-player/ios/app/build-app.sh
```

Close the app from the iPad's app switcher, then install only after the build reports `Signed experimental app`:

```bash
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/ &&
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

The installer validates all input hashes before writing, backs up replaced files, and permits an unchanged reapplication. If preflight fails, stop and share the mismatch; do not bypass it. Preserve the old binary until the new device tests pass.

## Verify on the iPad

- Pause/resume from the iPad at least ten times, including quick and slow taps. Confirm Spotify also reflects the changes.
- After a song has played for more than three seconds, press previous: CSpot normally restarts that song. Verify elapsed time resets and controls remain available.
- Press previous again near the beginning to test moving to the preceding song. Test next and queue boundaries too.
- Confirm screen-off playback and a track transition remain smooth.

Host regression testing reproduces a crash with the old shared encoder and passes 9,000 parallel encode/decode operations with the corrected encoder. Mac ARMv7 compilation and the above device tests remain required. This does not establish that every CSpot concurrency issue is resolved.

This is still an experimental receiver with local controls. On-iPad authentication and browsing remain pending. These changes must be included in the consolidated reproducible source/build before distribution.
