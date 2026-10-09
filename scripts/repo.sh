#!/bin/bash
# Builds the Cydia/Sileo repository for GitHub Pages and publishes it on the gh-pages branch.
# Layout: index.html, Release, Packages, Packages.gz, Packages.bz2, debs/<file>.deb
# Adding https://micheldpcarlos.github.io/bennu-music/ as a source then installs and updates
# the app like any other package. Run after scripts/package.sh.
#
# Usage: scripts/repo.sh            (uses every .deb under dist/)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT_DIR/dist"
WORK="$ROOT_DIR/build-repo"
URL="https://micheldpcarlos.github.io/bennu-music"
ls "$DIST"/*.deb >/dev/null 2>&1 || { echo "No .deb in dist/; run scripts/package.sh first" >&2; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK/debs"
cp "$DIST"/*.deb "$WORK/debs/"
python3 - "$WORK" "$URL" <<'PY'
import sys, os, io, tarfile, hashlib, gzip, bz2, time, glob
work, url = sys.argv[1:3]

def read_control(deb):
    # ar archive: control.tar.gz member holds ./control
    data = open(deb, "rb").read()
    assert data[:8] == b"!<arch>\n"
    pos = 8
    while pos + 60 <= len(data):
        name = data[pos:pos+16].decode().strip(); size = int(data[pos+48:pos+58].decode().strip()); body = data[pos+60:pos+60+size]
        pos += 60 + size + (size % 2)
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(body), mode="r:*") as tar:
                for m in tar.getmembers():
                    if m.name.endswith("control"):
                        return tar.extractfile(m).read().decode()
    raise SystemExit("no control in " + deb)

entries = []
for deb in sorted(glob.glob(os.path.join(work, "debs", "*.deb"))):
    control = read_control(deb).strip()
    raw = open(deb, "rb").read()
    entries.append(control + "\n" + f"Filename: debs/{os.path.basename(deb)}\nSize: {len(raw)}\nMD5sum: {hashlib.md5(raw).hexdigest()}\nSHA1: {hashlib.sha1(raw).hexdigest()}\nSHA256: {hashlib.sha256(raw).hexdigest()}\n")
packages = "\n".join(entries)
open(os.path.join(work, "Packages"), "w").write(packages)
open(os.path.join(work, "Packages.gz"), "wb").write(gzip.compress(packages.encode()))
open(os.path.join(work, "Packages.bz2"), "wb").write(bz2.compress(packages.encode()))
release = f"""Origin: Bennu Music
Label: Bennu Music
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm
Components: main
Description: Native Spotify player for jailbroken 32-bit iOS 9 devices
Date: {time.strftime('%a, %d %b %Y %H:%M:%S UTC', time.gmtime())}
"""
open(os.path.join(work, "Release"), "w").write(release)
open(os.path.join(work, "index.html"), "w").write(f"""<!doctype html><meta charset="utf-8"><title>Bennu Music repo</title>
<body style="font-family:-apple-system,Helvetica,sans-serif;background:#121212;color:#fff;padding:24px;max-width:640px">
<h1>Bennu Music</h1>
<p>Cydia / Sileo source for the native Spotify player for jailbroken 32-bit iOS 9 devices.</p>
<p>Add this URL as a source: <code>{url}/</code></p>
<p>Source and documentation: <a style="color:#1DB954" href="https://github.com/micheldpcarlos/bennu-music">github.com/micheldpcarlos/bennu-music</a></p>
<p><a style="color:#1DB954" href="cydia://url/https://cydia.saurik.com/api/share#?source={url}/">Add to Cydia</a> · <a style="color:#1DB954" href="sileo://source/{url}/">Add to Sileo</a></p>
</body>""")
open(os.path.join(work, ".nojekyll"), "w").write("")
print(f"{len(entries)} package(s) indexed")
PY
# Publish: replace the gh-pages branch contents with the repository files.
cd "$ROOT_DIR"
git fetch -q origin gh-pages 2>/dev/null || true
TMP_WT="$ROOT_DIR/build-repo-worktree"
rm -rf "$TMP_WT"
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
  git worktree add -q "$TMP_WT" origin/gh-pages
  (cd "$TMP_WT" && git checkout -q -B gh-pages)
else
  git worktree add -q --detach "$TMP_WT"
  (cd "$TMP_WT" && git checkout -q --orphan gh-pages && git rm -rfq . >/dev/null 2>&1 || true)
fi
rsync -a --delete --exclude .git "$WORK/" "$TMP_WT/"
(cd "$TMP_WT" && git add -A && (git commit -q -m "repo: $(ls "$WORK/debs" | tr '\n' ' ')" || true) && git push -q -f origin gh-pages)
git worktree remove --force "$TMP_WT"
echo "Published: $URL/"
