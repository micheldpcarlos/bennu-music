# Security

## What the app stores

- Spotify credentials: the reusable credential blob Spotify issues after you approve the
  device-authorization code or pair from your phone. It is kept in the iOS Keychain under
  the app's own access group and never written to disk in clear text.
- Browsing cache: track metadata and cover art under `Documents/bennu-cache`. No tokens.
- Preferences: network visibility marker, last volume, last visualization. No tokens.

Catalog tokens (the session token used for browsing) live only in memory and are never
persisted.

## Reporting a vulnerability

Open a GitHub issue if the problem is not sensitive. If it involves credential exposure, or
anything an attacker on the same Wi-Fi could exploit (the app runs an HTTP pairing endpoint
when "Visible on this network" is on), email the maintainer at the address on the GitHub
profile instead of filing a public issue. Expect an answer within a week; this is a
one-person project.

## Scope notes

- The pairing endpoint is Spotify Connect's zeroconf protocol as implemented by cspot. It is
  reachable only on the local network and can be switched off in the app.
- The app talks to Spotify over TLS with Mbed TLS 3.6.7 and a pinned, vendored copy. There is
  no certificate pinning beyond the system trust store of iOS 9, which is old; keep that in
  mind on untrusted networks.
- iOS 9.3.5 itself no longer receives security updates. A jailbroken device on it should be
  treated as a music appliance, not as a device holding sensitive accounts.
