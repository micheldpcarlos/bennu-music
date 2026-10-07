#!/usr/bin/env python3
"""Apply the Catalog v2 to the exact supplied source snapshot."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('project', type=Path)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = args.project.resolve()
bundle = Path(__file__).resolve().parent
manifest = json.loads((bundle / 'manifest.json').read_text())
changes = []
def digest(data):
    return hashlib.sha256(data).hexdigest()
for entry in manifest:
    relative = Path(entry['path'])
    if relative.is_absolute() or '..' in relative.parts:
        raise SystemExit('Invalid patch path; no files changed.')
    target = root / relative
    if not target.resolve().is_relative_to(root):
        raise SystemExit('Target escapes project; no files changed: ' + str(relative))
    source = bundle / 'overlay' / relative
    content = source.read_bytes()
    if digest(content) != entry['after']:
        raise SystemExit('Patch checksum mismatch; no files changed: ' + str(relative))
    current = digest(target.read_bytes()) if target.is_file() else None
    if current == entry['after']:
        continue
    if current != entry['before'] or (target.exists() and not target.is_file()):
        raise SystemExit('Source differs from the supplied snapshot; no files changed: ' + str(relative))
    changes.append((target, relative, content))
if args.check:
    print(f'Preflight passed: {len(changes)} files would change.')
    raise SystemExit(0)
if not changes:
    print('Catalog v2 already applied.')
    raise SystemExit(0)
backup = root / 'native-player/port-backups' / ('catalog-v2-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
for target, relative, _ in changes:
    if target.exists():
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, saved)
for target, _, content in changes:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
print(f'Applied {len(changes)} files. Backups: {backup}')
print('Next: bash native-player/ios/auth/build-login-app.sh')
