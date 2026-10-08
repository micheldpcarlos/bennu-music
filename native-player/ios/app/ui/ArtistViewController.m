// SPDX-License-Identifier: GPL-3.0-or-later
#import "ArtistViewController.h"
#import "PhoenixTheme.h"
#import "PhoenixCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
#import "ImageCache.h"
enum { SectionPopular = 0, SectionAlbums, SectionSingles, SectionAbout, SectionCount };
@interface ArtistViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) NSString* uri;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, strong) NSDictionary* data;
@property(nonatomic, strong) NSArray* topTracks;
@property(nonatomic, strong) NSArray* albums;
@property(nonatomic, strong) NSArray* singles;
@property(nonatomic, strong) CatalogRequest* request;
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UIImageView* portrait;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UIButton* playButton;
@property(nonatomic, strong) UIButton* shuffleButton;
@end
@implementation ArtistViewController
- (instancetype)initWithURI:(NSString*)uri name:(NSString*)name { if ((self = [super init])) { self.uri = uri; self.name = name; } return self; }
- (void)viewDidLoad {
  [super viewDidLoad];
  self.topTitle.text = self.name;
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  [self.table registerClass:TrackCell.class forCellReuseIdentifier:@"track"];
  UILongPressGestureRecognizer* press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
  press.minimumPressDuration = 0.5;
  [self.table addGestureRecognizer:press];
  [self.table registerClass:ShelfCell.class forCellReuseIdentifier:@"shelf"];
  [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"about"];
  [self.table registerClass:SectionHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
  self.header = [[UIView alloc] init];
  self.portrait = [[UIImageView alloc] init]; self.portrait.contentMode = UIViewContentModeScaleAspectFill; self.portrait.clipsToBounds = YES;
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:40]; self.titleLabel.textColor = [PhoenixTheme text]; self.titleLabel.adjustsFontSizeToFitWidth = YES;
  self.titleLabel.text = self.name;
  self.status = [[UILabel alloc] init]; self.status.font = [PhoenixTheme regular:13]; self.status.textColor = [PhoenixTheme subtext];
  self.playButton = [PhoenixTheme greenPlayButton:56];
  [self.playButton addTarget:self action:@selector(playPopular) forControlEvents:UIControlEventTouchUpInside];
  self.shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.shuffleButton setImage:[PhoenixTheme icon:@"shuffle" size:30 color:[PhoenixTheme subtext]] forState:UIControlStateNormal];
  [self.shuffleButton addTarget:self action:@selector(shufflePopular) forControlEvents:UIControlEventTouchUpInside];
  for (UIView* view in @[self.portrait, self.titleLabel, self.status, self.playButton, self.shuffleButton]) [self.header addSubview:view];
  self.table.tableHeaderView = self.header;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:PhoenixPlayerChanged object:nil];
  [self load];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.request cancel]; }
