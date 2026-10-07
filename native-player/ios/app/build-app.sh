#!/bin/bash
set -euo pipefail
APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(dirname "$APP_SOURCE")"
bash "$IOS_DIR/build-ipad.sh" build
APP_BINARY="$IOS_DIR/build/player/ipad-media-app"
test -f "$APP_BINARY"
APP_STAGE="$IOS_DIR/build/iPad2MediaPlayer.app"
# Start from an empty bundle: older builds accumulated every hashed executable
# (eighteen were found in one bundle), and scp -r merged them onto the device.
rm -rf "$APP_STAGE"
mkdir -p "$APP_STAGE"
# Fresh executable names avoid the observed stale-signature issue on overwrite.
APP_EXECUTABLE="ipad-player-$(shasum -a 256 "$APP_BINARY" | cut -c1-12)"
cp "$APP_BINARY" "$APP_STAGE/$APP_EXECUTABLE"
chmod 755 "$APP_STAGE/$APP_EXECUTABLE"
ldid -S "$APP_STAGE/$APP_EXECUTABLE"
python3 - "$APP_SOURCE/Info.plist" "$APP_STAGE/Info.plist" "$APP_EXECUTABLE" <<'PY'
import plistlib
import sys
from pathlib import Path
plist = plistlib.loads(Path(sys.argv[1]).read_bytes())
plist['CFBundleExecutable'] = sys.argv[3]
Path(sys.argv[2]).write_bytes(plistlib.dumps(plist))
PY
for i in 29 40 58 76 80 152; do cp "$APP_SOURCE/icon/AppIcon-$i.png" "$APP_STAGE/"; done
xcrun otool -L "$APP_STAGE/$APP_EXECUTABLE"
echo "Signed experimental app: $APP_STAGE"
