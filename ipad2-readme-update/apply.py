#!/usr/bin/env python3
"""Append/update a scoped README block, preserving all existing content."""
from pathlib import Path
import argparse
import datetime
import shutil

p = argparse.ArgumentParser()
p.add_argument('project', type=Path)
a = p.parse_args()
root = a.project.resolve()
if not (root / 'native-player/ios').is_dir():
    raise SystemExit('Expected the ipad2MediaPlayer project root.')
readme = root / 'README.md'
before = readme.read_text() if readme.exists() else '# iPad 2 Media Player\n'
block = (Path(__file__).resolve().parent / 'README-progress.md').read_text()
start = '<!-- ipad2-media-progress:start -->'
end = '<!-- ipad2-media-progress:end -->'
if start in before or end in before:
    if before.count(start) != 1 or before.count(end) != 1:
        raise SystemExit('Ambiguous progress markers; README preserved.')
    left, right = before.index(start), before.index(end) + len(end)
    if right <= left:
        raise SystemExit('Invalid progress block; README preserved.')
    after = before[:left] + block.rstrip() + before[right:]
else:
    after = before.rstrip() + '\n\n' + block
if after != before:
    if readme.exists():
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup = root / 'native-player/port-backups' / ('readme-' + stamp)
        backup.mkdir(parents=True)
        shutil.copy2(readme, backup / 'README.md')
    readme.write_text(after)
    print('Updated README.md; existing content preserved.')
else:
    print('README.md already up to date.')