- (void)load {
  self.status.text = @"Loading…";
  NSArray* parts = [self.uri componentsSeparatedByString:@":"];
  __weak ArtistViewController* weakSelf = self;
  self.request = [[CatalogClient shared] request:@"artist" argument:parts.count >= 3 ? parts[2] : @"" update:^(NSDictionary* json, BOOL done) {
    ArtistViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) { owner.status.text = json[@"error"]; return; }
    owner.data = json;
    owner.topTracks = [json[@"topTracks"] isKindOfClass:NSArray.class] ? json[@"topTracks"] : @[];
    owner.albums = [json[@"albums"] isKindOfClass:NSArray.class] ? json[@"albums"] : @[];
    owner.singles = [json[@"singles"] isKindOfClass:NSArray.class] ? json[@"singles"] : @[];
    NSString* name = json[@"name"]; if ([name isKindOfClass:NSString.class] && name.length) { owner.name = name; owner.titleLabel.text = name; owner.topTitle.text = name; }
    [[ImageCache shared] load:json[@"image"] into:owner.portrait placeholder:[PhoenixTheme placeholderArt:200]];
    owner.status.text = done ? @"" : @"Loading…";
    [owner.table reloadData];
  }];
}
- (void)layoutHeader {
  CGFloat width = self.view.bounds.size.width;
  self.header.frame = CGRectMake(0, 0, width, 260);
  self.portrait.frame = CGRectMake(24, 16, 180, 180); self.portrait.layer.cornerRadius = 90;
  self.titleLabel.frame = CGRectMake(228, 40, width - 252, 56);
  self.status.frame = CGRectMake(228, 100, width - 252, 20);
  self.playButton.frame = CGRectMake(228, 132, 56, 56);
  self.shuffleButton.frame = CGRectMake(300, 136, 48, 48);
  self.table.tableHeaderView = self.header;
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutHeader]; }
- (NSArray*)popularURIs { NSMutableArray* uris = [NSMutableArray array]; for (NSDictionary* t in self.topTracks) if ([t[@"uri"] isKindOfClass:NSString.class]) [uris addObject:t[@"uri"]]; return uris; }
- (void)playFrom:(NSUInteger)index shuffle:(BOOL)shuffle {
  NSArray* uris = [self popularURIs]; if (!uris.count) return;
  PlayerModel* model = [PlayerModel shared];
  if (shuffle != model.shuffle) [model toggleShuffle];
  [model playURIs:uris index:index contextUri:self.uri contextName:self.name];
}
- (void)playPopular { [self playFrom:0 shuffle:NO]; }
- (void)shufflePopular { [self playFrom:0 shuffle:YES]; }
- (void)playerChanged { for (UITableViewCell* cell in self.table.visibleCells) { NSIndexPath* path = [self.table indexPathForCell:cell]; if (path && path.section == SectionPopular) [self configure:(TrackCell*)cell at:path]; } }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return SectionCount; }
- (void)longPress:(UILongPressGestureRecognizer*)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  NSIndexPath* path = [self.table indexPathForRowAtPoint:[gesture locationInView:self.table]];
  if (!path) return;
  if (path.section != SectionPopular) return;
  if (path.row >= (NSInteger)self.topTracks.count) return;
  PhoenixTrackMenu(self, self.topTracks[path.row], [self.table cellForRowAtIndexPath:path]);
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case SectionPopular: return MIN(5, self.topTracks.count);
    case SectionAlbums: return self.albums.count ? 1 : 0;
    case SectionSingles: return self.singles.count ? 1 : 0;
    default: return [self.data[@"biography"] isKindOfClass:NSString.class] && [self.data[@"biography"] length] ? 1 : 0;
  }
}
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = @[@"Popular", @"Albums", @"Singles and EPs", @"About"][section];
  return header;
}
- (CGFloat)tableView:(UITableView*)table heightForRowAtIndexPath:(NSIndexPath*)path {
  if (path.section == SectionPopular) return 56;
  if (path.section == SectionAbout) return 150;
  return [ShelfCell height];
}
- (void)configure:(TrackCell*)cell at:(NSIndexPath*)path {
  NSDictionary* track = self.topTracks[path.row];
  NSString* playingId = @([PlayerModel shared].snapshot.trackId);
  [cell showTrack:track number:path.row + 1 playing:playingId.length && [track[@"id"] isEqualToString:playingId]];
}
- (NSArray*)tiles:(NSArray*)albums {
  NSMutableArray* tiles = [NSMutableArray array];
  for (NSDictionary* album in albums) {
    NSString* year = [album[@"year"] intValue] ? [NSString stringWithFormat:@"%d", [album[@"year"] intValue]] : @"";
    [tiles addObject:@{@"uri": album[@"uri"] ?: @"", @"name": album[@"name"] ?: @"", @"subtitle": year, @"artwork": album[@"artwork"] ?: @"", @"type": @"album"}];
  }
  return tiles;
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  if (path.section == SectionPopular) {
    TrackCell* cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path];
    [self configure:cell at:path]; return cell;
  }
  if (path.section == SectionAbout) {
    UITableViewCell* cell = [table dequeueReusableCellWithIdentifier:@"about" forIndexPath:path];
    cell.backgroundColor = [UIColor clearColor]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.numberOfLines = 6; cell.textLabel.font = [PhoenixTheme regular:14]; cell.textLabel.textColor = [PhoenixTheme subtext];
    cell.textLabel.text = self.data[@"biography"];
    return cell;
  }
  ShelfCell* shelf = [table dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:path];
  shelf.items = [self tiles:path.section == SectionAlbums ? self.albums : self.singles];
  shelf.onSelect = ^(NSDictionary* item) { PhoenixOpen(item[@"uri"], item[@"name"], item[@"artwork"]); };
  return shelf;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  if (path.section == SectionPopular) [self playFrom:path.row shuffle:NO];
}
@end
