// SPDX-License-Identifier: GPL-3.0-or-later
#import "MiniPlayerView.h"
#import "PhoenixTheme.h"
#import "PlayerModel.h"
#import "ImageCache.h"
@interface MiniPlayerView ()
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* artistLabel;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) UIView* progressTrack;
@property(nonatomic, strong) UIView* progressFill;
@end
@implementation MiniPlayerView
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [PhoenixTheme card];
    self.layer.cornerRadius = 8;
    self.artwork = [[UIImageView alloc] init];
    self.artwork.contentMode = UIViewContentModeScaleAspectFill; self.artwork.clipsToBounds = YES; self.artwork.layer.cornerRadius = 4;
    [self addSubview:self.artwork];
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:14]; self.titleLabel.textColor = [PhoenixTheme text];
    self.artistLabel = [[UILabel alloc] init]; self.artistLabel.font = [PhoenixTheme regular:12]; self.artistLabel.textColor = [PhoenixTheme subtext];
    [self addSubview:self.titleLabel]; [self addSubview:self.artistLabel];
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton addTarget:self action:@selector(togglePause) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.playButton];
    self.progressTrack = [[UIView alloc] init]; self.progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    self.progressFill = [[UIView alloc] init]; self.progressFill.backgroundColor = [PhoenixTheme text];
    [self addSubview:self.progressTrack]; [self.progressTrack addSubview:self.progressFill];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(render) name:PhoenixPlayerChanged object:nil];
    [self render];
  }
  return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat h = self.bounds.size.height, w = self.bounds.size.width;
  self.artwork.frame = CGRectMake(8, 8, h - 20, h - 20);
  CGFloat x = h; CGFloat textWidth = w - x - 72;
  self.titleLabel.frame = CGRectMake(x, 10, textWidth, 18);
  self.artistLabel.frame = CGRectMake(x, 29, textWidth, 16);
  self.playButton.frame = CGRectMake(w - 60, 4, 52, h - 12);
  self.progressTrack.frame = CGRectMake(8, h - 4, w - 16, 2);
}
- (void)render {
  IPadPlayerSnapshot snapshot = [PlayerModel shared].snapshot;
  self.hidden = !snapshot.hasTrack;
  if (!snapshot.hasTrack) return;
  self.titleLabel.text = @(snapshot.title); self.artistLabel.text = @(snapshot.artist);
  [[ImageCache shared] load:@(snapshot.artwork) into:self.artwork placeholder:[PhoenixTheme placeholderArt:64]];
  [self.playButton setImage:[PhoenixTheme icon:snapshot.paused ? @"play" : @"pause" size:28 color:[PhoenixTheme text]] forState:UIControlStateNormal];
  CGFloat fraction = snapshot.durationMs ? (CGFloat)snapshot.positionMs / snapshot.durationMs : 0;
  self.progressFill.frame = CGRectMake(0, 0, self.progressTrack.bounds.size.width * fraction, 2);
}
- (void)togglePause { [[PlayerModel shared] togglePause]; }
- (void)tapped { if (self.onTap) self.onTap(); }
@end
