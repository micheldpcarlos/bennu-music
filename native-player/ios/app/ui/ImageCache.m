// SPDX-License-Identifier: GPL-3.0-or-later
#import "ImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
static char kImageURLKey;
@interface ImageCache ()
@property(nonatomic, strong) NSCache* memory;
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic, copy) NSString* directory;
@property(nonatomic, strong) NSMutableDictionary* inFlight;  // url -> NSMutableArray of completions
@end
@implementation ImageCache
+ (instancetype)shared {
  static ImageCache* instance; static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[ImageCache alloc] init]; });
  return instance;
}
- (instancetype)init {
  if ((self = [super init])) {
    self.memory = [[NSCache alloc] init];
    self.memory.totalCostLimit = 24 * 1024 * 1024;  // iPad 2 has 512 MB; keep artwork modest
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 20; config.HTTPMaximumConnectionsPerHost = 4;
    self.session = [NSURLSession sessionWithConfiguration:config];
    NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.directory = [documents stringByAppendingPathComponent:@"phoenix-cache/images"];
    [NSFileManager.defaultManager createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:nil error:nil];
    self.inFlight = [NSMutableDictionary dictionary];
  }
  return self;
}
- (NSString*)pathFor:(NSString*)url {
  const char* bytes = url.UTF8String; unsigned char digest[CC_SHA1_DIGEST_LENGTH];
  CC_SHA1(bytes, (CC_LONG)strlen(bytes), digest);
  NSMutableString* name = [NSMutableString string];
  for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", digest[i]];
  return [self.directory stringByAppendingPathComponent:name];
}
- (BOOL)allowed:(NSURL*)url {
  if (![url.scheme isEqualToString:@"https"]) return NO;
  NSString* host = url.host ?: @"";
  return [host hasSuffix:@".scdn.co"] || [host hasSuffix:@".spotifycdn.com"] || [host hasSuffix:@".fbcdn.net"] || [host hasSuffix:@".spotify.com"];
}
- (void)load:(NSString*)url into:(UIImageView*)view placeholder:(UIImage*)placeholder {
  objc_setAssociatedObject(view, &kImageURLKey, url, OBJC_ASSOCIATION_COPY_NONATOMIC);
  UIImage* cached = url.length ? [self.memory objectForKey:url] : nil;
  if (cached) { view.image = cached; return; }
  view.image = placeholder;
  if (!url.length) return;
  __weak UIImageView* weakView = view;
  [self load:url completion:^(UIImage* image) {
    UIImageView* strongView = weakView;
    if (!image || !strongView) return;
    NSString* current = objc_getAssociatedObject(strongView, &kImageURLKey);
    if ([current isEqualToString:url]) strongView.image = image;
  }];
}
- (void)loadMosaic:(NSString*)url completion:(void (^)(UIImage*))completion {
  NSArray* ids = [[url substringFromIndex:15] componentsSeparatedByString:@":"];
  if (ids.count < 4) { completion(nil); return; }
  NSMutableArray* images = [NSMutableArray arrayWithObjects:[NSNull null], [NSNull null], [NSNull null], [NSNull null], nil];
  __block NSUInteger remaining = 4;
  __weak ImageCache* weakSelf = self;
  for (NSUInteger i = 0; i < 4; i++) {
    [self load:[@"https://i.scdn.co/image/" stringByAppendingString:ids[i]] completion:^(UIImage* image) {
      if (image) images[i] = image;
      if (--remaining) return;
      CGFloat size = 300;
      UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), YES, 1);
      [[UIColor colorWithWhite:0.16 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, size, size));
      for (NSUInteger j = 0; j < 4; j++)
        if (images[j] != [NSNull null]) [(UIImage*)images[j] drawInRect:CGRectMake((j % 2) * size / 2, (j / 2) * size / 2, size / 2, size / 2)];
      UIImage* mosaic = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
      [weakSelf.memory setObject:mosaic forKey:url cost:(NSUInteger)(size * size * 4)];
      completion(mosaic);
    }];
  }
}
- (void)load:(NSString*)url completion:(void (^)(UIImage*))completion {
  if (!url.length) { completion(nil); return; }
  UIImage* cached = [self.memory objectForKey:url];
  if (cached) { completion(cached); return; }
  if ([url hasPrefix:@"spotify:mosaic:"]) { [self loadMosaic:url completion:completion]; return; }
  NSURL* address = [NSURL URLWithString:url];
  if (![self allowed:address]) { completion(nil); return; }
  NSMutableArray* waiting = self.inFlight[url];
  if (waiting) { [waiting addObject:[completion copy]]; return; }
  self.inFlight[url] = [NSMutableArray arrayWithObject:[completion copy]];
  NSString* path = [self pathFor:url];
  __weak ImageCache* weakSelf = self;
  void (^finish)(UIImage*) = ^(UIImage* image) {
    dispatch_async(dispatch_get_main_queue(), ^{
      ImageCache* owner = weakSelf; if (!owner) return;
      if (image) [owner.memory setObject:image forKey:url cost:(NSUInteger)(image.size.width * image.size.height * 4)];
      NSArray* callbacks = owner.inFlight[url]; [owner.inFlight removeObjectForKey:url];
      for (void (^callback)(UIImage*) in callbacks) callback(image);
    });
  };
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    NSData* disk = [NSData dataWithContentsOfFile:path];
    UIImage* image = disk ? [UIImage imageWithData:disk] : nil;
    if (image) { finish(image); return; }
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:address];
    request.timeoutInterval = 20;
    [[weakSelf.session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
      UIImage* fetched = nil;
      NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
      if (!error && data.length > 0 && data.length < 3 * 1024 * 1024 && status == 200) {
        fetched = [UIImage imageWithData:data];
        if (fetched) [data writeToFile:path atomically:YES];
      }
      if (!fetched) fprintf(stderr, "IMG: %s failed status=%ld error=%ld %s\n", address.host.UTF8String, (long)status, (long)error.code, error.localizedDescription.UTF8String ?: "");
      finish(fetched);
    }] resume];
  });
}
@end
