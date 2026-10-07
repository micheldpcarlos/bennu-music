#!/usr/bin/env python3
"""Use AVAudioSession for the app while preserving the tested CLI path."""
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
app = ios / 'app/AppMain.mm'
cmake = ios / 'app/application.cmake'
for file in (sink, app, cmake):
    if not file.is_file():
        raise SystemExit('Required app file missing: ' + str(file))
def once(text, old, new, path):
    if text.count(old) != 1:
        raise SystemExit('Unexpected source marker; no files changed: ' + str(path))
    return text.replace(old, new, 1)
updates = {}
s = sink.read_text()
if 'bool ipadAppActivateAudioSession();' not in s:
    s = '#ifdef CSPOT_IOS_APP\nbool ipadAppActivateAudioSession();\nvoid ipadAppDeactivateAudioSession();\n#endif\n' + s
    s = once(s, '    AudioSessionSetActive(false);',
        '#ifdef CSPOT_IOS_APP\n    ipadAppDeactivateAudioSession();\n#else\n'
        '    AudioSessionSetActive(false);\n#endif', sink)
    start = s.find('  static const OSStatus initialized = AudioSessionInitialize(')
    end = s.find('  sessionActive = true;', start)
    if start < 0 or end < 0:
        raise SystemExit('Unexpected session setup; no files changed.')
    legacy = s[start:end]
    tail = s[end:]
    s = (s[:start] + '#ifdef CSPOT_IOS_APP\n'
         + '  if (!ipadAppActivateAudioSession()) return false;\n#else\n'
         + legacy + '#endif\n' + tail)
updates[sink] = s.encode()

t = app.read_text()
if '#include "AppAudioSession.inc"' not in t:
    t = '#include "AppAudioSession.inc"\n' + t
    t = once(t, '@implementation IPadPlayerDelegate',
        '@implementation IPadPlayerDelegate\n'
        '- (void)audioSessionEvent:(NSNotification*)notification {\n'
        '  std::fprintf(stderr, "SESSION: notification=%s info=%s\\n",\n'
        '      notification.name.UTF8String, notification.userInfo.description.UTF8String);\n'
        '  ipadLogAudioSession();\n}\n', app)
    t = once(t, '  pthread_t worker;',
        '  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;\n'
        '  [center addObserver:self selector:@selector(audioSessionEvent:)\n'
        '      name:AVAudioSessionInterruptionNotification object:nil];\n'
        '  [center addObserver:self selector:@selector(audioSessionEvent:)\n'
        '      name:AVAudioSessionRouteChangeNotification object:nil];\n'
        '  pthread_t worker;', app)
    for state in ('entered background', 'became active'):
        marker = '  std::fprintf(stderr, "APP: ' + state + '\\n");'
        t = once(t, marker, marker + '\n  ipadLogAudioSession();', app)
updates[app] = t.encode()

cm = cmake.read_text()
if 'CSPOT_IOS_APP=1' not in cm:
    cm = once(cm, 'target_compile_definitions(ipad-media-app PRIVATE CSPOT_ENABLE_IOS_SINK=1)',
        'target_compile_definitions(ipad-media-app PRIVATE CSPOT_ENABLE_IOS_SINK=1 CSPOT_IOS_APP=1)', cmake)
    cm = once(cm, '"-framework UIKit"', '"-framework UIKit" "-framework AVFoundation"', cmake)
    cm = once(cm, 'DEPENDS "${IPAD_APP_DIR}/AppMain.mm"',
        'DEPENDS "${IPAD_APP_DIR}/AppMain.mm" "${IPAD_APP_DIR}/AppAudioSession.inc"', cmake)
updates[cmake] = cm.encode()
source = Path(__file__).resolve().parent / 'files/AppAudioSession.inc'
destination = ios / 'app/AppAudioSession.inc'
content = source.read_bytes()
if destination.exists() and destination.read_bytes() != content:
    raise SystemExit('Existing session adapter differs; preserved: ' + str(destination))
updates[destination] = content
changes = [(path, content) for path, content in updates.items()
           if not path.exists() or path.read_bytes() != content]
if a.check:
    print(f'Preflight passed: {len(changes)} files would change.')
    raise SystemExit(0)
if changes:
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = root / 'native-player/port-backups' / ('audio-session-' + stamp)
    for path, content in changes:
        if path.exists():
            saved = backup / path.relative_to(root)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
        path.write_bytes(content)
    print('Applied AVAudioSession adapter. Backups:', backup)
else:
    print('AVAudioSession adapter already applied.')
print('Next: bash native-player/ios/app/build-app.sh')
