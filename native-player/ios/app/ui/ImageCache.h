// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Async artwork loading with a memory cache and a disk cache under Documents/phoenix-cache/images.
@interface ImageCache : NSObject
+ (instancetype)shared;
// Loads url into the image view (placeholder first). Safe to call repeatedly for reused cells:
// a late response for an older url is ignored.
- (void)load:(NSString*)url into:(UIImageView*)view placeholder:(UIImage*)placeholder;
- (void)load:(NSString*)url completion:(void (^)(UIImage* image))completion;
@end
