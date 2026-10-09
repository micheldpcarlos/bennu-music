// SPDX-License-Identifier: GPL-3.0-or-later
#import "HomeViewController.h"
#import "BennuTheme.h"
#import "BennuCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
#import "ImageCache.h"
#import "SetupViewController.h"
#import "SettingsViewController.h"
enum { HomeRecent = 0, HomePlaylists, HomeRadios, HomeReleases, HomeCount };
@interface HomeViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSArray* recent;
@property(nonatomic, strong) NSArray* playlists;
@property(nonatomic, strong) NSArray* radios;
@property(nonatomic, strong) NSArray* releases;
@property(nonatomic, strong) CatalogRequest* homeRequest;
@property(nonatomic, strong) CatalogRequest* feedRequest;
@property(nonatomic, strong) CatalogRequest* updateRequest;
@property(nonatomic) BOOL checkedUpdate;
@property(nonatomic, strong) NSArray* feed;   // Spotify's own Home sections [{title, items}] when the web player service answers
@property(nonatomic, strong) CatalogRequest* recentRequest;
@property(nonatomic, strong) CatalogRequest* profileRequest;
@property(nonatomic, strong) CatalogRequest* playlistsRequest;
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UILabel* greeting;
@property(nonatomic, strong) UIButton* accountButton;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic) BOOL loadedOnce;
@end
@implementation HomeViewController
- (instancetype)init { if ((self = [super init])) self.isRoot = YES; return self; }
- (void)viewDidLoad {
  [super viewDidLoad];
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  [self.table registerClass:ShelfCell.class forCellReuseIdentifier:@"shelf"];
  [self.table registerClass:SectionHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
  self.header = [[UIView alloc] init];
  self.greeting = [[UILabel alloc] init]; self.greeting.font = [BennuTheme bold:30]; self.greeting.textColor = [BennuTheme text];
  self.accountButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.accountButton setImage:[BennuTheme icon:@"account" size:30 color:[BennuTheme text]] forState:UIControlStateNormal];
  [self.accountButton addTarget:self action:@selector(openAccount) forControlEvents:UIControlEventTouchUpInside];
  self.accountButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
  self.accountButton.clipsToBounds = YES;
  self.status = [[UILabel alloc] init]; self.status.font = [BennuTheme regular:14]; self.status.textColor = [BennuTheme subtext]; self.status.numberOfLines = 2;
  for (UIView* view in @[self.greeting, self.accountButton, self.status]) [self.header addSubview:view];
  self.table.tableHeaderView = self.header;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:BennuTrackChanged object:nil];
  [self playerChanged];   // the view may be created after the engine is already Ready; the notification only fires on changes
  [self renderGreeting];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)renderGreeting {
  NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
  self.greeting.text = hour < 12 ? @"Good morning" : hour < 18 ? @"Good afternoon" : @"Good evening";
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  self.header.frame = CGRectMake(0, 0, width, 100);
  self.greeting.font = [BennuTheme bold:width < 400 ? 24 : 30];
  self.greeting.adjustsFontSizeToFitWidth = YES; self.greeting.minimumScaleFactor = 0.7;
  self.greeting.frame = CGRectMake(16, 20, width - 90, 40);
  self.accountButton.frame = CGRectMake(width - 56, 24, 36, 36);
  self.status.frame = CGRectMake(16, 62, width - 32, 36);
  self.table.tableHeaderView = self.header;
}
- (void)playerChanged {
  PlayerModel* model = [PlayerModel shared];
  IPadPlayerSnapshot snapshot = model.snapshot;
  if (snapshot.state == IPadReady && !self.loadedOnce) { self.loadedOnce = YES; [self load]; }
  if (snapshot.state == IPadWaiting && self.loadedOnce) { self.loadedOnce = NO; self.radios = nil; self.releases = nil; self.feed = nil; [self.accountButton setImage:[BennuTheme icon:@"account" size:30 color:[BennuTheme text]] forState:UIControlStateNormal]; self.recent = nil; self.playlists = nil; [self renderGreeting]; [self.table reloadData]; }
  if (snapshot.state == IPadFailed) self.status.text = [NSString stringWithFormat:@"%s Close and reopen the app to reconnect.", snapshot.error];
  else if (snapshot.reconnecting) self.status.text = @"Connection lost. Reconnecting to Spotify…";
  else if (snapshot.state == IPadConnecting) self.status.text = @"Connecting to Spotify…";
  else if (snapshot.state == IPadReady && [self.status.text hasPrefix:@"Connection lost"]) self.status.text = @"";
  else if (snapshot.state == IPadWaiting) self.status.text = @"No account yet. Tap the account icon to connect Spotify.";
}
- (void)load {
  self.status.text = @"Loading your music…";
  __weak HomeViewController* weakSelf = self;
  self.recentRequest = [[CatalogClient shared] request:@"recent" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) { owner.status.text = json[@"error"]; if ([json[@"unavailable"] boolValue]) owner.status.textColor = [BennuTheme green]; return; }
    NSMutableArray* items = [NSMutableArray arrayWithObject:@{@"uri": @"collection", @"name": @"Liked Songs", @"subtitle": @"Playlist", @"artwork": @"", @"type": @"collection"}];
    if ([json[@"items"] isKindOfClass:NSArray.class]) [items addObjectsFromArray:json[@"items"]];
    owner.recent = items;
    owner.status.text = done ? @"" : @"Loading…";
    [owner.table reloadData];
  }];
  self.profileRequest = [[CatalogClient shared] request:@"profile" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    NSString* name = json[@"name"];
    NSString* image = json[@"image"];
    if ([image isKindOfClass:NSString.class] && image.length) {
      [PlayerModel shared].accountImage = image;
      [owner showAvatar:image];
    }
    if ([name isKindOfClass:NSString.class] && name.length) {
      [PlayerModel shared].accountName = name;
      [owner renderGreeting];
      owner.greeting.text = [NSString stringWithFormat:@"%@, %@", owner.greeting.text, [name componentsSeparatedByString:@" "].firstObject];
    }
  }];
  if (!self.checkedUpdate) {
    self.checkedUpdate = YES;
    self.updateRequest = [[CatalogClient shared] request:@"update" argument:[SettingsViewController appVersion] update:^(NSDictionary* json, BOOL done) {
      HomeViewController* owner = weakSelf; if (!owner || !done || json[@"error"] || ![json[@"newer"] boolValue]) return;
      owner.status.text = [NSString stringWithFormat:@"Bennu Music %@ is available. Account › Settings › Updates.", json[@"latest"]];
      owner.status.textColor = [BennuTheme green];
    }];
  }
  self.feedRequest = [[CatalogClient shared] request:@"homefeed" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"] || ![json[@"sections"] isKindOfClass:NSArray.class] || [json[@"sections"] count] == 0) return;   // keep the derived shelves
    owner.feed = json[@"sections"];
    NSString* greeting = json[@"greeting"];
    if ([greeting isKindOfClass:NSString.class] && greeting.length) {
      NSString* name = [PlayerModel shared].accountName;
      owner.greeting.text = name.length ? [NSString stringWithFormat:@"%@, %@", greeting, [name componentsSeparatedByString:@" "].firstObject] : greeting;
    }
    [owner.table reloadData];
  }];
  self.homeRequest = [[CatalogClient shared] request:@"home" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) return;
    owner.radios = [json[@"radios"] isKindOfClass:NSArray.class] ? json[@"radios"] : @[];
    owner.releases = [json[@"releases"] isKindOfClass:NSArray.class] ? json[@"releases"] : @[];
    [owner.table reloadData];
  }];
  self.playlistsRequest = [[CatalogClient shared] request:@"playlists" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    NSMutableArray* tiles = [NSMutableArray array];
    if ([json[@"playlists"] isKindOfClass:NSArray.class])
      for (NSDictionary* playlist in json[@"playlists"]) {
        NSNumber* count = playlist[@"count"];
        [tiles addObject:@{@"uri": playlist[@"uri"] ?: @"", @"name": playlist[@"name"] ?: @"", @"subtitle": [count intValue] ? [NSString stringWithFormat:@"%d songs", [count intValue]] : @"Playlist", @"artwork": playlist[@"artwork"] ?: @"", @"type": @"playlist"}];
        if (tiles.count >= 20) break;
      }
    owner.playlists = tiles;
    [owner.table reloadData];
  }];
}
- (void)showAvatar:(NSString*)url {
  fprintf(stderr, "IMG: avatar host=%s\n", [NSURL URLWithString:url].host.UTF8String ?: "(invalid url)");
  __weak HomeViewController* weakSelf = self;
  [[ImageCache shared] load:url completion:^(UIImage* image) {
    HomeViewController* owner = weakSelf; if (!owner || !image) return;
    CGSize size = CGSizeMake(36, 36);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 36, 36)] addClip];
    CGFloat scale = MAX(36 / image.size.width, 36 / image.size.height);
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    [image drawInRect:CGRectMake((36 - drawn.width) / 2, (36 - drawn.height) / 2, drawn.width, drawn.height)];
    UIImage* round = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    [owner.accountButton setImage:[round imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
  }];
}
- (void)openAccount {
  UIViewController* setup = [[SetupViewController alloc] init];
  setup.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:setup animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return self.feed ? (NSInteger)self.feed.count : HomeCount; }
