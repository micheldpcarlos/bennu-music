# iPad 2 ARMv7 port patch 1

Apply to Michel's submitted 2026-10-06 snapshot. This is a source patch and
experimental build setup, not a finished Spotify package.

Save the archive to Downloads and run on the Mac:

```sh
cd ~/Projects/Personal/ipad2MediaPlayer
tar -xzf ~/Downloads/ipad2-port-patch-1.tar.gz
python3 ipad2-port-patch-1/apply.py "$PWD" --check
python3 ipad2-port-patch-1/apply.py "$PWD"
source native-player/build-venv/bin/activate
python -m pip install -r native-player/ios/requirements-build.txt
bash native-player/ios/build-ipad.sh probe
```

The installer validates every changed file and the three backport headers before
writing, refuses conflicting local modifications, and creates backups under
`native-player/port-backups`. Reapplying is safe when files match the patch.
It does not modify the original SDK, download dependencies, install on the iPad,
flash firmware or commit your Git repositories.

Then read `native-player/ios/README.md` for uploading the expanded probe and
building the full native player. Inspect `native-player/PORT_STATUS.md` and
`native-player/DISTRIBUTION.md` to continue the project with another agent.

Validation completed here:
- Compatibility probe built and ran in C++14/backport and C++20/standard modes.
- Ten DSP/container source files passed host C++14 syntax checks.
- SDK normalizer checks passed for architecture filtering, symlinked headers and
  preservation of original SDK files.
- Build shell script passed syntax checking.
- Installer dry-run, application, idempotence and conflict rejection tested.

Full macOS cross-build, expanded iPad probe, native AudioQueue sink and iPad
Spotify playback still require device/host testing. The product's independent
login, local controls and Safari frontend are not included in this patch.

Source changes are provided under CSpot's GPL-3.0-or-later terms; license included.
The external backport code, Apple's SDK and credentials are not bundled.
