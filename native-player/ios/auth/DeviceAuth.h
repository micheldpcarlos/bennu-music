// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Spotify OAuth device-authorization flow (RFC 8628) with the desktop client id, which is
// the only kind of token login5 still accepts for playback credentials. The iPad shows a
// code and a QR to spotify.com/pair; the phone approves; the iPad exchanges the token for
// reusable AP credentials and stores them in the Keychain. Runs on its own thread.
int ipad_device_auth_start(void);
// JSON: {"state":"idle|requesting|waiting|verifying|done|failed","code":"ABCDEFGH","url":"https://spotify.com/pair?code=...",
//        "message":"...","expires_in":n}
uint32_t ipad_device_auth_status(char* output, uint32_t capacity);
void ipad_device_auth_cancel(void);
// Re-run only the credential exchange with the last approved token (kept in memory). 0 if none.
int ipad_device_auth_retry(void);
#ifdef __cplusplus
}
#endif
