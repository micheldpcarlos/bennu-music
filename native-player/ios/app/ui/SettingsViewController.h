// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Settings: audio quality, network visibility, storage, updates, diagnostics, about.
@interface SettingsViewController : UIViewController
+ (NSString*)appVersion;
+ (int)bitrate;                 // 96, 160 or 320 kbps; read by the engine launcher
- (void)checkForUpdates;        // also used by the dev URL
@end
