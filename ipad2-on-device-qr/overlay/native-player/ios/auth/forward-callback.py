#!/usr/bin/env python3
"""Visible callback entry; forward to iPad without exchanging OAuth on the Mac."""
import argparse
import subprocess
from urllib.parse import urlsplit, parse_qs

# Fixed path; URL goes only through stdin, never into a remote shell command.
REMOTE = '''set -eu
umask 077
inbox=/var/mobile/Documents/phoenix-qr-inbox
mkdir -p "$inbox"
chown mobile:mobile "$inbox"
chmod 700 "$inbox"
temporary=$(mktemp "$inbox/.callback.XXXXXX")
trap 'rm -f "$temporary"' EXIT
cat > "$temporary"
chmod 600 "$temporary"
chown mobile:mobile "$temporary"
mv -f "$temporary" "$inbox/callback.txt"
'''

def validate(value):
    value = value.strip()
    if value.startswith('127.0.0.1:'):
        value = 'http://' + value
    if len(value.encode()) > 16384:
        raise ValueError('Callback is too long.')
    u = urlsplit(value)
    if (u.scheme != 'http' or u.hostname != '127.0.0.1' or u.port != 8765
            or u.path != '/callback' or u.username or u.password or u.fragment):
        raise ValueError('Expected the full 127.0.0.1:8765/callback address.')
    q = parse_qs(u.query, keep_blank_values=True)
    if any(len(v) != 1 for v in q.values()):
        raise ValueError('Duplicate callback parameters.')
    if not q.get('state', [''])[0] or bool(q.get('code', [''])[0]) == bool(q.get('error', [''])[0]):
        raise ValueError('Callback needs state and either code or error.')
    return value

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipad', default='192.168.13.24')
    args = parser.parse_args()
    print('Open Connect Spotify on the iPad and scan its QR with your phone.')
    print('After approval, the phone callback page will fail to load. Copy its FULL address.')
    print('Paste below. Text is VISIBLE. Do not share the callback or this terminal output.')
    try:
        value = validate(input('Final callback address: '))
        subprocess.run(['ssh', '-o', 'HostKeyAlgorithms=+ssh-rsa',
                        'root@' + args.ipad, REMOTE], input=value.encode(), check=True)
    except (ValueError, EOFError, KeyboardInterrupt):
        print('Callback not sent. Check the address and try again with the current iPad QR.')
        return 1
    except subprocess.CalledProcessError:
        print('SSH transfer failed. The callback was not confirmed delivered.')
        return 1
    print('Callback delivered. Watch the iPad for authentication and account storage status.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
