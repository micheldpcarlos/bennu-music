#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Phone QR authorization; callback pasted locally; token sent only over SSH stdin."""
import argparse, base64, getpass, hashlib, json, secrets, subprocess, tempfile, time
from pathlib import Path
from urllib.parse import urlencode, urlsplit, parse_qs
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
CLIENT='8686d6b87e484c50a6f9ab93bcc099e7'
REDIRECT='http://127.0.0.1:8765/callback'
SCOPES='streaming user-read-private playlist-read-private user-library-read'
def b64(data): return base64.urlsafe_b64encode(data).decode().rstrip('=')
def validate_callback(value,state):
 value=value.strip()
 if value.startswith('127.0.0.1:8765/'):
  value='http://'+value
 u=urlsplit(value)
 if u.scheme!='http' or u.netloc!='127.0.0.1:8765' or u.path!='/callback' or u.fragment:
  raise ValueError('Expected the full registered loopback callback address.')
 q=parse_qs(u.query,keep_blank_values=True)
 if any(len(v)!=1 for v in q.values()) or not secrets.compare_digest(q.get('state',[''])[0],state):
  raise ValueError('Callback state mismatch or duplicate parameters; restart authorization.')
 if q.get('error'): raise ValueError('Spotify authorization was denied.')
 if not q.get('code',[''])[0] or len(q['code'][0])>8192: raise ValueError('Callback has no valid code.')
 return q['code'][0]
def exchange(code,verifier):
 body=urlencode(dict(client_id=CLIENT,grant_type='authorization_code',code=code,
                    redirect_uri=REDIRECT,code_verifier=verifier)).encode()
 request=Request('https://accounts.spotify.com/api/token',data=body,
                 headers={'Content-Type':'application/x-www-form-urlencoded'},method='POST')
 with urlopen(request,timeout=20) as response: result=json.load(response)
 token=result.get('access_token')
 if not isinstance(token,str) or not token or len(token)>16384: raise ValueError('Invalid token response.')
 return token

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--ipad',default='192.168.13.24')
 args=parser.parse_args()
 if args.ipad.startswith('-') or any(c.isspace() for c in args.ipad): parser.error('Invalid iPad address')
 try: import qrcode
 except ImportError:
  print('Install the QR dependency: python -m pip install "qrcode[pil]>=8,<9"');return 2
 verifier=b64(secrets.token_bytes(32));state=secrets.token_urlsafe(24)
 url='https://accounts.spotify.com/authorize?'+urlencode(dict(client_id=CLIENT,
  response_type='code',redirect_uri=REDIRECT,scope=SCOPES,state=state,
  code_challenge_method='S256',code_challenge=b64(hashlib.sha256(verifier.encode()).digest())))
 with tempfile.TemporaryDirectory(prefix='ipad-qr-auth-') as temporary:
  image=Path(temporary)/'spotify-authorization.png'
  qrcode.make(url).save(image)
  print('Scan the QR code with your phone and authorize Spotify.')
  print('After approval, the phone cannot load 127.0.0.1. This is expected for this test.')
  print('Copy the FULL address from the phone browser, including its query parameters.')
  print('Paste it below on the Mac (Universal Clipboard works if configured). Input stays hidden.')
  subprocess.run(['open',str(image)],check=True)
  started=time.monotonic()
  input('Copy the final address to the Mac clipboard, then press Enter: ')
  callback=subprocess.check_output(['pbpaste']).decode('utf-8').strip()
  if not callback:
   print('Mac clipboard is empty. Copy the address onto the Mac and retry.')
   return 1
  if time.monotonic()-started>600: raise ValueError('Authorization test expired; rerun it.')
  try:
   code=validate_callback(callback,state)
  except ValueError:
   print('Clipboard callback is invalid or from another session. Use the new QR.')
   return 1
  print('Callback state verified. Exchanging code with PKCE…')
  token=exchange(code,verifier)
  print('OAuth token received. Starting iPad compatibility test over SSH…')
  # No credential file, shell interpolation, argv token, or token output.
  completed=subprocess.run(['ssh','-T','-o','HostKeyAlgorithms=+ssh-rsa',
      'root@'+args.ipad,'/tmp/cspot-token-test'],
      input=json.dumps({'access_token':token}).encode())
  return completed.returncode
if __name__=='__main__':
 try: raise SystemExit(main())
 except HTTPError as error: print('OAuth HTTP failure:',error.code);raise SystemExit(1)
 except URLError: print('OAuth network failure; no secrets printed.');raise SystemExit(1)
 except (ValueError, OSError, subprocess.SubprocessError):
  print('Test failed: callback validation, local command, or response failure. No secrets printed.');raise SystemExit(1)
 except (KeyboardInterrupt,EOFError): print('\nCancelled. No tokens saved.');raise SystemExit(130)
