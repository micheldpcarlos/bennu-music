// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#import "../../PlayerBridge.h"
extern NSString* const PhoenixPlayerChanged;  // posted on the main thread 2x per second and after commands
@interface PlayerModel : NSObject
+ (instancetype)shared;
@property(nonatomic, readonly) IPadPlayerSnapshot snapshot;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, copy, readonly) NSString* contextName;   // what is playing from
@property(nonatomic, copy, readonly) NSString* contextUri;
@property(nonatomic, readonly) BOOL shuffle;
@property(nonatomic, copy) NSString* accountName;   // from the profile, set by Home
@property(nonatomic, copy) NSString* accountImage;  // profile picture url
- (void)signOut;
- (void)start;
- (void)refresh;
- (void)togglePause;
- (void)next;
- (void)previous;
- (void)seekTo:(uint32_t)milliseconds;
- (void)toggleShuffle;
- (void)cycleRepeat;            // off -> all -> one -> off
- (BOOL)addToQueue:(NSString*)uri;
@property(nonatomic, readonly) int repeat;
@property(nonatomic, readonly) BOOL reconnecting;
// Loads uris as the queue starting at index; contextName is shown in Now Playing.
- (BOOL)playURIs:(NSArray*)uris index:(NSUInteger)index contextUri:(NSString*)uri contextName:(NSString*)name;
// Resolves a context (album/playlist/artist/collection uri) and plays it.
- (void)playContext:(NSString*)uri name:(NSString*)name shuffle:(BOOL)shuffle;
- (NSArray*)queueURIs;
@end
