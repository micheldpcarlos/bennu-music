// SPDX-License-Identifier: GPL-3.0-or-later
#import "BennuTheme.h"
static UIColor* hex(unsigned value) {
  return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0 green:((value >> 8) & 0xff) / 255.0 blue:(value & 0xff) / 255.0 alpha:1];
}
NSString* BennuDuration(uint32_t milliseconds) {
  unsigned seconds = milliseconds / 1000;
  return [NSString stringWithFormat:@"%u:%02u", seconds / 60, seconds % 60];
}
@implementation BennuTheme
+ (UIColor*)background { return hex(0x121212); }
+ (UIColor*)surface { return hex(0x181818); }
+ (UIColor*)card { return hex(0x282828); }
+ (UIColor*)cardHighlight { return hex(0x333333); }
+ (UIColor*)green { return hex(0x1DB954); }
+ (UIColor*)text { return [UIColor whiteColor]; }
+ (UIColor*)subtext { return hex(0xB3B3B3); }
+ (UIFont*)bold:(CGFloat)size { return [UIFont boldSystemFontOfSize:size]; }
+ (UIFont*)regular:(CGFloat)size { return [UIFont systemFontOfSize:size]; }

static NSCache* drawnImages(void) {
  static NSCache* cache; static dispatch_once_t once;
  dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 200; });
  return cache;
}
+ (UIImage*)icon:(NSString*)name size:(CGFloat)size color:(UIColor*)color {
  NSString* key = [NSString stringWithFormat:@"icon:%@:%.1f:%@", name, size, color.description];
  UIImage* cached = [drawnImages() objectForKey:key];
  if (cached) return cached;
  UIImage* drawn = [self drawIcon:name size:size color:color];
  if (drawn) [drawnImages() setObject:drawn forKey:key];
  return drawn;
}
+ (UIImage*)drawIcon:(NSString*)name size:(CGFloat)size color:(UIColor*)color {
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
  CGContextRef context = UIGraphicsGetCurrentContext();
  [color setStroke]; [color setFill];
  CGFloat s = size, w = MAX(1.5, size / 12);  // stroke width scales with the icon
  UIBezierPath* path = [UIBezierPath bezierPath];
  path.lineWidth = w; path.lineCapStyle = kCGLineCapRound; path.lineJoinStyle = kCGLineJoinRound;
  if ([name isEqualToString:@"home"]) {
    [path moveToPoint:CGPointMake(s * 0.12, s * 0.5)]; [path addLineToPoint:CGPointMake(s * 0.5, s * 0.14)];
    [path addLineToPoint:CGPointMake(s * 0.88, s * 0.5)]; [path moveToPoint:CGPointMake(s * 0.22, s * 0.42)];
    [path addLineToPoint:CGPointMake(s * 0.22, s * 0.88)]; [path addLineToPoint:CGPointMake(s * 0.4, s * 0.88)];
    [path addLineToPoint:CGPointMake(s * 0.4, s * 0.62)]; [path addLineToPoint:CGPointMake(s * 0.6, s * 0.62)];
    [path addLineToPoint:CGPointMake(s * 0.6, s * 0.88)]; [path addLineToPoint:CGPointMake(s * 0.78, s * 0.88)];
    [path addLineToPoint:CGPointMake(s * 0.78, s * 0.42)]; [path stroke];
  } else if ([name isEqualToString:@"search"]) {
    [path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(s * 0.14, s * 0.14, s * 0.52, s * 0.52)]];
    [path moveToPoint:CGPointMake(s * 0.6, s * 0.6)]; [path addLineToPoint:CGPointMake(s * 0.86, s * 0.86)]; [path stroke];
  } else if ([name isEqualToString:@"library"]) {
    [path moveToPoint:CGPointMake(s * 0.2, s * 0.14)]; [path addLineToPoint:CGPointMake(s * 0.2, s * 0.86)];
    [path moveToPoint:CGPointMake(s * 0.4, s * 0.14)]; [path addLineToPoint:CGPointMake(s * 0.4, s * 0.86)];
    [path moveToPoint:CGPointMake(s * 0.58, s * 0.2)]; [path addLineToPoint:CGPointMake(s * 0.84, s * 0.84)]; [path stroke];
  } else if ([name isEqualToString:@"play"]) {
    [path moveToPoint:CGPointMake(s * 0.3, s * 0.18)]; [path addLineToPoint:CGPointMake(s * 0.84, s * 0.5)];
    [path addLineToPoint:CGPointMake(s * 0.3, s * 0.82)]; [path closePath]; [path fill];
  } else if ([name isEqualToString:@"pause"]) {
    [[UIBezierPath bezierPathWithRect:CGRectMake(s * 0.24, s * 0.18, s * 0.18, s * 0.64)] fill];
    [[UIBezierPath bezierPathWithRect:CGRectMake(s * 0.58, s * 0.18, s * 0.18, s * 0.64)] fill];
  } else if ([name isEqualToString:@"next"] || [name isEqualToString:@"previous"]) {
    BOOL next = [name isEqualToString:@"next"];
    CGContextSaveGState(context);
    if (!next) { CGContextTranslateCTM(context, s, 0); CGContextScaleCTM(context, -1, 1); }
    [path moveToPoint:CGPointMake(s * 0.18, s * 0.2)]; [path addLineToPoint:CGPointMake(s * 0.66, s * 0.5)];
    [path addLineToPoint:CGPointMake(s * 0.18, s * 0.8)]; [path closePath]; [path fill];
    [[UIBezierPath bezierPathWithRect:CGRectMake(s * 0.7, s * 0.2, s * 0.12, s * 0.6)] fill];
    CGContextRestoreGState(context);
  } else if ([name isEqualToString:@"shuffle"]) {
    [path moveToPoint:CGPointMake(s * 0.12, s * 0.3)]; [path addLineToPoint:CGPointMake(s * 0.32, s * 0.3)];
    [path addCurveToPoint:CGPointMake(s * 0.68, s * 0.7) controlPoint1:CGPointMake(s * 0.5, s * 0.3) controlPoint2:CGPointMake(s * 0.5, s * 0.7)];
    [path addLineToPoint:CGPointMake(s * 0.84, s * 0.7)];
    [path moveToPoint:CGPointMake(s * 0.12, s * 0.7)]; [path addLineToPoint:CGPointMake(s * 0.32, s * 0.7)];
    [path addCurveToPoint:CGPointMake(s * 0.68, s * 0.3) controlPoint1:CGPointMake(s * 0.5, s * 0.7) controlPoint2:CGPointMake(s * 0.5, s * 0.3)];
    [path addLineToPoint:CGPointMake(s * 0.84, s * 0.3)];
    [path moveToPoint:CGPointMake(s * 0.76, s * 0.22)]; [path addLineToPoint:CGPointMake(s * 0.86, s * 0.3)]; [path addLineToPoint:CGPointMake(s * 0.76, s * 0.38)];
    [path moveToPoint:CGPointMake(s * 0.76, s * 0.62)]; [path addLineToPoint:CGPointMake(s * 0.86, s * 0.7)]; [path addLineToPoint:CGPointMake(s * 0.76, s * 0.78)];
    [path stroke];
  } else if ([name isEqualToString:@"repeatOne"]) {
    [path moveToPoint:CGPointMake(s * 0.2, s * 0.56)]; [path addLineToPoint:CGPointMake(s * 0.2, s * 0.36)];
    [path addLineToPoint:CGPointMake(s * 0.8, s * 0.36)]; [path moveToPoint:CGPointMake(s * 0.7, s * 0.26)];
    [path addLineToPoint:CGPointMake(s * 0.82, s * 0.36)]; [path addLineToPoint:CGPointMake(s * 0.7, s * 0.46)];
    [path moveToPoint:CGPointMake(s * 0.8, s * 0.44)]; [path addLineToPoint:CGPointMake(s * 0.8, s * 0.64)];
    [path addLineToPoint:CGPointMake(s * 0.2, s * 0.64)]; [path moveToPoint:CGPointMake(s * 0.3, s * 0.54)];
    [path addLineToPoint:CGPointMake(s * 0.18, s * 0.64)]; [path addLineToPoint:CGPointMake(s * 0.3, s * 0.74)]; [path stroke];
    NSDictionary* attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:s * 0.34], NSForegroundColorAttributeName: color};
    [@"1" drawAtPoint:CGPointMake(s * 0.42, s * 0.3) withAttributes:attributes];
  } else if ([name isEqualToString:@"repeat"]) {
    [path moveToPoint:CGPointMake(s * 0.2, s * 0.56)]; [path addLineToPoint:CGPointMake(s * 0.2, s * 0.36)];
    [path addLineToPoint:CGPointMake(s * 0.8, s * 0.36)]; [path moveToPoint:CGPointMake(s * 0.7, s * 0.26)];
    [path addLineToPoint:CGPointMake(s * 0.82, s * 0.36)]; [path addLineToPoint:CGPointMake(s * 0.7, s * 0.46)];
    [path moveToPoint:CGPointMake(s * 0.8, s * 0.44)]; [path addLineToPoint:CGPointMake(s * 0.8, s * 0.64)];
    [path addLineToPoint:CGPointMake(s * 0.2, s * 0.64)]; [path moveToPoint:CGPointMake(s * 0.3, s * 0.54)];
    [path addLineToPoint:CGPointMake(s * 0.18, s * 0.64)]; [path addLineToPoint:CGPointMake(s * 0.3, s * 0.74)]; [path stroke];
  } else if ([name isEqualToString:@"chevronDown"]) {
    [path moveToPoint:CGPointMake(s * 0.2, s * 0.36)]; [path addLineToPoint:CGPointMake(s * 0.5, s * 0.66)];
    [path addLineToPoint:CGPointMake(s * 0.8, s * 0.36)]; [path stroke];
  } else if ([name isEqualToString:@"chevronLeft"]) {
    [path moveToPoint:CGPointMake(s * 0.64, s * 0.2)]; [path addLineToPoint:CGPointMake(s * 0.34, s * 0.5)];
    [path addLineToPoint:CGPointMake(s * 0.64, s * 0.8)]; [path stroke];
  } else if ([name isEqualToString:@"heart"]) {
    [path moveToPoint:CGPointMake(s * 0.5, s * 0.84)];
    [path addCurveToPoint:CGPointMake(s * 0.1, s * 0.36) controlPoint1:CGPointMake(s * 0.3, s * 0.68) controlPoint2:CGPointMake(s * 0.1, s * 0.56)];
    [path addCurveToPoint:CGPointMake(s * 0.5, s * 0.3) controlPoint1:CGPointMake(s * 0.1, s * 0.12) controlPoint2:CGPointMake(s * 0.42, s * 0.12)];
    [path addCurveToPoint:CGPointMake(s * 0.9, s * 0.36) controlPoint1:CGPointMake(s * 0.58, s * 0.12) controlPoint2:CGPointMake(s * 0.9, s * 0.12)];
    [path addCurveToPoint:CGPointMake(s * 0.5, s * 0.84) controlPoint1:CGPointMake(s * 0.9, s * 0.56) controlPoint2:CGPointMake(s * 0.7, s * 0.68)];
    [path closePath]; [path fill];
  } else if ([name isEqualToString:@"more"]) {
    for (int i = 0; i < 3; i++) [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(s * (0.18 + 0.26 * i), s * 0.44, s * 0.12, s * 0.12)] fill];
  } else if ([name isEqualToString:@"close"]) {
    [path moveToPoint:CGPointMake(s * 0.24, s * 0.24)]; [path addLineToPoint:CGPointMake(s * 0.76, s * 0.76)];
    [path moveToPoint:CGPointMake(s * 0.76, s * 0.24)]; [path addLineToPoint:CGPointMake(s * 0.24, s * 0.76)]; [path stroke];
  } else if ([name isEqualToString:@"visualizer"]) {
    CGFloat bars[] = {0.35, 0.7, 0.5, 0.85, 0.3};
    for (int i = 0; i < 5; i++) [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s * (0.12 + i * 0.16), s * (0.88 - bars[i] * 0.72), s * 0.1, s * bars[i] * 0.72) cornerRadius:s * 0.03] fill];
  } else if ([name isEqualToString:@"account"]) {
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(s * 0.32, s * 0.14, s * 0.36, s * 0.36)] fill];
    [path moveToPoint:CGPointMake(s * 0.14, s * 0.88)];
    [path addCurveToPoint:CGPointMake(s * 0.86, s * 0.88) controlPoint1:CGPointMake(s * 0.14, s * 0.52) controlPoint2:CGPointMake(s * 0.86, s * 0.52)];
    [path closePath]; [path fill];
  }
  UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}
