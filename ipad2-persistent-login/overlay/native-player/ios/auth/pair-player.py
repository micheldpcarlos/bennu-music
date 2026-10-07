#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Phone QR authorization, verified reusable login, and player Keychain import handoff."""
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
  print('This version reads the Mac clipboard directly; it never prints the address.')
  subprocess.run(['open',str(image)],check=True)
  started=time.monotonic()
  getpass.getpass('Copy the final address to the Mac clipboard, then press Enter (do not paste here): ')
  callback=subprocess.check_output(['pbpaste']).decode('utf-8').strip()
  if not callback:
   print('The Mac clipboard is empty. Copy the address onto the Mac, then rerun.');return 1
  if time.monotonic()-started>600: raise ValueError('Authorization test expired; rerun it.')
  try:
   code=validate_callback(callback,state)
  except ValueError:
   u=urlsplit(callback if callback.startswith('http://') else 'http://'+callback)
   if u.netloc!='127.0.0.1:8765' or u.path!='/callback':
    print('Clipboard does not contain the callback address. Copy the entire final browser address.')
   else:
    print('Callback is incomplete, denied, or belongs to another QR session. Scan the newly generated QR.')
   return 1
  print('Callback state verified. Exchanging code with PKCE…')
  token=exchange(code,verifier)
  print('OAuth token received. Starting iPad compatibility test over SSH…')
  # No credential file, shell interpolation, argv token, or token output.
  completed=subprocess.run(['ssh','-T','-o','HostKeyAlgorithms=+ssh-rsa',
      'root@'+args.ipad,'/tmp/cspot-pairing --export-for-pairing'],
      input=json.dumps({'access_token':token}).encode(),stdout=subprocess.PIPE)
  output=completed.stdout.decode('utf-8',errors='replace')
  records=[]
  for line in output.splitlines():
   if line.startswith('PRIVATE_CREDENTIALS:'):
    records.append(line[len('PRIVATE_CREDENTIALS:'):])
   else: print(line)
  if completed.returncode or len(records)!=1:
   print('Pairing authentication failed. No credentials transferred.');return 1
  record=json.loads(records[0])
  credential=base64.b64decode(record.get('authData',''),validate=True)
  if record.get('authType') not in (1,2) or not isinstance(record.get('username'),str) or not 0<len(record['username'].encode())<=29 or not 0<len(credential)<=512:
   print('Invalid reusable credential response.');return 1
  data=json.dumps(record).encode()
  if len(data)>4095: print('Credential record too large.');return 1
  temporary_name='incoming-'+secrets.token_hex(16)
  # Temporary, permission-restricted handoff. The app imports it into Keychain
  # on launch and removes it only after a successful Keychain write.
  command=(
   'set -e; umask 077; '
   'dir=/var/mobile/Documents/phoenix-auth-inbox; '
   'test ! -L "$dir"; mkdir -p "$dir"; '
   'test ! -e "$dir/credentials.json"; '
   'chown root:wheel "$dir"; chmod 700 "$dir"; '
   'set -C; cat > "$dir/'+temporary_name+'"; '
   'chmod 600 "$dir/'+temporary_name+'"; '
   'mv "$dir/'+temporary_name+'" "$dir/credentials.json"; '
   'chown mobile:mobile "$dir/credentials.json" "$dir"'
  )
  transfer=subprocess.run(['ssh','-T','-o','HostKeyAlgorithms=+ssh-rsa','root@'+args.ipad,command],input=data)
  if transfer.returncode:
   print('Credential transfer failed. A prior pending import may already exist.');return 1
  print('PAIRING: credentials transferred. Open the updated iPad player to import them into Keychain.')
  print('They remain in a restricted temporary inbox until the app reports successful import.')
  return 0
if __name__=='__main__':
 try: raise SystemExit(main())
 except HTTPError as error: print('OAuth HTTP failure:',error.code);raise SystemExit(1)
 except URLError: print('OAuth network failure; no secrets printed.');raise SystemExit(1)
 except (ValueError, OSError, subprocess.SubprocessError):
  print('Test failed: callback validation, local command, or response failure. No secrets printed.');raise SystemExit(1)
 except (KeyboardInterrupt,EOFError): print('\nCancelled. Check whether a pending import was transferred before closing.');raise SystemExit(130)
