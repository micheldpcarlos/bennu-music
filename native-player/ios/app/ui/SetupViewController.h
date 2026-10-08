// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Account setup: sign in by scanning a code with the phone (device authorization), or pair
// through Spotify Connect. Presented from the account button on Home.
@interface SetupViewController : UIViewController
@property(nonatomic) BOOL welcome;   // first launch without an account: no close button, dismisses itself once connected
@end