+ (UIImage*)placeholderArt:(CGFloat)size {
  NSString* key = [NSString stringWithFormat:@"placeholder:%.0f", size];
  UIImage* cached = [drawnImages() objectForKey:key];
  if (cached) return cached;
  UIImage* drawn = [self drawPlaceholderArt:size];
  [drawnImages() setObject:drawn forKey:key];
  return drawn;
}
+ (UIImage*)drawPlaceholderArt:(CGFloat)size {
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 0);
  [[self card] setFill]; UIRectFill(CGRectMake(0, 0, size, size));
  NSDictionary* attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:size * 0.4], NSForegroundColorAttributeName: hex(0x535353)};
  NSString* note = @"♪"; CGSize text = [note sizeWithAttributes:attributes];
  [note drawAtPoint:CGPointMake((size - text.width) / 2, (size - text.height) / 2) withAttributes:attributes];
  UIImage* image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
+ (UIImage*)likedSongsArt:(CGFloat)size {
  NSString* key = [NSString stringWithFormat:@"liked:%.0f", size];
  UIImage* cached = [drawnImages() objectForKey:key];
  if (cached) return cached;
  UIImage* drawn = [self drawLikedSongsArt:size];
  [drawnImages() setObject:drawn forKey:key];
  return drawn;
}
+ (UIImage*)drawLikedSongsArt:(CGFloat)size {
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 0);
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGFloat components[] = {0.27, 0.04, 0.96, 1, 0.77, 0.94, 0.85, 1};
  CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
  CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(size, size), 0);
  CGGradientRelease(gradient); CGColorSpaceRelease(space);
  [[self icon:@"heart" size:size * 0.5 color:[UIColor whiteColor]] drawInRect:CGRectMake(size * 0.25, size * 0.25, size * 0.5, size * 0.5)];
  UIImage* image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
+ (UIButton*)pillButton:(NSString*)title {
  UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
  button.titleLabel.font = [self bold:14];
  button.backgroundColor = [UIColor whiteColor];
  button.layer.cornerRadius = 16;
  button.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
  return button;
}
+ (UIButton*)greenPlayButton:(CGFloat)diameter {
  UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.backgroundColor = [self green];
  button.layer.cornerRadius = diameter / 2;
  [button setImage:[self icon:@"play" size:diameter * 0.5 color:[UIColor blackColor]] forState:UIControlStateNormal];
  button.frame = CGRectMake(0, 0, diameter, diameter);
  return button;
}
@end
