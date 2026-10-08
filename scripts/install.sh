#!/bin/bash
# Staged install: upload the freshly built bundle next to the installed one, then
# swap directories. Nothing is merged into the old bundle, so obsolete hashed
# executables cannot accumulate. Keychain data lives outside the bundle and is
# untouched. The previous bundle is kept as BennuMusic.app.previous for rollback.
#
# Usage: IPAD=root@<ipad address> scripts/install.sh
# The iPad needs OpenSSH (jailbreak) and your public key in /var/root/.ssh/authorized_keys.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT_DIR/native-player/ios"
APP="$IOS_DIR/build/BennuMusic.app"
IPAD="${IPAD:?Set IPAD=root@<ipad address> (see README: Install)}"
# iOS 9's sshd only offers ssh-rsa host keys, which modern OpenSSH disables by default.
SSH_OPTS=(-o HostKeyAlgorithms=+ssh-rsa)

test -d "$APP" || { echo "Build first: scripts/build.sh" >&2; exit 1; }
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
test -x "$APP/$EXECUTABLE" || { echo "Info.plist executable $EXECUTABLE missing from bundle" >&2; exit 1; }
COUNT=$(find "$APP" -maxdepth 1 -name 'bennu-music-*' | wc -l | tr -d ' ')
test "$COUNT" = 1 || { echo "Bundle has $COUNT executables; rebuild before installing" >&2; exit 1; }
echo "Installing executable $EXECUTABLE to $IPAD (the app is stopped only for the swap)"

# Upload while the app may still be running: on a locked iPad, background audio is
# what keeps Wi-Fi awake, so the app is stopped only right before the swap.
ssh "${SSH_OPTS[@]}" "$IPAD" 'rm -rf /Applications/BennuMusic.app.staging'
scp -r -O "${SSH_OPTS[@]}" "$APP" "$IPAD:/Applications/BennuMusic.app.staging"
ssh "${SSH_OPTS[@]}" "$IPAD" 'set -eu
cd /Applications
killall -9 bennu-music-* 2>/dev/null || true
# Bundles from before the rename to Bennu Music.
killall -9 ipad-player-* 2>/dev/null || true; rm -rf iPad2MediaPlayer.app iPad2MediaPlayer.app.previous
rm -rf BennuMusic.app.previous
if [ -d BennuMusic.app ]; then mv BennuMusic.app BennuMusic.app.previous; fi
mv BennuMusic.app.staging BennuMusic.app
chown -R mobile:mobile BennuMusic.app
uicache
echo "installed: $(ls BennuMusic.app | grep -c "^bennu-music-") executable(s) in bundle"'
# Verify the device bundle matches what was built; fail loudly otherwise.
# (The iPad shell lacks wc/head/tail, so all counting happens here.)
REMOTE_LIST=$(ssh "${SSH_OPTS[@]}" "$IPAD" 'ls /Applications/BennuMusic.app' 2>/dev/null)
REMOTE_ICONS=$(printf '%s\n' "$REMOTE_LIST" | grep -c '^AppIcon-.*\.png$' || true)
LOCAL_ICONS=$(find "$APP" -maxdepth 1 -name 'AppIcon-*.png' | wc -l | tr -d ' ')
if printf '%s\n' "$REMOTE_LIST" | grep -qx "$EXECUTABLE" && [ "$REMOTE_ICONS" = "$LOCAL_ICONS" ]; then
  echo "Verified on device: $EXECUTABLE with $LOCAL_ICONS icons"
else
  echo "DEVICE BUNDLE DOES NOT MATCH THE BUILD: $(printf '%s ' $REMOTE_LIST)" >&2; exit 1
fi
echo "Done. Rollback: ssh $IPAD 'cd /Applications && rm -rf BennuMusic.app && mv BennuMusic.app.previous BennuMusic.app && uicache'"
