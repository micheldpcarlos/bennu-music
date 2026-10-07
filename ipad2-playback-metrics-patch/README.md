# Screen-off playback diagnostics

This patch instruments the current iPad CSpot app, preserves existing playback
fixes, and adds no wake lock, power assertion, or playback recovery policy.
It requires the native app wrapper already installed in the source tree.
Both CLI and app targets include the same metrics implementation.

Apply from the project root:

```sh
python3 ipad2-playback-metrics-patch/apply.py "$PWD" --check
python3 ipad2-playback-metrics-patch/apply.py "$PWD"
bash native-player/ios/app/build-app.sh
```

Preflight checks all required source markers before changing anything. Backups
are retained under native-player/port-backups. Reapplying is idempotent.

The counters are per-interval deltas, normally emitted every two seconds:

- decoded: PCM bytes accepted into the central buffer from the decoder.
- queued: PCM bytes handed to AudioQueue successfully.
- consumed: PCM bytes in buffers returned by AudioQueue's callback.
- empty_reads: player attempts to read an empty central buffer while unpaused.
- waiting: snapshot of whether the producer is in the queue-buffer wait.
- interval_ms: wall-clock interval since the last report; clock changes can
  affect this measurement, so interpret it alongside epoch_ms and other logs.

44.1 kHz stereo 16-bit audio uses 176,400 PCM bytes per second. Buffering causes
small differences between counters; a sustained gap is the diagnostic signal.
Consumed callbacks do not prove the speaker produced audible sound. A running
queue can be starved. No counters establish system sleep policy by themselves.

Logs remain in /var/mobile/Documents/cspot-app.log on the observed installation.
For a fresh test, close the app via the app switcher, then remove only that log,
reopen the app, start a song, play for twenty seconds with the screen on, then
leave the screen dark for twenty seconds and wake it. Leave Spotify playing.

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@192.168.13.24 \
  'cat /var/mobile/Documents/cspot-app.log' |
  grep -E 'METRICS:|APP:|AUDIO:|failed|exception|External pause'
```

Background playback remains unresolved. Possible interpretations include:
consumed stalls while queued fills (output/callback issue); decoded and queued
stall with rising empty_reads (upstream supply issue); a large reporting gap
(process scheduling/suspension or clock change). Compare observations before
choosing a recovery mechanism.

Source is GPL-3.0-or-later; see included license. No SDK or device credentials
are bundled. Diagnostics use atomic counters in hot paths; logging is performed
by a separate reporter thread. Remove the reporter after diagnosis for release.
