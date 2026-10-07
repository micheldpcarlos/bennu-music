#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Isolated catalog probe: authorize with the user's own Spotify app (PKCE, phone QR),
then make exactly one track search against the public Web API. Nothing touches the iPad.
Tokens stay in memory; nothing is saved or printed except HTTP status/track metadata."""
import argparse, base64, hashlib, json, secrets, subprocess, sys, tempfile, time
from pathlib import Path
from urllib.parse import urlencode, urlsplit, parse_qs, quote
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

CLIENT = '8686d6b87e484c50a6f9ab93bcc099e7'
REDIRECT = 'http://127.0.0.1:8765/callback'
SCOPES = 'user-read-private'          # search needs no scope; keep the grant minimal
SEARCH = 'https://api.spotify.com/v1/search'

def b64(data): return base64.urlsafe_b64encode(data).decode().rstrip('=')

def validate_callback(value, state):
    value = value.strip()
    if value.startswith('127.0.0.1:8765/'): value = 'http://' + value
    u = urlsplit(value)
    if u.scheme != 'http' or u.netloc != '127.0.0.1:8765' or u.path != '/callback' or u.fragment:
        raise ValueError('Expected the full registered loopback callback address.')
    q = parse_qs(u.query, keep_blank_values=True)
    if any(len(v) != 1 for v in q.values()) or not secrets.compare_digest(q.get('state', [''])[0], state):
        raise ValueError('Callback state mismatch or duplicate parameters; restart authorization.')
    if q.get('error'): raise ValueError('Spotify authorization was denied: ' + q['error'][0][:40])
    code = q.get('code', [''])[0]
    if not code or len(code) > 8192: raise ValueError('Callback has no valid code.')
    return code

def exchange(code, verifier):
    body = urlencode(dict(client_id=CLIENT, grant_type='authorization_code', code=code,
                          redirect_uri=REDIRECT, code_verifier=verifier)).encode()
    req = Request('https://accounts.spotify.com/api/token', data=body,
                  headers={'Content-Type': 'application/x-www-form-urlencoded'}, method='POST')
    with urlopen(req, timeout=20) as r: result = json.load(r)
    token = result.get('access_token')
    if not isinstance(token, str) or not token: raise ValueError('Invalid token response.')
    print('Token exchange: HTTP 200, scope=%r, expires_in=%s, refresh_token=%s'
          % (result.get('scope'), result.get('expires_in'), 'present' if result.get('refresh_token') else 'absent'))
    return token

def search(token, query):
    url = SEARCH + '?' + urlencode(dict(type='track', limit=10, q=query), quote_via=quote)
    req = Request(url, headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
    started = int(time.time())
    try:
        with urlopen(req, timeout=20) as r:
            payload = json.load(r); status = r.status
    except HTTPError as e:
        print('CATALOG PROBE: HTTP=%d epoch_seconds=%d retry_after=%s' % (e.code, started, e.headers.get('Retry-After')))
        try:
            err = json.load(e).get('error', {})
            print('  reason=%r message=%r' % (err.get('reason'), str(err.get('message'))[:120]))
        except Exception: pass
        return 1
    tracks = payload.get('tracks', {}).get('items', [])
    print('CATALOG PROBE: HTTP=%d epoch_seconds=%d tracks=%d' % (status, started, len(tracks)))
    for t in tracks:
        artists = ', '.join(a.get('name', '?') for a in t.get('artists', []))
        print('  %s — %s  [%s]' % (t.get('name'), artists, t.get('uri')))
    return 0 if tracks else 1

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--query', default='daft punk')
    ap.add_argument('--no-qr', action='store_true', help='print the URL instead of opening a QR image')
    args = ap.parse_args()
    verifier = b64(secrets.token_bytes(32)); state = secrets.token_urlsafe(24)
    url = 'https://accounts.spotify.com/authorize?' + urlencode(dict(
        client_id=CLIENT, response_type='code', redirect_uri=REDIRECT, scope=SCOPES, state=state,
        code_challenge_method='S256', code_challenge=b64(hashlib.sha256(verifier.encode()).digest())))
    if args.no_qr:
        print('Open this on the phone (or any browser logged into the Spotify account):\n' + url)
    else:
        try: import qrcode
        except ImportError:
            print('Install the QR dependency: python -m pip install "qrcode[pil]>=8,<9" (or use --no-qr)'); return 2
        tmp = tempfile.mkdtemp(prefix='ipad-search-probe-')
        image = Path(tmp) / 'spotify-authorization.png'
        qrcode.make(url).save(image); subprocess.run(['open', str(image)], check=True)
        print('Scan the QR with the phone and authorize.')
    print('After approval the browser fails to load 127.0.0.1. That is expected.')
    print('Copy the FULL final address (with ?code=...&state=...) and paste it here, visible:')
    started = time.monotonic()
    callback = input('> ')
    if not callback.strip():
        callback = subprocess.check_output(['pbpaste']).decode('utf-8', 'replace')
        print('(empty input; using the Mac clipboard)')
    if time.monotonic() - started > 600: raise ValueError('Authorization expired; rerun.')
    code = validate_callback(callback, state)
    print('Callback state verified. Exchanging code with PKCE...')
    token = exchange(code, verifier)
    print('One search request for %r ...' % args.query)
    return search(token, args.query)

if __name__ == '__main__':
    try: raise SystemExit(main())
    except HTTPError as e: print('OAuth HTTP failure:', e.code, e.read()[:200].decode('utf-8', 'replace')); raise SystemExit(1)
    except URLError as e: print('Network failure:', e.reason); raise SystemExit(1)
    except ValueError as e: print('Probe failed:', e); raise SystemExit(1)
    except (KeyboardInterrupt, EOFError): print('\nCancelled. No tokens saved.'); raise SystemExit(130)
