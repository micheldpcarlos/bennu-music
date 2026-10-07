#!/usr/bin/env python3
"""Instrument the current app without changing playback or power policy."""
from pathlib import Path
import argparse
import datetime
import shutil

p = argparse.ArgumentParser()
p.add_argument('project', type=Path)
p.add_argument('--check', action='store_true')
a = p.parse_args()
root = a.project.resolve()
ios = root / 'native-player/ios'
sink = ios / 'IOSAudioQueueSink.cpp'
cli = root / 'native-player/cspot/targets/cli/CliPlayer.cpp'
cmake = ios / 'app/application.cmake'
for path in (sink, cli, cmake):
    if not path.is_file():
        raise SystemExit('Required current app file missing: ' + str(path))
updates = {}
def replace_once(text, old, new, path):
    if text.count(old) != 1:
        raise SystemExit('Unexpected source marker; no files changed: ' + str(path))
    return text.replace(old, new, 1)

s = sink.read_text()
if 'ipad_metrics::startReporter()' not in s:
    s = '#include "PlaybackMetrics.h"\n' + s
    s = replace_once(s, '  std::puts("iPad AudioQueue ready:',
        '  ipad_metrics::startReporter();\n  std::puts("iPad AudioQueue ready:', sink)
    s = replace_once(s, '  auto* self = static_cast<IOSAudioQueueSink*>(context);',
        '  ipad_metrics::consumed(buffer->mAudioDataByteSize);\n'
        '  auto* self = static_cast<IOSAudioQueueSink*>(context);', sink)
    s = replace_once(s, '      ready.wait(lock, [this] {',
        '      ipad_metrics::waiting(true);\n      ready.wait(lock, [this] {', sink)
    s = replace_once(s, '      if (stopped) throw std::runtime_error("AudioQueue is stopped");',
        '      ipad_metrics::waiting(false);\n'
        '      if (stopped) throw std::runtime_error("AudioQueue is stopped");', sink)
    s = replace_once(s, '    if (!started) {',
        '    ipad_metrics::enqueued(count);\n    if (!started) {', sink)
updates[sink] = s.encode()

c = cli.read_text()
if 'ipad_metrics::decoded(written)' not in c:
    c = '#ifdef CSPOT_ENABLE_IOS_SINK\n#include "PlaybackMetrics.h"\n#endif\n' + c
    c = replace_once(c, '        return this->centralAudioBuffer->writePCM(data, bytes, hash);',
        '        size_t written = this->centralAudioBuffer->writePCM(data, bytes, hash);\n'
        '#ifdef CSPOT_ENABLE_IOS_SINK\n        ipad_metrics::decoded(written);\n#endif\n'
        '        return written;', cli)
    c = replace_once(c, '    if (!chunk || chunk->pcmSize == 0) {',
        '    if (!chunk || chunk->pcmSize == 0) {\n'
        '#ifdef CSPOT_ENABLE_IOS_SINK\n      ipad_metrics::emptyRead();\n#endif', cli)
updates[cli] = c.encode()

cm = cmake.read_text()
addition = '''# Playback diagnostics shared by the command-line and app executables.
target_sources(cspot-ipad PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/PlaybackMetrics.cpp")
target_sources(ipad-media-app PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/PlaybackMetrics.cpp")
'''
if addition not in cm:
    cm = cm.rstrip() + '\n' + addition
updates[cmake] = cm.encode()

for source in sorted((Path(__file__).resolve().parent / 'files').iterdir()):
    destination = ios / source.name
    content = source.read_bytes()
    if destination.exists() and destination.read_bytes() != content:
        raise SystemExit('Existing metrics file differs; preserved: ' + str(destination))
    updates[destination] = content
changes = [(path, content) for path, content in updates.items()
           if not path.exists() or path.read_bytes() != content]
if a.check:
    print(f'Preflight passed: {len(changes)} files would change.')
    raise SystemExit(0)
if changes:
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = root / 'native-player/port-backups' / ('metrics-' + stamp)
    for path, content in changes:
        if path.exists():
            saved = backup / path.relative_to(root)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print('Applied metrics. Backups:', backup)
else:
    print('Metrics already applied.')
print('Next: bash native-player/ios/app/build-app.sh')
