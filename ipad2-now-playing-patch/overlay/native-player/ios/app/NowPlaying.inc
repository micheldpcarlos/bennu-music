// SPDX-License-Identifier: GPL-3.0-or-later
#include "../PlayerBridge.h"

static NSString* playerText(const char* text) {
  NSString* value = text ? [NSString stringWithUTF8String:text] : nil;
  return value ?: @"";
}
static NSString* playerTime(uint32_t ms) {
  unsigned seconds = ms / 1000;
  return [NSString stringWithFormat:@"%u:%02u", seconds / 60, seconds % 60];
}

@interface NowPlayingController : UIViewController
@property(nonatomic, strong) UILabel* heading;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* artistLabel;
@property(nonatomic, strong) UILabel* albumLabel;
@property(nonatomic, strong) UILabel* elapsedLabel;
@property(nonatomic, strong) UILabel* durationLabel;
@property(nonatomic, strong) UILabel* message;
@property(nonatomic, strong) UILabel* placeholder;
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UIProgressView* progress;
@property(nonatomic, strong) UIButton* previousButton;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) UIButton* nextButton;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic, strong) NSURLSessionDataTask* imageTask;
@property(nonatomic, copy) NSString* imageURL;
@end

@implementation NowPlayingController
- (UILabel*)labelWithSize:(CGFloat)size color:(UIColor*)color {
  UILabel* label = [[UILabel alloc] initWithFrame:CGRectZero];
  label.font = [UIFont systemFontOfSize:size];
  label.textColor = color;
  label.numberOfLines = 1;
  [self.view addSubview:label];
  return label;
}
- (UIButton*)button:(NSString*)text action:(SEL)action {
  UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:text forState:UIControlStateNormal];
  button.titleLabel.font = [UIFont systemFontOfSize:26];
  button.tintColor = UIColor.whiteColor;
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:button];
  return button;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
  UIColor* secondary = [UIColor colorWithWhite:0.65 alpha:1];
  self.heading = [self labelWithSize:16 color:secondary];
  self.heading.text = @"NOW PLAYING";
  self.status = [self labelWithSize:14 color:secondary];
  self.status.textAlignment = NSTextAlignmentRight;
  self.titleLabel = [self labelWithSize:34 color:UIColor.whiteColor];
  self.titleLabel.font = [UIFont boldSystemFontOfSize:34];
  self.titleLabel.numberOfLines = 2;
  self.artistLabel = [self labelWithSize:23 color:secondary];
  self.albumLabel = [self labelWithSize:17 color:secondary];
  self.elapsedLabel = [self labelWithSize:14 color:secondary];
  self.durationLabel = [self labelWithSize:14 color:secondary];
  self.durationLabel.textAlignment = NSTextAlignmentRight;
  self.message = [self labelWithSize:16 color:secondary];
  self.message.numberOfLines = 2;
  self.message.textAlignment = NSTextAlignmentCenter;
  self.artwork = [[UIImageView alloc] initWithFrame:CGRectZero];
  self.artwork.contentMode = UIViewContentModeScaleAspectFit;
  self.artwork.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
  [self.view addSubview:self.artwork];
  self.placeholder = [self labelWithSize:100 color:[UIColor colorWithWhite:0.3 alpha:1]];
  self.placeholder.text = @"♪";
  self.placeholder.textAlignment = NSTextAlignmentCenter;
  self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  self.progress.progressTintColor = [UIColor colorWithRed:0.12 green:0.8 blue:0.36 alpha:1];
  self.progress.trackTintColor = [UIColor colorWithWhite:0.2 alpha:1];
  [self.view addSubview:self.progress];
  self.previousButton = [self button:@"|◀" action:@selector(previous)];
  self.playButton = [self button:@"Play" action:@selector(togglePause)];
  self.nextButton = [self button:@"▶|" action:@selector(next)];
  self.previousButton.accessibilityLabel = @"Previous track";
  self.nextButton.accessibilityLabel = @"Next track";
  self.playButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.7 blue:0.31 alpha:1];
  self.playButton.layer.cornerRadius = 32;
  self.playButton.titleLabel.font = [UIFont boldSystemFontOfSize:22];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(applicationInactive:)
      name:UIApplicationWillResignActiveNotification object:nil];
  [center addObserver:self selector:@selector(applicationActive:)
      name:UIApplicationDidBecomeActiveNotification object:nil];
  [self render];
}
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self startUpdates];
}
- (void)viewWillDisappear:(BOOL)animated {
  [self stopUpdates];
  [super viewWillDisappear:animated];
}
- (void)dealloc {
  [self.timer invalidate];
  [self.imageTask cancel];
  [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)applicationInactive:(NSNotification*)notification { (void)notification; [self stopUpdates]; }
- (void)applicationActive:(NSNotification*)notification { (void)notification; [self startUpdates]; }
- (void)timerFired:(NSTimer*)timer { (void)timer; [self render]; }
- (void)startUpdates {
  if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
  [self render];
  if (!self.timer) self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
      target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];
}
- (void)stopUpdates {
  [self.timer invalidate];
  self.timer = nil;
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  CGFloat height = self.view.bounds.size.height;
  const CGFloat margin = 40;
  self.heading.frame = CGRectMake(margin, 38, width / 2 - margin, 24);
  self.status.frame = CGRectMake(width / 2, 38, width / 2 - margin, 24);
  BOOL landscape = width > height;
  CGFloat artSize = landscape ? MIN(width * 0.43, height - 210) : MIN(width - 100, height * 0.37);
  CGFloat artY = landscape ? (height - artSize) / 2 : 108;
  self.artwork.frame = CGRectMake(landscape ? margin : (width - artSize) / 2, artY, artSize, artSize);
  self.placeholder.frame = self.artwork.frame;
  CGFloat x = landscape ? margin + artSize + 40 : margin;
  CGFloat y = landscape ? artY + 10 : artY + artSize + 24;
  CGFloat contentWidth = width - x - margin;
  self.titleLabel.frame = CGRectMake(x, y, contentWidth, 88);
  self.artistLabel.frame = CGRectMake(x, y + 96, contentWidth, 32);
  self.albumLabel.frame = CGRectMake(x, y + 138, contentWidth, 24);
  self.progress.frame = CGRectMake(x, y + 195, contentWidth, 4);
  self.elapsedLabel.frame = CGRectMake(x, y + 210, contentWidth / 2, 24);
  self.durationLabel.frame = CGRectMake(x + contentWidth / 2, y + 210, contentWidth / 2, 24);
  CGFloat buttonCenter = x + contentWidth / 2;
  self.previousButton.frame = CGRectMake(buttonCenter - 150, y + 254, 70, 64);
  self.playButton.frame = CGRectMake(buttonCenter - 64, y + 254, 128, 64);
  self.nextButton.frame = CGRectMake(buttonCenter + 80, y + 254, 70, 64);
  self.message.frame = CGRectMake(margin, height - 94, width - 2 * margin, 66);
}
- (void)loadArtwork:(NSString*)url {
  if ([url isEqualToString:self.imageURL]) return;
  self.imageURL = url;
  [self.imageTask cancel];
  self.imageTask = nil;
  self.artwork.image = nil;
  self.placeholder.hidden = NO;
  NSURL* address = [NSURL URLWithString:url];
  if (![address.scheme isEqualToString:@"https"] || ![address.host isEqualToString:@"i.scdn.co"]) return;
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:address];
  request.timeoutInterval = 15;
  __weak NowPlayingController* weakSelf = self;
  self.imageTask = [NSURLSession.sharedSession dataTaskWithRequest:request
      completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    if (error || data.length == 0 || data.length > 2 * 1024 * 1024) return;
    if ([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse*)response).statusCode != 200) return;
    UIImage* image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      NowPlayingController* owner = weakSelf;
      if (owner && [owner.imageURL isEqualToString:url]) {
        owner.artwork.image = image;
        owner.placeholder.hidden = YES;
      }
    });
  }];
  [self.imageTask resume];
}
- (void)render {
  IPadPlayerSnapshot snapshot{};
  ipad_player_snapshot(&snapshot);
  BOOL ready = snapshot.state == IPadReady;
  BOOL enabled = ready && snapshot.hasTrack && !snapshot.loading && !snapshot.pending;
  self.previousButton.enabled = enabled;
  self.playButton.enabled = enabled;
  self.nextButton.enabled = enabled;
  self.previousButton.alpha = enabled ? 1 : 0.3;
  self.playButton.alpha = enabled ? 1 : 0.3;
  self.nextButton.alpha = enabled ? 1 : 0.3;
  [self.playButton setTitle:snapshot.paused ? @"Play" : @"Pause" forState:UIControlStateNormal];
  self.playButton.accessibilityLabel = snapshot.paused ? @"Resume playback" : @"Pause playback";
  self.titleLabel.text = snapshot.hasTrack ? playerText(snapshot.title) : @"iPad Media Player";
  self.artistLabel.text = snapshot.hasTrack ? playerText(snapshot.artist) : @"Your music, on this iPad";
  self.albumLabel.text = snapshot.hasTrack ? playerText(snapshot.album) : @"";
  self.elapsedLabel.text = playerTime(snapshot.hasTrack ? snapshot.positionMs : 0);
  self.durationLabel.text = playerTime(snapshot.hasTrack ? snapshot.durationMs : 0);
  self.progress.progress = snapshot.hasTrack && snapshot.durationMs ? (float)snapshot.positionMs / snapshot.durationMs : 0;
  [self loadArtwork:snapshot.hasTrack ? playerText(snapshot.artwork) : @""];
  self.status.textColor = ready ? self.progress.progressTintColor : [UIColor colorWithWhite:0.65 alpha:1];
  if (snapshot.state == IPadFailed) {
    self.status.text = @"CONNECTION ERROR";
    self.message.text = [NSString stringWithFormat:@"%@\nClose and reopen the app to reconnect.", playerText(snapshot.error)];
  } else if (snapshot.state == IPadConnecting) {
    self.status.text = @"CONNECTING";
    self.message.text = @"Connecting to Spotify…";
  } else if (!ready) {
    self.status.text = @"WAITING FOR SPOTIFY";
    self.message.text = @"Choose CSpot player in Spotify to start playback.";
  } else if (!snapshot.hasTrack) {
    self.status.text = @"CONNECTED";
    self.message.text = @"Choose a song in Spotify. Playback controls are available here.";
  } else {
    self.status.text = snapshot.loading ? @"LOADING" : snapshot.paused ? @"PAUSED" : @"PLAYING";
    self.message.text = @"";
  }
}
- (void)togglePause { ipad_player_command(IPadTogglePause); [self render]; }
- (void)previous { ipad_player_command(IPadPrevious); [self render]; }
- (void)next { ipad_player_command(IPadNext); [self render]; }
@end
