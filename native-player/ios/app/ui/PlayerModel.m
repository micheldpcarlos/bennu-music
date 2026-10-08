// SPDX-License-Identifier: GPL-3.0-or-later
#import "PlayerModel.h"
#import "CatalogClient.h"
#import "ImageCache.h"
#import <MediaPlayer/MediaPlayer.h>
NSString* const PhoenixPlayerChanged = @"PhoenixPlayerChanged";
@interface PlayerModel ()
@property(nonatomic) IPadPlayerSnapshot snapshot;
@property(nonatomic, copy) NSString* contextName;
@property(nonatomic, copy) NSString* contextUri;
@property(nonatomic) BOOL shuffle;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic, strong) CatalogRequest* contextRequest;
@property(nonatomic, strong) NSArray* queue;
@property(nonatomic, copy) NSString* infoTrackId;
@property(nonatomic, strong) UIImage* infoArtwork;
@property(nonatomic) BOOL infoPaused;
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
  // Lock screen, Control Center and headphone buttons.
  MPRemoteCommandCenter* commands = [MPRemoteCommandCenter sharedCommandCenter];
  [commands.playCommand addTarget:self action:@selector(remotePlay:)];
  [commands.pauseCommand addTarget:self action:@selector(remotePause:)];
  [commands.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle:)];
  [commands.nextTrackCommand addTarget:self action:@selector(remoteNext:)];
  [commands.previousTrackCommand addTarget:self action:@selector(remotePrevious:)];
  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
  [self refresh];
}
- (void)refresh {
  IPadPlayerSnapshot snapshot; memset(&snapshot, 0, sizeof snapshot);
  ipad_player_snapshot(&snapshot);
  self.snapshot = snapshot;
  [self updateNowPlayingInfo];
  [NSNotificationCenter.defaultCenter postNotificationName:PhoenixPlayerChanged object:self];
}
- (MPRemoteCommandHandlerStatus)remotePlay:(MPRemoteCommandEvent*)event { if (self.snapshot.paused) [self togglePause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePause:(MPRemoteCommandEvent*)event { if (!self.snapshot.paused) [self togglePause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteToggle:(MPRemoteCommandEvent*)event { [self togglePause]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remoteNext:(MPRemoteCommandEvent*)event { [self next]; return MPRemoteCommandHandlerStatusSuccess; }
- (MPRemoteCommandHandlerStatus)remotePrevious:(MPRemoteCommandEvent*)event { [self previous]; return MPRemoteCommandHandlerStatusSuccess; }
- (void)updateNowPlayingInfo {
  IPadPlayerSnapshot snapshot = self.snapshot;
  MPNowPlayingInfoCenter* center = [MPNowPlayingInfoCenter defaultCenter];
  if (!snapshot.hasTrack) { if (self.infoTrackId) { center.nowPlayingInfo = nil; self.infoTrackId = nil; self.infoArtwork = nil; } return; }
  NSString* trackId = @(snapshot.trackId);
  BOOL changed = ![trackId isEqualToString:self.infoTrackId] || snapshot.paused != self.infoPaused;
  if (changed) {
    self.infoTrackId = trackId; self.infoPaused = snapshot.paused;
    NSMutableDictionary* info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = @(snapshot.title);
    info[MPMediaItemPropertyArtist] = @(snapshot.artist);
    info[MPMediaItemPropertyAlbumTitle] = @(snapshot.album);
    info[MPMediaItemPropertyPlaybackDuration] = @(snapshot.durationMs / 1000.0);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(snapshot.positionMs / 1000.0);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(snapshot.paused ? 0.0 : 1.0);
    if (self.infoArtwork) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:self.infoArtwork];
    center.nowPlayingInfo = info;
    __weak PlayerModel* weakSelf = self;
    [[ImageCache shared] load:@(snapshot.artwork) completion:^(UIImage* image) {
      PlayerModel* owner = weakSelf;
      if (!image || !owner || ![owner.infoTrackId isEqualToString:trackId]) return;
      owner.infoArtwork = image;
      NSMutableDictionary* updated = [center.nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary];
      updated[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:image];
      center.nowPlayingInfo = updated;
    }];
  }
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
- (void)signOut {
  self.accountName = nil; self.accountImage = nil; self.contextName = nil; self.contextUri = nil; self.queue = nil;
  ipad_engine_stop();
  [self refresh];
}
@end
