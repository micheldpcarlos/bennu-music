// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
@interface MiniPlayerView : UIView
@property(nonatomic, copy) void (^onTap)(void);
@end
