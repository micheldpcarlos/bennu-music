// SPDX-License-Identifier: GPL-3.0-or-later
#import "HomeViewController.h"
#import "PhoenixTheme.h"
#import "PhoenixCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
#import "ImageCache.h"
#import "SetupViewController.h"
enum { HomeRecent = 0, HomePlaylists, HomeCount };
@interface HomeViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSArray* recent;
@property(nonatomic, strong) NSArray* playlists;
@property(nonatomic, strong) CatalogRequest* recentRequest;
@property(nonatomic, strong) CatalogRequest* profileRequest;
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
  self.greeting = [[UILabel alloc] init]; self.greeting.font = [PhoenixTheme bold:30]; self.greeting.textColor = [PhoenixTheme text];
  self.accountButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.accountButton setImage:[PhoenixTheme icon:@"account" size:30 color:[PhoenixTheme text]] forState:UIControlStateNormal];
  [self.accountButton addTarget:self action:@selector(openAccount) forControlEvents:UIControlEventTouchUpInside];
  self.status = [[UILabel alloc] init]; self.status.font = [PhoenixTheme regular:14]; self.status.textColor = [PhoenixTheme subtext]; self.status.numberOfLines = 2;
  for (UIView* view in @[self.greeting, self.accountButton, self.status]) [self.header addSubview:view];
  self.table.tableHeaderView = self.header;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:PhoenixPlayerChanged object:nil];
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
  self.greeting.frame = CGRectMake(16, 20, width - 90, 40);
  self.accountButton.frame = CGRectMake(width - 64, 18, 44, 44);
  self.status.frame = CGRectMake(16, 62, width - 32, 36);
  self.table.tableHeaderView = self.header;
}
- (void)playerChanged {
  PlayerModel* model = [PlayerModel shared];
  IPadPlayerSnapshot snapshot = model.snapshot;
  if (snapshot.state == IPadReady && !self.loadedOnce) { self.loadedOnce = YES; [self load]; }
  if (snapshot.state == IPadFailed) self.status.text = [NSString stringWithFormat:@"%s Close and reopen the app to reconnect.", snapshot.error];
  else if (snapshot.state == IPadConnecting) self.status.text = @"Connecting to Spotify…";
  else if (snapshot.state == IPadWaiting) self.status.text = @"No account yet. Tap the account icon to connect Spotify.";
}
- (void)load {
  self.status.text = @"Loading your music…";
  __weak HomeViewController* weakSelf = self;
  self.recentRequest = [[CatalogClient shared] request:@"recent" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) { owner.status.text = json[@"error"]; return; }
    NSMutableArray* items = [NSMutableArray arrayWithObject:@{@"uri": @"collection", @"name": @"Liked Songs", @"subtitle": @"Playlist", @"artwork": @"", @"type": @"collection"}];
    if ([json[@"items"] isKindOfClass:NSArray.class]) [items addObjectsFromArray:json[@"items"]];
    owner.recent = items;
    owner.status.text = done ? @"" : @"Loading…";
    [owner.table reloadData];
  }];
  self.profileRequest = [[CatalogClient shared] request:@"profile" argument:@"" update:^(NSDictionary* json, BOOL done) {
    HomeViewController* owner = weakSelf; if (!owner) return;
    NSString* name = json[@"name"];
    if ([name isKindOfClass:NSString.class] && name.length) owner.greeting.text = [NSString stringWithFormat:@"%@, %@", owner.greeting.text, [name componentsSeparatedByString:@" "].firstObject];
    NSMutableArray* tiles = [NSMutableArray array];
    if ([json[@"playlists"] isKindOfClass:NSArray.class])
      for (NSDictionary* playlist in json[@"playlists"])
        [tiles addObject:@{@"uri": playlist[@"uri"] ?: @"", @"name": playlist[@"name"] ?: @"", @"subtitle": playlist[@"owner"] ?: @"Playlist", @"artwork": playlist[@"artwork"] ?: @"", @"type": @"playlist"}];
    owner.playlists = tiles;
    [owner.table reloadData];
  }];
}
- (void)openAccount {
  UIViewController* setup = [[SetupViewController alloc] init];
  setup.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:setup animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return HomeCount; }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return (section == HomeRecent ? self.recent.count : self.playlists.count) ? 1 : 0; }
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = section == HomeRecent ? @"Recently played" : @"Your playlists";
  return header;
}
- (CGFloat)tableView:(UITableView*)table heightForRowAtIndexPath:(NSIndexPath*)path { return [ShelfCell height]; }
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  ShelfCell* shelf = [table dequeueReusableCellWithIdentifier:@"shelf" forIndexPath:path];
  shelf.items = path.section == HomeRecent ? self.recent : self.playlists;
  shelf.onSelect = ^(NSDictionary* item) {
    NSString* uri = item[@"uri"];
    if ([uri isEqualToString:@"collection"]) uri = @"spotify:user:me:collection";
    PhoenixOpen(uri, item[@"name"], item[@"artwork"]);
  };
  return shelf;
}
@end
