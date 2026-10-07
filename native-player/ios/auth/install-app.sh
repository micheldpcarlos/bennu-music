#!/bin/bash
# Staged install: upload the freshly built bundle next to the installed one, then
# swap directories. Nothing is merged into the old bundle, so obsolete hashed
# executables cannot accumulate. Keychain data lives outside the bundle and is
# untouched. The previous bundle is kept as iPad2MediaPlayer.app.previous for rollback.
set -euo pipefail
IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$IOS_DIR/build/iPad2MediaPlayer.app"
IPAD="${IPAD:-root@192.168.13.24}"
SSH_OPTS=(-o HostKeyAlgorithms=+ssh-rsa)

test -d "$APP" || { echo "Build first: bash $IOS_DIR/auth/build-login-app.sh" >&2; exit 1; }
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
test -x "$APP/$EXECUTABLE" || { echo "Info.plist executable $EXECUTABLE missing from bundle" >&2; exit 1; }
COUNT=$(find "$APP" -maxdepth 1 -name 'ipad-player-*' | wc -l | tr -d ' ')
test "$COUNT" = 1 || { echo "Bundle has $COUNT executables; rebuild before installing" >&2; exit 1; }
echo "Installing executable $EXECUTABLE to $IPAD (close the app in the iPad app switcher first)"

scp -r -O "${SSH_OPTS[@]}" "$APP" "$IPAD:/Applications/iPad2MediaPlayer.app.staging"
ssh "${SSH_OPTS[@]}" "$IPAD" 'set -eu
cd /Applications
rm -rf iPad2MediaPlayer.app.previous
if [ -d iPad2MediaPlayer.app ]; then mv iPad2MediaPlayer.app iPad2MediaPlayer.app.previous; fi
mv iPad2MediaPlayer.app.staging iPad2MediaPlayer.app
chown -R mobile:mobile iPad2MediaPlayer.app
uicache
echo "installed: $(ls iPad2MediaPlayer.app | grep -c "^ipad-player-") executable(s) in bundle"'
# Verify the device bundle matches what was built; fail loudly otherwise.
# (The iPad shell lacks wc/head/tail, so all counting happens here.)
REMOTE_LIST=$(ssh "${SSH_OPTS[@]}" "$IPAD" 'ls /Applications/iPad2MediaPlayer.app' 2>/dev/null)
REMOTE_ICONS=$(printf '%s\n' "$REMOTE_LIST" | grep -c '^AppIcon-.*\.png$' || true)
LOCAL_ICONS=$(find "$APP" -maxdepth 1 -name 'AppIcon-*.png' | wc -l | tr -d ' ')
if printf '%s\n' "$REMOTE_LIST" | grep -qx "$EXECUTABLE" && [ "$REMOTE_ICONS" = "$LOCAL_ICONS" ]; then
  echo "Verified on device: $EXECUTABLE with $LOCAL_ICONS icons"
else
  echo "DEVICE BUNDLE DOES NOT MATCH THE BUILD: $(printf '%s ' $REMOTE_LIST)" >&2; exit 1
fi
echo "Done. Rollback: ssh $IPAD 'cd /Applications && rm -rf iPad2MediaPlayer.app && mv iPad2MediaPlayer.app.previous iPad2MediaPlayer.app && uicache'"
