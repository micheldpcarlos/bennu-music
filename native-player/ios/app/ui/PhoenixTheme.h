// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Spotify-like dark theme and vector icons drawn at runtime (iOS 9 has no symbol images).
@interface PhoenixTheme : NSObject
+ (UIColor*)background;      // #121212
+ (UIColor*)surface;         // #181818
+ (UIColor*)card;            // #282828
+ (UIColor*)cardHighlight;   // #333333
+ (UIColor*)green;           // #1DB954
+ (UIColor*)text;            // white
+ (UIColor*)subtext;         // #B3B3B3
+ (UIFont*)bold:(CGFloat)size;
+ (UIFont*)regular:(CGFloat)size;
// names: home search library play pause next previous shuffle repeat chevronDown chevronLeft heart more close account
+ (UIImage*)icon:(NSString*)name size:(CGFloat)size color:(UIColor*)color;
+ (UIImage*)placeholderArt:(CGFloat)size;      // gray square with a note
+ (UIImage*)likedSongsArt:(CGFloat)size;       // purple gradient with a heart
+ (UIButton*)pillButton:(NSString*)title;      // white pill with black bold text
+ (UIButton*)greenPlayButton:(CGFloat)diameter;
@end
NSString* PhoenixDuration(uint32_t milliseconds);
