#!/bin/bash
# Packages the built bundle as a Debian package for jailbroken devices (Cydia, Sileo, Filza,
# or `dpkg -i` over SSH). No dpkg tooling is needed on the Mac: the archive is assembled with
# Python. Output: dist/app.bennu.music_<version>_iphoneos-arm.deb and a zip of the bundle.
#
# Usage: scripts/package.sh            (version from Info.plist)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/native-player/ios/build/BennuMusic.app"
test -d "$APP" || { echo "Build first: scripts/build.sh" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
DIST="$ROOT_DIR/dist"
mkdir -p "$DIST"
python3 - "$APP" "$VERSION" "$DIST" <<'PY'
import io, os, sys, tarfile, time, zipfile
app, version, dist = sys.argv[1:4]
name = "app.bennu.music"

def tar_bytes(add):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tar:
        add(tar)
    return buf.getvalue()

def add_text(tar, path, text, mode=0o644):
    data = text.encode()
    info = tarfile.TarInfo(path); info.size = len(data); info.mode = mode; info.mtime = int(time.time())
    info.uname = info.gname = "root"
    tar.addfile(info, io.BytesIO(data))

installed = 0
def add_app(tar):
    global installed
    for root, dirs, files in os.walk(app):
        for f in sorted(files):
            full = os.path.join(root, f)
            rel = os.path.relpath(full, os.path.dirname(app))
            info = tar.gettarinfo(full, arcname="./Applications/" + rel)
            info.uname = info.gname = "root"; info.uid = info.gid = 0
            with open(full, "rb") as fh:
                tar.addfile(info, fh)
            installed += info.size

data = tar_bytes(add_app)
control_text = f"""Package: {name}
Name: Bennu Music
Version: {version}
Architecture: iphoneos-arm
Section: Multimedia
Priority: optional
Depends: firmware (>= 9.0), firmware (<< 11.0)
Installed-Size: {max(1, installed // 1024)}
Maintainer: Michel Carlos
Author: Michel Carlos
Homepage: https://github.com/micheldpcarlos/bennu-music
Description: Native Spotify player for jailbroken 32-bit iOS 9 devices.
 Spotify Connect receiver and standalone player with Home, Search, Library,
 queue, lock-screen controls and visualizations. Spotify Premium required.
"""
postinst = "#!/bin/sh\nuicache 2>/dev/null || /usr/bin/uicache 2>/dev/null || true\nexit 0\n"
postrm = "#!/bin/sh\nuicache 2>/dev/null || /usr/bin/uicache 2>/dev/null || true\nexit 0\n"
control = tar_bytes(lambda tar: (add_text(tar, "./control", control_text),
                                 add_text(tar, "./postinst", postinst, 0o755),
                                 add_text(tar, "./postrm", postrm, 0o755)))

def ar_entry(fname, payload):
    header = f"{fname:<16}{int(time.time()):<12}{0:<6}{0:<6}{'100644':<8}{len(payload):<10}`\n".encode()
    return header + payload + (b"\n" if len(payload) % 2 else b"")

deb = os.path.join(dist, f"{name}_{version}_iphoneos-arm.deb")
with open(deb, "wb") as out:
    out.write(b"!<arch>\n")
    out.write(ar_entry("debian-binary", b"2.0\n"))
    out.write(ar_entry("control.tar.gz", control))
    out.write(ar_entry("data.tar.gz", data))

zip_path = os.path.join(dist, f"BennuMusic-{version}.app.zip")
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(app):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, os.path.dirname(app)))
print(deb); print(zip_path)
PY
