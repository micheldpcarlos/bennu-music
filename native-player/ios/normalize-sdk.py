#!/usr/bin/env python3
"""Create a private SDK overlay; never edit or distribute Apple's SDK."""
import argparse
from pathlib import Path
import yaml

class Loader(yaml.SafeLoader):
    pass
Loader.add_multi_constructor('!tapi-tbd', lambda loader, tag, node: loader.construct_mapping(node, deep=True))

def normalize(text):
    documents = list(yaml.load_all(text, Loader=Loader))
    converted = []
    for doc in documents:
        if not isinstance(doc, dict) or 'archs' not in doc:
            raise ValueError('Expected an old archs/platform stub')
        if doc.get('platform') != 'ios':
            raise ValueError('Expected an iOS stub')
        if 'armv7' not in doc['archs']:
            continue
        doc['archs'] = ['armv7']
        for name in ('exports', 'undefineds', 're-exports'):
            if name in doc:
                sections = []
                for section in doc[name]:
                    if 'armv7' in section.get('archs', []):
                        section['archs'] = ['armv7']
                        sections.append(section)
                doc[name] = sections
        if doc.get('install-name') in ('/usr/lib/libSystem.B.dylib', '/usr/lib/libSystem.dylib'):
            exported = {s for e in doc.get('exports', [])
                        for s in e.get('symbols', [])}
            missing = [s for s in ('_memcmp', '_memcpy', '_memmove', '_memset', '_memchr', '_strchr', '_strcmp', '_strncmp')
                       if s not in exported]
            if missing:
                doc.setdefault('exports', []).append(
                    {'archs': ['armv7'], 'symbols': missing})
        converted.append(doc)
    # Old version-1 stubs use an untagged document. Retain that representation.
    return yaml.safe_dump_all(converted, explicit_start=True, explicit_end=True,
                              sort_keys=False) if converted else None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    destination = args.destination.resolve()
    if source == destination or source in destination.parents:
        parser.error('Destination must be outside the original SDK')
    if destination.exists():
        parser.error('Destination already exists; reuse it or choose a new directory')
    if not (source / 'usr/lib/libSystem.B.tbd').is_file():
        parser.error('Source is not the expected legacy iPhoneOS SDK')
    destination.mkdir(parents=True)
    count = 0
    try:
        for path in source.rglob('*'):
            target = destination / path.relative_to(source)
            if path.is_symlink() and path.is_dir():
                target.symlink_to(path.resolve(), target_is_directory=True)
            elif path.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif path.name.startswith('._'):
                continue
            elif path.suffix == '.tbd':
                text = normalize(path.read_text())
                if text:
                    target.write_text(text)
                    count += 1
            else:
                target.symlink_to(path.resolve())
        (destination / '.normalized-sdk-complete').write_text(str(source) + '\n')
    except Exception:
        print('Incomplete overlay: delete only the destination directory before retrying.')
        raise
    print(f'Created ARMv7 SDK overlay: {destination} ({count} stubs)')

if __name__ == '__main__':
    main()
