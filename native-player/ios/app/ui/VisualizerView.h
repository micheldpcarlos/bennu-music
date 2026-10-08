// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Full-screen audio visualizations in the spirit of Windows Media Player 9's collections:
// Alchemy, Ambience, Bars and Waves, Battery, Musical Colors, Particle, Plenoptic, Spikes.
@interface VisualizerView : UIView
+ (NSArray*)families;                                  // NSString names in menu order
+ (NSArray*)presetsForFamily:(NSString*)family;        // NSString preset names
- (void)startWithFamily:(NSString*)family preset:(NSString*)preset;
- (void)stop;
@property(nonatomic, copy) void (^onTouch)(void);
@end
