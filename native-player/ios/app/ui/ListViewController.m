// SPDX-License-Identifier: GPL-3.0-or-later
#import "ListViewController.h"
#import "PhoenixTheme.h"
#import "PhoenixCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
#import "ImageCache.h"
@interface ListViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) NSString* kind;
@property(nonatomic, copy) NSString* uri;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* artworkURL;
@property(nonatomic, strong) NSDictionary* data;
@property(nonatomic, strong) NSArray* tracks;
@property(nonatomic, strong) CatalogRequest* request;
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* subtitleLabel;
@property(nonatomic, strong) UILabel* detailLabel;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) UIButton* shuffleButton;
@property(nonatomic, strong) UILabel* status;
@end
@implementation ListViewController
- (instancetype)initWithKind:(NSString*)kind uri:(NSString*)uri name:(NSString*)name artwork:(NSString*)artwork {
  if ((self = [super init])) { self.kind = kind; self.uri = uri; self.name = name; self.artworkURL = artwork; }
  return self;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.topTitle.text = self.name;
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  self.table.rowHeight = 56;
  [self.table registerClass:TrackCell.class forCellReuseIdentifier:@"track"];
  self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
  self.artwork = [[UIImageView alloc] init];
  self.artwork.contentMode = UIViewContentModeScaleAspectFill; self.artwork.clipsToBounds = YES;
  self.artwork.layer.shadowOpacity = 0.5; self.artwork.layer.shadowRadius = 16; self.artwork.layer.shadowOffset = CGSizeMake(0, 8);
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:30]; self.titleLabel.textColor = [PhoenixTheme text]; self.titleLabel.numberOfLines = 2;
  self.subtitleLabel = [[UILabel alloc] init]; self.subtitleLabel.font = [PhoenixTheme bold:15]; self.subtitleLabel.textColor = [PhoenixTheme text];
  self.detailLabel = [[UILabel alloc] init]; self.detailLabel.font = [PhoenixTheme regular:13]; self.detailLabel.textColor = [PhoenixTheme subtext]; self.detailLabel.numberOfLines = 2;
  self.playButton = [PhoenixTheme greenPlayButton:56];
  [self.playButton addTarget:self action:@selector(playAll) forControlEvents:UIControlEventTouchUpInside];
  self.shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.shuffleButton setImage:[PhoenixTheme icon:@"shuffle" size:30 color:[PhoenixTheme subtext]] forState:UIControlStateNormal];
  [self.shuffleButton addTarget:self action:@selector(shuffleAll) forControlEvents:UIControlEventTouchUpInside];
  self.status = [[UILabel alloc] init]; self.status.font = [PhoenixTheme regular:13]; self.status.textColor = [PhoenixTheme subtext];
  for (UIView* view in @[self.artwork, self.titleLabel, self.subtitleLabel, self.detailLabel, self.playButton, self.shuffleButton, self.status]) [self.header addSubview:view];
  self.table.tableHeaderView = self.header;
  self.titleLabel.text = self.name;
  UIImage* placeholder = [self.kind isEqualToString:@"collection"] ? [PhoenixTheme likedSongsArt:240] : [PhoenixTheme placeholderArt:240];
  [[ImageCache shared] load:self.artworkURL into:self.artwork placeholder:placeholder];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:PhoenixPlayerChanged object:nil];
  [self load];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.request cancel]; }