- (NSArray*)itemsFor:(NSInteger)section {
  if (self.feed) { NSDictionary* shelf = section < (NSInteger)self.feed.count ? self.feed[section] : nil; return [shelf[@"items"] isKindOfClass:NSArray.class] ? shelf[@"items"] : @[]; }
  switch (section) { case HomeRecent: return self.recent; case HomePlaylists: return self.playlists; case HomeRadios: return self.radios; default: return self.releases; }
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return [self itemsFor:section].count ? 1 : 0; }
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = self.feed ? (section < (NSInteger)self.feed.count ? self.feed[section][@"title"] : @"") : @[@"Recently played", @"Your playlists", @"Made for you", @"New releases for you"][section];
  return header;
}
- (CGFloat)tableView:(UITableView*)table heightForRowAtIndexPath:(NSIndexPath*)path { return [ShelfCell height]; }
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  ShelfCell* shelf = [table dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:path];
  shelf.items = [self itemsFor:path.section];
  shelf.onSelect = ^(NSDictionary* item) {
    NSString* uri = item[@"uri"];
    if ([uri isEqualToString:@"collection"]) uri = @"spotify:user:me:collection";
    if ([item[@"type"] isEqualToString:@"station"]) { [[PlayerModel shared] playContext:uri name:item[@"name"] shuffle:NO]; return; }
    BennuOpen(uri, item[@"name"], item[@"artwork"]);
  };
  return shelf;
}
@end
