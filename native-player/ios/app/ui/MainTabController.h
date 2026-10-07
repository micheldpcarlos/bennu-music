// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Root of the app: Home / Search / Your Library tabs, a docked mini player, and modal Now Playing.
@interface MainTabController : UITabBarController
+ (instancetype)shared;
- (void)push:(UIViewController*)controller;   // push on the active tab's navigation stack
- (void)showNowPlaying;
@end
