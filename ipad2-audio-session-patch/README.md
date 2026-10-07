# Native AVAudioSession experiment

The supplied metrics remain near the expected 176,400 bytes/sec in background:
decoded PCM arrives, AudioQueue buffers are enqueued and consumed, empty reads
stay zero, and the reporter continues at roughly two-second intervals. This
does not prove audible output or rule out brief underruns. It argues against
sustained upstream starvation or full-process suspension in this trace.

This patch uses the iOS 9 AVAudioSession API, configured on the UIKit main thread,
for the app target only. It sets Playback category, Default mode and active YES,
and logs actual category, mode, route, sample rate, I/O duration and volume.
It also records route-change and interruption notifications. The CLI retains its
previous legacy AudioSession path. Metrics and the existing engine remain.

No forced screen wake, repeated reactivation, private power entitlement or
arbitrary process restart is added. Screen-off playback is still unverified.

```sh
python3 ipad2-audio-session-patch/apply.py "$PWD" --check
python3 ipad2-audio-session-patch/apply.py "$PWD"
bash native-player/ios/app/build-app.sh
```

After a successful build, close the app via the app switcher before uploading
the updated bundle. Refresh with uicache and launch via the Home screen.
Use the same twenty-second screen-on, screen-off and wake test.

```sh
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@192.168.13.24:/Applications/
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app &&
   rm -f /var/mobile/Documents/cspot-app.log && uicache'
```

The fixed log location is grounded in this device's observed installation.
After the test, leave Spotify playing and collect:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/cspot-app.log' |
  grep -E 'SESSION:|METRICS:|APP:|AUDIO:|failed|exception'
```

The earlier first launch ended its engine thread with "Can't connect to spotify
servers". The app does not yet reconnect automatically after that exception.
That is separate from the successful run's screen-off issue; a retry lifecycle
with clean teardown and user-visible status remains release work.

The installer preserves current CoreGraphics, buffer, timer, metrics, and SDK
repairs. It requires the current wrapper; this is not a complete pristine-source
distribution. Backups go under native-player/port-backups. Source is
GPL-3.0-or-later; see included license. No Apple SDK is distributed.
