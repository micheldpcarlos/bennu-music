#!/usr/bin/env python3
"""Apply only to the submitted source baseline; preserve unrelated local changes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from datetime import datetime, timezone

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def checked_path(root, relative):
    rel = Path(relative)
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError(f'Unsafe manifest path: {relative}')
    path = root / rel
    if not path.resolve().is_relative_to(root):
        raise ValueError(f'Path points outside project: {relative}')
    return path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path, help='ipad2MediaPlayer project root')
    parser.add_argument('--check', action='store_true', help='Validate without writing')
    args = parser.parse_args()
    root = args.project.resolve()
    bundle = Path(__file__).resolve().parent
    if not (root/'native-player/cspot/cspot/CMakeLists.txt').is_file():
        parser.error('Expected the project root containing native-player/cspot')
    manifest = json.loads((bundle/'manifest.json').read_text())
    pending, conflicts = [], []
    for entry in manifest['files']:
        target = checked_path(root, entry['path'])
        source = checked_path(bundle/'overlay', entry['path'])
        if digest(source) != entry['after_sha256']:
            raise SystemExit(f'Bundle integrity failure: {entry["path"]}')
        if target.exists() and not target.is_file():
            conflicts.append(entry['path']); continue
        current = digest(target) if target.exists() else None
        if current == entry['after_sha256']:
            continue
        if current != entry['before_sha256']:
            conflicts.append(entry['path']); continue
        pending.append((entry,target,source))
    lock = json.loads((bundle/'backport-header-hashes.json').read_text())
    for relative, expected in lock.items():
        path = checked_path(root,'native-player/compat/vendor/'+relative)
        if not path.is_file() or digest(path) != expected:
            conflicts.append('backport dependency: '+relative)
    if conflicts:
        print('No files changed. These files differ from the submitted snapshot:')
        for path in conflicts: print('  '+path)
        raise SystemExit(1)
    if args.check:
        print(f'Preflight passed; {len(pending)} files would be installed/updated.')
        return
    if not pending:
        print('Patch already applied; no files changed.')
        return
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-%f')
    backup = root/'native-player/port-backups'/stamp
    backup.mkdir(parents=True)
    (backup/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for entry,target,source in pending:
        # Recheck to avoid overwriting a file edited after preflight.
        current = digest(target) if target.exists() else None
        if current != entry['before_sha256']:
            raise SystemExit(f'File changed during application: {entry["path"]}. Backups: {backup}')
        if target.exists():
            saved = backup/entry['path']; saved.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(target,saved)
        target.parent.mkdir(parents=True,exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=target.name+'.port-',dir=target.parent)
        try:
            with os.fdopen(fd,'wb') as output: output.write(source.read_bytes())
            os.chmod(temporary,entry['mode'])
            os.replace(temporary,target)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
    print(f'Applied {len(pending)} files. Backups: {backup}')
    print('Next: source native-player/build-venv/bin/activate')
    print('      python -m pip install -r native-player/ios/requirements-build.txt')
    print('      bash native-player/ios/build-ipad.sh probe')

if __name__ == '__main__':
    main()
