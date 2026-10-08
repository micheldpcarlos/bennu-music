# Experimental native background-audio wrapper

Apply from the project root:

```sh
python3 ipad2-background-app-patch/apply.py "$PWD" --check
python3 ipad2-background-app-patch/apply.py "$PWD"
bash native-player/ios/app/build-app.sh
```

The existing CLI target remains available. The app target uses the same library,
CLI engine, AudioQueue sink, and current source fixes. No dependency source is
overwritten. This is a build-and-device experiment, not a verified screen-off fix.

After a successful app build, stop the diagnostic CLI before launching the app:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'killall cspot-ipad-audio-diag'
scp -r -O -o HostKeyAlgorithms=+ssh-rsa \
  native-player/ios/build/iPad2MediaPlayer.app \
  root@<ipad-ip>:/Applications/
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'chown -R mobile:mobile /Applications/iPad2MediaPlayer.app && uicache'
```

If killall says no matching process exists, continue. If uicache fails or is
missing, report its error. Do not install arbitrary packages to bypass it.

Open **iPad Media Player** from the Home screen. Do not start the binary over SSH:
this test needs SpringBoard to launch the application. Select CSpot player in
Spotify on the phone, then play a full song. First test with the display on, then
manual lock, automatic screen sleep, and Home button backgrounding separately.
The placeholder UI does not yet search or control playback.

Logs go to the app's Documents/cspot-app.log. To locate them from the Mac:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa root@<ipad-ip> \
  'find /var/mobile/Containers/Data/Application /var/mobile/Documents \
    -name cspot-app.log -type f -exec cat {} \;' | tail -100
```

Some listed directories may be absent on this jailbreak; report errors if no log
is found. Logs may contain temporary Spotify CDN authorization URLs; remove them
before publishing logs publicly.

Files are GPL-3.0-or-later compatible with CSpot. See CSpot's LICENSE and the
included license copy. No Apple SDK or compiled third-party binary is bundled.
