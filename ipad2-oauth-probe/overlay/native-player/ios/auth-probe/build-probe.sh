#!/bin/bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$TASK_DIR/../../.." && pwd)"
SDK="$PROJECT_DIR/native-player/ios/build/iPhoneOS9.3.sdk"
BUILD_DIR="$PROJECT_DIR/native-player/ios/build/oauth-probe"
APP="$BUILD_DIR/iPadOAuthProbe.app"
if [ ! -f "$SDK/System/Library/Frameworks/SafariServices.framework/SafariServices.tbd" ]; then
  echo "Missing normalized SafariServices SDK stub: $SDK" >&2
  echo "Use the same normalized iOS 9.3 SDK as the working player." >&2
  exit 1
fi
command -v ldid >/dev/null || { echo "Install ldid before building." >&2; exit 1; }
mkdir -p "$BUILD_DIR"
xcrun --sdk iphoneos clang \
  -target armv7-apple-ios9.0 -marm -O0 -g \
  -isysroot "$SDK" -fobjc-arc -fblocks \
  "$TASK_DIR/AuthProbe.m" \
  -framework UIKit -framework Foundation -framework CFNetwork \
  -framework CoreGraphics -framework QuartzCore -framework SafariServices -framework Security \
  "$SDK/usr/lib/system/libcommonCrypto.tbd" \
  -o "$BUILD_DIR/probe-executable"
ldid -S "$BUILD_DIR/probe-executable"
BINARY_NAME="oauth-probe-$(shasum -a 256 "$BUILD_DIR/probe-executable" | awk '{print substr($1,1,12)}')"
python3 - "$APP" "$BUILD_DIR/probe-executable" "$BINARY_NAME" <<'PY'
from pathlib import Path
import plistlib, shutil, sys
app=Path(sys.argv[1]); binary=Path(sys.argv[2]); name=sys.argv[3]
if app.is_symlink():
    raise SystemExit('Refusing to replace a symlink at the probe output path.')
if app.exists():
    shutil.rmtree(app)
app.mkdir()
shutil.copy2(binary,app/name)
(app/name).chmod(0o755)
info={
    'CFBundleIdentifier':'org.ipad2mediaplayer.oauthprobe',
    'CFBundleName':'OAuth Probe', 'CFBundleDisplayName':'OAuth Probe',
    'CFBundleExecutable':name, 'CFBundlePackageType':'APPL',
    'CFBundleVersion':'0.1.0', 'CFBundleShortVersionString':'0.1.0',
    'MinimumOSVersion':'9.0', 'LSRequiresIPhoneOS':True, 'UIDeviceFamily':[2],
    'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
    # Diagnostic-only app: allow the loopback HTTP callback on iOS 9.
    # Both token and profile requests are still fixed HTTPS endpoints.
    'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':True},
}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
print('Signed OAuth probe app:',app)
PY
xcrun otool -L "$APP/$BINARY_NAME"