- (NSString*)identifier {
  NSArray* parts = [self.uri componentsSeparatedByString:@":"];
  return parts.count >= 3 ? parts[2] : @"";
}
- (void)load {
  self.status.text = @"Loading…";
  __weak ListViewController* weakSelf = self;
  self.request = [[CatalogClient shared] request:self.kind argument:[self identifier] update:^(NSDictionary* json, BOOL done) {
    ListViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) { owner.status.text = json[@"error"]; return; }
    owner.data = json;
    NSArray* tracks = json[@"tracks"];
    owner.tracks = [tracks isKindOfClass:NSArray.class] ? tracks : @[];
    [owner renderHeader];
    [owner.table reloadData];
  }];
}
- (void)renderHeader {
  NSDictionary* data = self.data;
  NSString* name = data[@"name"]; if ([name isKindOfClass:NSString.class] && name.length) { self.name = name; self.titleLabel.text = name; self.topTitle.text = name; }
  NSString* artwork = data[@"artwork"];
  if ([artwork isKindOfClass:NSString.class] && artwork.length && ![artwork isEqualToString:self.artworkURL]) { self.artworkURL = artwork; [[ImageCache shared] load:artwork into:self.artwork placeholder:self.artwork.image]; }
  NSMutableArray* details = [NSMutableArray array];
  if ([self.kind isEqualToString:@"album"]) {
    self.subtitleLabel.text = data[@"artist"] ?: @"";
    NSString* type = [data[@"type"] isKindOfClass:NSString.class] ? [data[@"type"] capitalizedString] : @"Album";
    if ([data[@"year"] intValue]) [details addObject:[NSString stringWithFormat:@"%@ • %d", type, [data[@"year"] intValue]]]; else [details addObject:type];
  } else if ([self.kind isEqualToString:@"playlist"]) {
    NSString* owner = data[@"owner"]; self.subtitleLabel.text = [owner isKindOfClass:NSString.class] && owner.length ? [NSString stringWithFormat:@"By %@", [owner stringByReplacingOccurrencesOfString:@"spotify:user:" withString:@""]] : @"Playlist";
    NSString* description = data[@"description"]; if ([description isKindOfClass:NSString.class] && description.length) [details addObject:description];
  } else { self.subtitleLabel.text = @"Playlist"; }
  BOOL loading = [data[@"loading"] boolValue];
  NSUInteger count = self.tracks.count;
  if (count) [details addObject:[NSString stringWithFormat:@"%lu songs", (unsigned long)count]];
  self.detailLabel.text = [details componentsJoinedByString:@" • "];
  self.status.text = loading ? @"Loading song details…" : @"";
  [self layoutHeader];
}
- (void)layoutHeader {
  CGFloat width = self.view.bounds.size.width;
  BOOL wide = width > 600;
  CGFloat art = wide ? 240 : 200;
  self.header.frame = CGRectMake(0, 0, width, wide ? art + 80 : art + 190);
  if (wide) {
    self.artwork.frame = CGRectMake(24, 16, art, art);
    CGFloat x = 24 + art + 24, w = width - x - 24;
    self.titleLabel.frame = CGRectMake(x, 24, w, 76);
    self.subtitleLabel.frame = CGRectMake(x, 104, w, 20);
    self.detailLabel.frame = CGRectMake(x, 128, w, 36);
    self.playButton.frame = CGRectMake(x, 180, 56, 56);
    self.shuffleButton.frame = CGRectMake(x + 72, 184, 48, 48);
    self.status.frame = CGRectMake(x + 132, 198, w - 132, 20);
  } else {
    self.artwork.frame = CGRectMake((width - art) / 2, 16, art, art);
    self.titleLabel.frame = CGRectMake(16, art + 28, width - 32, 40);
    self.subtitleLabel.frame = CGRectMake(16, art + 70, width - 32, 20);
    self.detailLabel.frame = CGRectMake(16, art + 92, width - 120, 36);
    self.playButton.frame = CGRectMake(width - 80, art + 92, 56, 56);
    self.shuffleButton.frame = CGRectMake(width - 136, art + 96, 48, 48);
    self.status.frame = CGRectMake(16, art + 134, width - 32, 20);
  }
  self.table.tableHeaderView = self.header;
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutHeader]; }
- (NSArray*)uris {
  NSMutableArray* uris = [NSMutableArray array];
  for (NSDictionary* track in self.tracks) if ([track[@"uri"] isKindOfClass:NSString.class]) [uris addObject:track[@"uri"]];
  return uris;
}
- (void)playFrom:(NSUInteger)index shuffle:(BOOL)shuffle {
  NSArray* uris = [self uris];
  if (!uris.count) return;
  PlayerModel* model = [PlayerModel shared];
  if (shuffle != model.shuffle) [model toggleShuffle];
  if (![model playURIs:uris index:index contextUri:self.uri contextName:self.name]) self.status.text = @"The player is busy. Try again.";
}
- (void)playAll { [self playFrom:0 shuffle:NO]; }
- (void)shuffleAll { [self playFrom:(NSUInteger)arc4random_uniform((uint32_t)MAX(1, self.tracks.count)) shuffle:YES]; }
- (void)playerChanged { for (TrackCell* cell in self.table.visibleCells) { NSIndexPath* path = [self.table indexPathForCell:cell]; if (path) [self configure:cell at:path]; } }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return self.tracks.count; }
- (void)configure:(TrackCell*)cell at:(NSIndexPath*)path {
  NSDictionary* track = self.tracks[path.row];
  NSString* playingId = @([PlayerModel shared].snapshot.trackId);
  BOOL playing = playingId.length && [track[@"id"] isEqualToString:playingId];
  [cell showTrack:track number:[self.kind isEqualToString:@"album"] ? path.row + 1 : -1 playing:playing];
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  TrackCell* cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path];
  [self configure:cell at:path];
  return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  [self playFrom:path.row shuffle:NO];
}
@end
