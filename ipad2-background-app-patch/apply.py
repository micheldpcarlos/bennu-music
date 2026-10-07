#!/usr/bin/env python3
"""Install only the wrapper, preserving the user's current port fixes."""
from pathlib import Path
import argparse
import datetime
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('project', type=Path)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
project = args.project.resolve()
ios = project / 'native-player/ios'
cmake = ios / 'CMakeLists.txt'
if not cmake.is_file():
    raise SystemExit('Missing native-player/ios/CMakeLists.txt')
text = cmake.read_text()
for required in ('add_executable(cspot-ipad', 'CSPOT_ENABLE_IOS_SINK',
                 'MBEDTLS_PLATFORM_MS_TIME_ALT', 'libsystem_dnssd.tbd'):
    if required not in text:
        raise SystemExit('Required current port fix missing: ' + required)
include = 'include("${CMAKE_CURRENT_SOURCE_DIR}/app/application.cmake")'
source = Path(__file__).resolve().parent / 'app'
changes = []
for original in sorted(source.iterdir()):
    if not original.is_file():
        continue
    destination = ios / 'app' / original.name
    if destination.exists():
        if destination.read_bytes() != original.read_bytes():
            raise SystemExit('Existing wrapper file differs; preserved: ' + str(destination))
    else:
        changes.append((original, destination))
if args.check:
    print(f'Preflight passed: {len(changes)} new files; '
          f'CMake update needed: {include not in text}')
    raise SystemExit(0)
if include not in text:
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = project / 'native-player/port-backups' / ('background-app-' + stamp)
    backup.mkdir(parents=True)
    shutil.copy2(cmake, backup / 'CMakeLists.txt')
    cmake.write_text(text.rstrip() + '\n' + include + '\n')
    print('CMake backup:', backup)
for original, destination in changes:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(original, destination)
print('Wrapper installed; existing engine and SDK fixes preserved.')
print('Next: bash native-player/ios/app/build-app.sh')
