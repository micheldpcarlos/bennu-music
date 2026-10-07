# Playback-token checkpoint — 7 October 2026

On-device QR authorization succeeded. Saved-account connection has been intermittent. Spotify Connect subscription receives song selection and track metadata, but login5 playback-token requests fail repeatedly; playback remains blocked. Full saved-login persistence and QR-based playback are not yet verified.

This diagnostic patch adds HTTP status, checked protobuf decoding and login5 error numbers without logging response bodies, tokens, account identifiers or stored credentials. It removes the immediate four-request retry burst and rate-limits failed attempts. Failure cooldowns are 5 seconds for transport/decode errors, 15 seconds for HTTP errors, 60 seconds for HTTP 429, and 30 seconds for login5 errors. It does not change the login5 client ID or saved credentials. It also fixes the previously shadowed expiry variable and prevents returning expired tokens after a failed refresh.

Known login5 error numbers in the bundled schema: 1 invalid credentials, 2 bad request, 3 unsupported login protocol, 4 timeout, 5 unknown identifier, 6 too many attempts, 8 try again later. A decode failure can indicate a response shape the old minimal schema cannot handle. The diagnostic result is needed before choosing a credential/protocol fix. The existing five-second track-load timeout can still skip tracks while no playback token is available.

Build with `bash native-player/ios/auth/build-login-app.sh`, close the installed app, copy the rebuilt app to /Applications, chown mobile:mobile, run uicache, then open the icon and attempt one song. Collect PLAYBACK AUTH, AUTH and APP log lines. Do not reauthorize merely because playback-token acquisition fails: account login and playback tokens are separate stages.

Host tests passed: modified C++ syntax; actual login5 protobuf encoding/decoding with synthetic credentials; invalid credentials, malformed response, HTTP 429 and transport failure cooldowns; pending-flag recovery after exceptions; successful token caching, expiry and expired-token suppression; guarded installer reapplication/conflict rejection. Xcode build and device diagnostics remain pending.

The HTTPS callback relay remains a later step. It will replace manual callback transfer, not this playback-token path.
