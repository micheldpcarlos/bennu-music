// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
// Development aid: drive the UI from SSH with `uiopen phoenix://...` and save screenshots to
// Documents/phoenix-screen.png. Harmless for users; no data leaves the device.
#ifdef __cplusplus
extern "C" {
#endif
BOOL PhoenixHandleURL(NSURL* url);
#ifdef __cplusplus
}
#endif
