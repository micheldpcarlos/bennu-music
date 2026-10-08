// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// One-tap visualization picker: families on the left, presets on the right, no modal sheets.
@interface VisualizerMenu : UIView
@property(nonatomic, copy) void (^onPick)(NSString* family, NSString* preset);
- (void)showIn:(UIView*)parent anchor:(UIView*)anchor selectedFamily:(NSString*)family preset:(NSString*)preset;
- (void)dismiss;
@end
