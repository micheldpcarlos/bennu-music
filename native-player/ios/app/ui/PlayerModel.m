// SPDX-License-Identifier: GPL-3.0-or-later
#import "PlayerModel.h"
#import "CatalogClient.h"
#import "ImageCache.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
NSString* const BennuMusicChanged = @"BennuMusicChanged";
NSString* const BennuTrackChanged = @"BennuTrackChanged";
@interface PlayerModel ()
@property(nonatomic) IPadPlayerSnapshot snapshot;
@property(nonatomic, copy) NSString* contextName;
@property(nonatomic, copy) NSString* contextUri;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic) NSInteger pendingShuffle;   // -1: keep the engine's current shuffle for the next play
@property(nonatomic, strong) MPVolumeView* volumeView;   // off-screen; its slider is the only public way to set the system volume
@property(nonatomic) float appliedVolume;
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
- (int)repeat { return self.snapshot.repeat; }
- (BOOL)reconnecting { return self.snapshot.reconnecting != 0; }
- (void)cycleRepeat { ipad_player_set_repeat((self.snapshot.repeat + 1) % 3); [self refresh]; }
- (BOOL)addToQueue:(NSString*)uri {
  if (![uri isKindOfClass:NSString.class]) return NO;
  NSString* json = [NSString stringWithFormat:@"{\"uris\":[\"%@\"]}", uri];
  return ipad_player_queue_tracks(json.UTF8String) != 0;
}
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
  // Spotify Connect volume == system volume: report the current level and watch the hardware buttons.
  self.appliedVolume = AVAudioSession.sharedInstance.outputVolume;
  ipad_player_report_volume((uint32_t)lroundf(self.appliedVolume * 65535));
  [AVAudioSession.sharedInstance addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:NULL];
  self.pendingShuffle = -1;
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
  [self refresh];
}
- (void)refresh {
  IPadPlayerSnapshot snapshot; memset(&snapshot, 0, sizeof snapshot);
  ipad_player_snapshot(&snapshot);
  IPadPlayerSnapshot previous = self.snapshot;
  self.snapshot = snapshot;
  if (snapshot.volume != previous.volume) [self applySystemVolume:snapshot.volume / 65535.0f];
  [self updateNowPlayingInfo];
  [NSNotificationCenter.defaultCenter postNotificationName:BennuMusicChanged object:self];
  if (strcmp(previous.trackId, snapshot.trackId) != 0 || previous.paused != snapshot.paused || previous.state != snapshot.state ||
      previous.hasTrack != snapshot.hasTrack || previous.reconnecting != snapshot.reconnecting || previous.repeat != snapshot.repeat || previous.shuffle != snapshot.shuffle)
    [NSNotificationCenter.defaultCenter postNotificationName:BennuTrackChanged object:self];
}
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
  if (![keyPath isEqualToString:@"outputVolume"]) return;
  float level = [change[NSKeyValueChangeNewKey] floatValue];
  if (fabsf(level - self.appliedVolume) < 0.02f) return;   // our own change echoing back
  self.appliedVolume = level;
  ipad_player_report_volume((uint32_t)lroundf(level * 65535));
  fprintf(stderr, "VOLUME: system changed to %.2f, reported to Spotify\n", level);
}
- (void)applySystemVolume:(float)level {
  float current = AVAudioSession.sharedInstance.outputVolume;
  if (fabsf(level - current) < 0.02f) { self.appliedVolume = current; return; }
  if (!self.volumeView) {
    UIWindow* window = UIApplication.sharedApplication.keyWindow; if (!window) return;
    self.volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-2000, -2000, 120, 40)];
    self.volumeView.showsRouteButton = NO;
    [window addSubview:self.volumeView];
  }
  UISlider* slider = nil;
  for (UIView* view in self.volumeView.subviews) if ([view isKindOfClass:UISlider.class]) { slider = (UISlider*)view; break; }
  if (!slider) return;
  self.appliedVolume = level;
  [slider setValue:level animated:NO];
  [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
  fprintf(stderr, "VOLUME: phone set %.2f (system was %.2f)\n", level, current);
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
- (BOOL)shuffle { return self.snapshot.shuffle != 0; }
- (void)toggleShuffle { ipad_player_set_shuffle(self.shuffle ? 0 : 1); [self refresh]; }
- (BOOL)playURIs:(NSArray*)uris index:(NSUInteger)index contextUri:(NSString*)uri contextName:(NSString*)name {
  if (uris.count == 0) return NO;
  BOOL shuffle = self.pendingShuffle >= 0 ? self.pendingShuffle == 1 : self.shuffle;
  self.pendingShuffle = -1;
  NSDictionary* command = @{@"uris": uris, @"index": @(index), @"context": uri ?: @"", @"shuffle": @(shuffle)};
  NSData* data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
  NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!ipad_player_play_tracks(json.UTF8String)) return NO;
  self.contextUri = uri; self.contextName = name; self.queue = uris;
  [self refresh];
  return YES;
}
- (void)playContext:(NSString*)uri name:(NSString*)name shuffle:(BOOL)shuffle {
  self.pendingShuffle = shuffle ? 1 : 0;
  __weak PlayerModel* weakSelf = self;
  self.contextRequest = [[CatalogClient shared] request:@"context" argument:uri update:^(NSDictionary* json, BOOL done) {
    NSArray* uris = json[@"uris"];
    if ([uris isKindOfClass:NSArray.class] && uris.count) [weakSelf playURIs:uris index:0 contextUri:uri contextName:name ?: json[@"name"]];
  }];
}
- (NSArray*)queueURIs {
  static uint64_t lastRevision = 0; static NSArray* lastQueue = nil;
  char buffer[65536];
  uint64_t revision = ipad_player_queue(buffer, sizeof(buffer));
  if (!revision || !buffer[0]) return self.queue ?: @[];
  if (revision == lastRevision && lastQueue) return lastQueue;
  NSDictionary* json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:strlen(buffer)] options:0 error:nil];
  NSArray* uris = [json isKindOfClass:NSDictionary.class] ? json[@"uris"] : nil;
  if (![uris isKindOfClass:NSArray.class]) return self.queue ?: @[];
  lastRevision = revision; lastQueue = uris;
  return uris;
}
- (void)signOut {
  self.accountName = nil; self.accountImage = nil; self.contextName = nil; self.contextUri = nil; self.queue = nil;
  ipad_engine_stop();
  [self refresh];
}
@end
