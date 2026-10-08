// SPDX-License-Identifier: GPL-3.0-or-later
#import "NowPlayingViewController.h"
#import "BennuTheme.h"
#import "PlayerModel.h"
#import "ImageCache.h"
#import "QueueViewController.h"
#import "VisualizerView.h"
#import "VisualizerMenu.h"
@interface NowPlayingViewController ()
@property(nonatomic, strong) UIButton* closeButton;
@property(nonatomic, strong) UILabel* contextLabel;
@property(nonatomic, strong) UILabel* contextName;
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* artistLabel;
@property(nonatomic, strong) UISlider* slider;
@property(nonatomic, strong) UILabel* elapsed;
@property(nonatomic, strong) UILabel* remaining;
@property(nonatomic, strong) UIButton* shuffleButton;
@property(nonatomic, strong) UIButton* previousButton;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) UIButton* nextButton;
@property(nonatomic, strong) UIButton* repeatButton;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UIButton* queueButton;
@property(nonatomic, strong) UIButton* vizButton;
@property(nonatomic, strong) VisualizerView* visualizer;
@property(nonatomic) BOOL scrubbing;
@end
@implementation NowPlayingViewController
- (UIButton*)iconButton:(NSString*)name size:(CGFloat)size action:(SEL)action {
  UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
  [button setImage:[BennuTheme icon:name size:size color:[BennuTheme text]] forState:UIControlStateNormal];
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:button];
  return button;
}
- (UILabel*)label:(UIFont*)font color:(UIColor*)color {
  UILabel* label = [[UILabel alloc] init];
  label.font = font; label.textColor = color; label.textAlignment = NSTextAlignmentCenter;
  [self.view addSubview:label];
  return label;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [BennuTheme background];
  self.closeButton = [self iconButton:@"chevronDown" size:28 action:@selector(close)];
  self.contextLabel = [self label:[BennuTheme regular:11] color:[BennuTheme subtext]];
  self.contextName = [self label:[BennuTheme bold:13] color:[BennuTheme text]];
  self.artwork = [[UIImageView alloc] init];
  self.artwork.contentMode = UIViewContentModeScaleAspectFill;
  self.artwork.clipsToBounds = YES;
  self.artwork.layer.cornerRadius = 6;
  self.artwork.layer.shadowOpacity = 0.6; self.artwork.layer.shadowRadius = 24; self.artwork.layer.shadowOffset = CGSizeMake(0, 12);
  [self.view addSubview:self.artwork];
  self.titleLabel = [self label:[BennuTheme bold:24] color:[BennuTheme text]];
  self.titleLabel.textAlignment = NSTextAlignmentLeft;
  self.artistLabel = [self label:[BennuTheme regular:17] color:[BennuTheme subtext]];
  self.artistLabel.textAlignment = NSTextAlignmentLeft;
  self.slider = [[UISlider alloc] init];
  self.slider.minimumTrackTintColor = [BennuTheme text];
  self.slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.3];
  [self.slider setThumbImage:[self thumbImage] forState:UIControlStateNormal];
  [self.slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
  [self.slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
  [self.slider addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
  [self.view addSubview:self.slider];
  self.elapsed = [self label:[BennuTheme regular:12] color:[BennuTheme subtext]];
  self.elapsed.textAlignment = NSTextAlignmentLeft;
  self.remaining = [self label:[BennuTheme regular:12] color:[BennuTheme subtext]];
  self.remaining.textAlignment = NSTextAlignmentRight;
  self.shuffleButton = [self iconButton:@"shuffle" size:26 action:@selector(shuffle)];
  self.previousButton = [self iconButton:@"previous" size:36 action:@selector(previous)];
  self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.playButton.backgroundColor = [BennuTheme text];
  self.playButton.layer.cornerRadius = 36;
  [self.playButton addTarget:self action:@selector(togglePause) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.playButton];
  self.nextButton = [self iconButton:@"next" size:36 action:@selector(next)];
  self.repeatButton = [self iconButton:@"repeat" size:26 action:@selector(repeatTapped)];
  self.repeatButton.alpha = 0.35;
  self.queueButton = [self iconButton:@"library" size:24 action:@selector(openQueue)];
  self.vizButton = [self iconButton:@"visualizer" size:26 action:@selector(chooseVisualization)];
  self.vizButton.accessibilityLabel = @"Visualizations";
  self.queueButton.accessibilityLabel = @"Queue";
  self.status = [self label:[BennuTheme regular:13] color:[BennuTheme subtext]];
  self.status.numberOfLines = 2;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(render) name:BennuMusicChanged object:nil];
  [self render];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (UIImage*)thumbImage {
  UIGraphicsBeginImageContextWithOptions(CGSizeMake(14, 14), NO, 0);
  [[BennuTheme text] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 14, 14)] fill];
  UIImage* image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  BOOL landscape = width > height;
  self.closeButton.frame = CGRectMake(16, 24, 44, 44);
  self.visualizer.frame = self.view.bounds;
  self.contextLabel.frame = CGRectMake(80, 28, width - 160, 16);
  self.contextName.frame = CGRectMake(80, 46, width - 160, 20);
  CGFloat art = landscape ? MIN(height - 160, width * 0.42) : MIN(width - 160, height * 0.46);
  CGFloat contentWidth = landscape ? width - art - 3 * 48 : MIN(width - 120, 640);
  CGFloat artX = landscape ? 48 : (width - art) / 2;
  CGFloat artY = landscape ? (height - art) / 2 + 10 : 96;
  self.artwork.frame = CGRectMake(artX, artY, art, art);
  CGFloat x = landscape ? artX + art + 48 : (width - contentWidth) / 2;
  CGFloat y = landscape ? artY + art * 0.1 : artY + art + 36;
  self.titleLabel.frame = CGRectMake(x, y, contentWidth, 30);
  self.artistLabel.frame = CGRectMake(x, y + 32, contentWidth, 22);
  self.slider.frame = CGRectMake(x, y + 72, contentWidth, 30);
  self.elapsed.frame = CGRectMake(x, y + 104, contentWidth / 2, 16);
  self.remaining.frame = CGRectMake(x + contentWidth / 2, y + 104, contentWidth / 2, 16);
  CGFloat center = x + contentWidth / 2, controlsY = y + 140;
  self.playButton.frame = CGRectMake(center - 36, controlsY, 72, 72);
  self.previousButton.frame = CGRectMake(center - 36 - 24 - 56, controlsY + 8, 56, 56);
  self.nextButton.frame = CGRectMake(center + 36 + 24, controlsY + 8, 56, 56);
  self.shuffleButton.frame = CGRectMake(x, controlsY + 12, 48, 48);
  self.repeatButton.frame = CGRectMake(x + contentWidth - 48, controlsY + 12, 48, 48);
  // Bottom action row, like Spotify's: visualizer on the left, queue on the right, status in between.
  CGFloat rowY = controlsY + 92;
  self.vizButton.frame = CGRectMake(x, rowY, 48, 48);
  self.queueButton.frame = CGRectMake(x + contentWidth - 48, rowY, 48, 48);
  self.status.frame = CGRectMake(x + 56, rowY + 4, contentWidth - 112, 40);
}
- (void)render {
  PlayerModel* model = [PlayerModel shared];
  IPadPlayerSnapshot snapshot = model.snapshot;
  BOOL hasTrack = snapshot.hasTrack;
  self.contextLabel.text = model.contextName.length ? @"PLAYING FROM" : @"";
  self.contextName.text = model.contextName ?: @"";
  self.titleLabel.text = hasTrack ? @(snapshot.title) : @"Nothing playing";
  self.artistLabel.text = hasTrack ? @(snapshot.artist) : @"Pick a song from Home or Search";
  [[ImageCache shared] load:hasTrack ? @(snapshot.artwork) : @"" into:self.artwork placeholder:[BennuTheme placeholderArt:300]];
  [self.playButton setImage:[BennuTheme icon:snapshot.paused ? @"play" : @"pause" size:36 color:[UIColor blackColor]] forState:UIControlStateNormal];
  BOOL enabled = hasTrack && !snapshot.loading && !snapshot.pending;
  for (UIButton* button in @[self.playButton, self.previousButton, self.nextButton]) { button.enabled = enabled; button.alpha = enabled ? 1 : 0.4; }
  self.shuffleButton.alpha = model.shuffle ? 1 : 0.35;
  [self.shuffleButton setImage:[BennuTheme icon:@"shuffle" size:26 color:model.shuffle ? [BennuTheme green] : [BennuTheme text]] forState:UIControlStateNormal];
  if (!self.scrubbing) {
    self.slider.maximumValue = MAX(1, snapshot.durationMs);
    self.slider.value = hasTrack ? snapshot.positionMs : 0;
    self.elapsed.text = BennuDuration(hasTrack ? snapshot.positionMs : 0);
    self.remaining.text = [@"-" stringByAppendingString:BennuDuration(hasTrack && snapshot.durationMs > snapshot.positionMs ? snapshot.durationMs - snapshot.positionMs : 0)];
  }
  int repeat = snapshot.repeat;
  self.repeatButton.alpha = repeat ? 1 : 0.35;
  [self.repeatButton setImage:[BennuTheme icon:repeat == 2 ? @"repeatOne" : @"repeat" size:26 color:repeat ? [BennuTheme green] : [BennuTheme text]] forState:UIControlStateNormal];
  if (snapshot.state == IPadFailed) self.status.text = @(snapshot.error);
  else if (snapshot.reconnecting) self.status.text = @"Reconnecting to Spotify…";
  else if (snapshot.state != IPadReady) self.status.text = @"Connecting to Spotify…";
  else if (snapshot.loading) self.status.text = @"Loading…";
  else self.status.text = @"";
}
- (void)scrubBegan { self.scrubbing = YES; }
- (void)scrubMoved { self.elapsed.text = BennuDuration((uint32_t)self.slider.value); }
- (void)scrubEnded { self.scrubbing = NO; [[PlayerModel shared] seekTo:(uint32_t)self.slider.value]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)togglePause { [[PlayerModel shared] togglePause]; }
- (void)next { [[PlayerModel shared] next]; }
- (void)previous { [[PlayerModel shared] previous]; }
- (void)shuffle { [[PlayerModel shared] toggleShuffle]; }
- (void)repeatTapped { [[PlayerModel shared] cycleRepeat]; }
// Visualization picker: one panel with families and presets side by side.
- (void)chooseVisualization {
  NSArray* saved = [NSUserDefaults.standardUserDefaults arrayForKey:@"BennuVisualization"];
  VisualizerMenu* menu = [[VisualizerMenu alloc] init];
  __weak NowPlayingViewController* weakSelf = self;
  menu.onPick = ^(NSString* family, NSString* preset) { [weakSelf showVisualization:family preset:preset]; };
  [menu showIn:self.view anchor:self.vizButton selectedFamily:saved.count > 1 ? saved[0] : nil preset:saved.count > 1 ? saved[1] : nil];
}
- (void)showVisualization:(NSString*)family preset:(NSString*)preset {
  [NSUserDefaults.standardUserDefaults setObject:@[family, preset] forKey:@"BennuVisualization"];
  if (!self.visualizer) {
    self.visualizer = [[VisualizerView alloc] initWithFrame:self.view.bounds];
    __weak NowPlayingViewController* weakSelf = self;
    self.visualizer.onTouch = ^{ [weakSelf hideVisualization]; };   // any touch closes it
  }
  self.visualizer.alpha = 0;
  [self.view addSubview:self.visualizer];
  [self.visualizer startWithFamily:family preset:preset];
  [UIView animateWithDuration:0.3 animations:^{ self.visualizer.alpha = 1; }];
}
- (void)hideVisualization {
  VisualizerView* view = self.visualizer;
  [UIView animateWithDuration:0.25 animations:^{ view.alpha = 0; } completion:^(BOOL finished) { [view stop]; [view removeFromSuperview]; }];
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [self.visualizer stop]; }
- (void)openQueue {
  QueueViewController* queue = [[QueueViewController alloc] init];
  queue.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:queue animated:YES completion:nil];
}
@end
