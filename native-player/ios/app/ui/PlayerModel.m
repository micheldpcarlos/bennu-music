// SPDX-License-Identifier: GPL-3.0-or-later
#import "PlayerModel.h"
#import "CatalogClient.h"
NSString* const PhoenixPlayerChanged = @"PhoenixPlayerChanged";
@interface PlayerModel ()
@property(nonatomic) IPadPlayerSnapshot snapshot;
@property(nonatomic, copy) NSString* contextName;
@property(nonatomic, copy) NSString* contextUri;
@property(nonatomic) BOOL shuffle;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic, strong) CatalogRequest* contextRequest;
@property(nonatomic, strong) NSArray* queue;
@end
@implementation PlayerModel
+ (instancetype)shared {
  static PlayerModel* instance; static dispatch_once_t once;
  dispatch_once(&once, ^{ instance = [[PlayerModel alloc] init]; });
  return instance;
}
- (BOOL)ready { return self.snapshot.state == IPadReady; }
- (void)start {
  if (self.timer) return;
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
  [self refresh];
}
- (void)refresh {
  IPadPlayerSnapshot snapshot; memset(&snapshot, 0, sizeof snapshot);
  ipad_player_snapshot(&snapshot);
  self.snapshot = snapshot;
  [NSNotificationCenter.defaultCenter postNotificationName:PhoenixPlayerChanged object:self];
}
- (void)togglePause { ipad_player_command(IPadTogglePause); [self refresh]; }
- (void)next { ipad_player_command(IPadNext); [self refresh]; }
- (void)previous { ipad_player_command(IPadPrevious); [self refresh]; }
- (void)seekTo:(uint32_t)milliseconds { ipad_player_seek(milliseconds); [self refresh]; }
- (void)toggleShuffle { self.shuffle = !self.shuffle; [self refresh]; }
- (BOOL)playURIs:(NSArray*)uris index:(NSUInteger)index contextUri:(NSString*)uri contextName:(NSString*)name {
  if (uris.count == 0) return NO;
  NSDictionary* command = @{@"uris": uris, @"index": @(index), @"context": uri ?: @"", @"shuffle": @(self.shuffle)};
  NSData* data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
  NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!ipad_player_play_tracks(json.UTF8String)) return NO;
  self.contextUri = uri; self.contextName = name; self.queue = uris;
  [self refresh];
  return YES;
}
- (void)playContext:(NSString*)uri name:(NSString*)name shuffle:(BOOL)shuffle {
  self.shuffle = shuffle;
  __weak PlayerModel* weakSelf = self;
  self.contextRequest = [[CatalogClient shared] request:@"context" argument:uri update:^(NSDictionary* json, BOOL done) {
    NSArray* uris = json[@"uris"];
    if ([uris isKindOfClass:NSArray.class] && uris.count) [weakSelf playURIs:uris index:0 contextUri:uri contextName:name ?: json[@"name"]];
  }];
}
- (NSArray*)queueURIs { return self.queue ?: @[]; }
@end
