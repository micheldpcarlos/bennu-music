// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
// Development aid: drive the UI from SSH with `uiopen bennu://...` and save screenshots to
// Documents/bennu-screen.png. Harmless for users; no data leaves the device.
#ifdef __cplusplus
extern "C" {
#endif
BOOL BennuHandleURL(NSURL* url);
#ifdef __cplusplus
}
#endif
