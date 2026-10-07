// SPDX-License-Identifier: GPL-3.0-or-later
#import "CatalogClient.h"
#import "../../PlayerBridge.h"
@interface CatalogRequest ()
@property(nonatomic) uint64_t identifier;
@property(nonatomic) uint64_t revision;
@property(nonatomic, copy) void (^update)(NSDictionary*, BOOL);
@end
@implementation CatalogRequest
- (void)cancel { self.update = nil; if (self.identifier) ipad_catalog_forget(self.identifier); self.identifier = 0; }
- (void)dealloc { [self cancel]; }
@end
@interface CatalogClient ()
@property(nonatomic, strong) NSMutableArray* pending;  // CatalogRequest (weak wrappers)
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic) char* buffer;
@end
static const uint32_t kBufferSize = 1024 * 1024;
@implementation CatalogClient
+ (instancetype)shared {
  static CatalogClient* instance; static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[CatalogClient alloc] init]; });
  return instance;
}
- (instancetype)init {
  if ((self = [super init])) { self.pending = [NSMutableArray array]; self.buffer = malloc(kBufferSize); }
  return self;
}
- (CatalogRequest*)request:(NSString*)kind argument:(NSString*)argument update:(void (^)(NSDictionary*, BOOL))update {
  CatalogRequest* request = [[CatalogRequest alloc] init];
  request.update = update;
  request.identifier = ipad_catalog_request(kind.UTF8String, argument.UTF8String ?: "");
  if (!request.identifier) {
    dispatch_async(dispatch_get_main_queue(), ^{ if (request.update) request.update(@{@"error": @"The player is not connected yet."}, YES); });
    return request;
  }
  [self.pending addObject:[NSValue valueWithNonretainedObject:request]];
  if (!self.timer) self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(poll) userInfo:nil repeats:YES];
  return request;
}
- (void)poll {
  NSMutableArray* finished = [NSMutableArray array];
  for (NSValue* box in [self.pending copy]) {
    CatalogRequest* request = box.nonretainedObjectValue;
    // The owner released the request (screen closed) or cancelled it.
    if (!request || !request.identifier || !request.update) { [finished addObject:box]; continue; }
    int done = 0;
    uint64_t revision = ipad_catalog_poll(request.identifier, request.revision, self.buffer, kBufferSize, &done);
    if (!revision) continue;
    request.revision = revision;
    NSData* data = [NSData dataWithBytesNoCopy:self.buffer length:strlen(self.buffer) freeWhenDone:NO];
    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSDictionary.class]) json = @{@"error": @"Unreadable response."};
    request.update(json, done != 0);
    if (done) { [finished addObject:box]; ipad_catalog_forget(request.identifier); request.identifier = 0; }
  }
  [self.pending removeObjectsInArray:finished];
  if (self.pending.count == 0) { [self.timer invalidate]; self.timer = nil; }
}
@end
