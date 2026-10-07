#!/bin/bash
set -euo pipefail
AUTH_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$AUTH_DIR/.." && pwd)"
bash "$IOS_DIR/app/build-app.sh"
APP="$IOS_DIR/build/iPad2MediaPlayer.app"
# Restrict these development entitlements to the receiver app we are updating.
python3 - "$APP/Info.plist" "$AUTH_DIR/Entitlements.plist" <<'PY'
from pathlib import Path
import plistlib,sys
app=plistlib.loads(Path(sys.argv[1]).read_bytes())
entitlements=plistlib.loads(Path(sys.argv[2]).read_bytes())
assert app['CFBundleIdentifier']=='org.ipad2mediaplayer.receiver', 'Unexpected app identifier; signing stopped'
assert entitlements['keychain-access-groups']==['PHOENIXDEV.'+app['CFBundleIdentifier']]
PY
TEMP_BINARY="$IOS_DIR/build/player/ipad-media-app-keychain"
cp "$IOS_DIR/build/player/ipad-media-app" "$TEMP_BINARY"
ldid -S"$AUTH_DIR/Entitlements.plist" "$TEMP_BINARY"
NAME="ipad-player-$(shasum -a 256 "$TEMP_BINARY" | cut -c1-12)"
# Replace the plain-signed executable from build-app.sh so the bundle ships one binary.
find "$APP" -maxdepth 1 -name 'ipad-player-*' ! -name "$NAME" -delete
cp "$TEMP_BINARY" "$APP/$NAME"
chmod 755 "$APP/$NAME"
python3 - "$APP/Info.plist" "$NAME" <<'PY'
from pathlib import Path
import plistlib,sys
p=Path(sys.argv[1]);value=plistlib.loads(p.read_bytes())
value['CFBundleExecutable']=sys.argv[2];p.write_bytes(plistlib.dumps(value))
PY
ldid -e "$APP/$NAME"
EXECUTABLES=$(find "$APP" -maxdepth 1 -name 'ipad-player-*' | wc -l | tr -d ' ')
test "$EXECUTABLES" = 1 || { echo "Bundle has $EXECUTABLES executables; expected 1" >&2; exit 1; }
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")" = "$NAME"
echo "Signed app with a private Keychain access group: $APP (executable $NAME)"
