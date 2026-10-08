// SPDX-License-Identifier: GPL-3.0-or-later
#import "LibraryViewController.h"
#import "BennuTheme.h"
#import "BennuCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
@interface LibraryViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSArray* items;   // dictionaries: uri, name, subtitle, artwork, type
@property(nonatomic, strong) CatalogRequest* profileRequest;
@property(nonatomic, strong) CatalogRequest* recentRequest;
@property(nonatomic, strong) NSArray* playlists;
@property(nonatomic, strong) NSArray* recent;
@property(nonatomic, strong) CatalogRequest* libraryRequest;
@property(nonatomic, strong) NSArray* libraryItems;   // everything saved, from the web player service; nil -> fallback shelves
@property(nonatomic, strong) UIScrollView* pills;
@property(nonatomic, strong) NSArray* pillButtons;
@property(nonatomic) NSInteger filter;   // 0 all, 1 playlists, 2 albums, 3 artists
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic) BOOL loadedOnce;
@end
@implementation LibraryViewController
- (instancetype)init { if ((self = [super init])) self.isRoot = YES; return self; }
- (void)viewDidLoad {
  [super viewDidLoad];
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  self.table.rowHeight = 72;
  [self.table registerClass:EntityCell.class forCellReuseIdentifier:@"entity"];
  self.header = [[UIView alloc] init];
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [BennuTheme bold:30]; self.titleLabel.textColor = [BennuTheme text]; self.titleLabel.text = @"Your Library";
  self.status = [[UILabel alloc] init]; self.status.font = [BennuTheme regular:14]; self.status.textColor = [BennuTheme subtext];
  self.pills = [[UIScrollView alloc] init]; self.pills.showsHorizontalScrollIndicator = NO;
  NSMutableArray* pillButtons = [NSMutableArray array]; CGFloat x = 0;
  NSArray* names = @[@"All", @"Playlists", @"Albums", @"Artists"];
  for (NSUInteger i = 0; i < names.count; i++) {
    UIButton* pill = [UIButton buttonWithType:UIButtonTypeCustom];
    [pill setTitle:names[i] forState:UIControlStateNormal];
    pill.titleLabel.font = [BennuTheme regular:14];
    pill.layer.cornerRadius = 16; pill.layer.borderWidth = 1; pill.layer.borderColor = [BennuTheme cardHighlight].CGColor;
    pill.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    [pill sizeToFit]; pill.frame = CGRectMake(x, 0, pill.frame.size.width, 32); x += pill.frame.size.width + 8;
    pill.tag = (NSInteger)i;
    [pill addTarget:self action:@selector(pillTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.pills addSubview:pill]; [pillButtons addObject:pill];
  }
  self.pills.contentSize = CGSizeMake(x, 32); self.pillButtons = pillButtons; self.pills.hidden = YES;
  [self.header addSubview:self.titleLabel]; [self.header addSubview:self.status]; [self.header addSubview:self.pills];
  [self stylePills];
  self.table.tableHeaderView = self.header;
  [self rebuild];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:BennuTrackChanged object:nil];
  [self playerChanged];   // the view may be created after the engine is already Ready; the notification only fires on changes
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  BOOL filters = !self.pills.hidden;
  self.header.frame = CGRectMake(0, 0, width, filters ? 130 : 90);
  self.titleLabel.frame = CGRectMake(16, 20, width - 32, 40);
  self.status.frame = CGRectMake(16, 62, width - 32, 20);
  self.pills.frame = CGRectMake(16, 88, width - 32, 32);
  self.table.tableHeaderView = self.header;
}
- (void)playerChanged {
  if ([PlayerModel shared].ready && !self.loadedOnce) { self.loadedOnce = YES; [self load]; }
  if ([PlayerModel shared].snapshot.state == IPadWaiting && self.loadedOnce) { self.loadedOnce = NO; self.playlists = nil; self.recent = nil; self.libraryItems = nil; self.pills.hidden = YES; [self rebuild]; }
}
- (void)load {
  self.status.text = @"Loading…";
  __weak LibraryViewController* weakSelf = self;
  // Preferred: everything saved, with types, from the web player service. The rootlist and
  // recently played requests below stay as the fallback when it is paused or fails.
  self.libraryRequest = [[CatalogClient shared] request:@"library" argument:@"" update:^(NSDictionary* json, BOOL done) {
    LibraryViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"] || ![json[@"items"] isKindOfClass:NSArray.class] || [json[@"items"] count] == 0) return;
    owner.libraryItems = json[@"items"]; owner.pills.hidden = NO; owner.status.text = @"";
    [owner.view setNeedsLayout]; [owner rebuild];
  }];
  self.profileRequest = [[CatalogClient shared] request:@"playlists" argument:@"" update:^(NSDictionary* json, BOOL done) {
    LibraryViewController* owner = weakSelf; if (!owner) return;
    NSMutableArray* list = [NSMutableArray array];
    if ([json[@"playlists"] isKindOfClass:NSArray.class])
      for (NSDictionary* playlist in json[@"playlists"]) {
        NSNumber* count = playlist[@"count"];
        [list addObject:@{@"uri": playlist[@"uri"] ?: @"", @"name": playlist[@"name"] ?: @"", @"subtitle": [count intValue] ? [NSString stringWithFormat:@"Playlist • %d songs", [count intValue]] : @"Playlist", @"artwork": playlist[@"artwork"] ?: @"", @"type": @"playlist"}];
      }
    owner.playlists = list; [owner rebuild];
  }];
  self.recentRequest = [[CatalogClient shared] request:@"recent" argument:@"" update:^(NSDictionary* json, BOOL done) {
    LibraryViewController* owner = weakSelf; if (!owner) return;
    NSMutableArray* list = [NSMutableArray array];
    if ([json[@"items"] isKindOfClass:NSArray.class])
      for (NSDictionary* item in json[@"items"]) {
        NSString* type = item[@"type"];
        NSString* subtitle = [type isEqualToString:@"album"] ? [NSString stringWithFormat:@"Album • %@", item[@"subtitle"] ?: @""] : [type isEqualToString:@"artist"] ? @"Artist" : @"Playlist";
        [list addObject:@{@"uri": item[@"uri"] ?: @"", @"name": item[@"name"] ?: @"", @"subtitle": subtitle, @"artwork": item[@"artwork"] ?: @"", @"type": type ?: @""}];
      }
    owner.recent = list; owner.status.text = done ? @"" : @"Loading…"; [owner rebuild];
  }];
}
- (void)stylePills {
  for (UIButton* pill in self.pillButtons) {
    BOOL on = pill.tag == self.filter;
    pill.backgroundColor = on ? [BennuTheme green] : [BennuTheme card];
    [pill setTitleColor:on ? [UIColor blackColor] : [BennuTheme text] forState:UIControlStateNormal];
  }
}
- (void)pillTapped:(UIButton*)pill { self.filter = pill.tag; [self stylePills]; [self rebuild]; }
- (void)rebuild {
  if (self.libraryItems) {
    NSString* wanted = @[@"", @"playlist", @"album", @"artist"][self.filter];
    NSMutableArray* list = [NSMutableArray array]; BOOL hasCollection = NO;
    for (NSDictionary* item in self.libraryItems) {
      NSString* type = item[@"type"];
      if ([type isEqualToString:@"collection"]) hasCollection = YES;
      if (wanted.length && !([type isEqualToString:wanted] || (self.filter == 1 && [type isEqualToString:@"collection"]))) continue;
      [list addObject:item];
    }
    if (!hasCollection && self.filter <= 1) [list insertObject:@{@"uri": @"spotify:user:me:collection", @"name": @"Liked Songs", @"subtitle": @"Playlist", @"artwork": @"", @"type": @"collection"} atIndex:0];
    self.items = list; [self.table reloadData]; return;
  }
  NSMutableArray* items = [NSMutableArray arrayWithObject:@{@"uri": @"spotify:user:me:collection", @"name": @"Liked Songs", @"subtitle": @"Playlist", @"artwork": @"", @"type": @"collection"}];
  NSMutableSet* seen = [NSMutableSet set];
  for (NSDictionary* item in [self.playlists arrayByAddingObjectsFromArray:self.recent ?: @[]] ?: self.recent) {
    if ([seen containsObject:item[@"uri"]] || [item[@"type"] isEqualToString:@"collection"]) continue;
    [seen addObject:item[@"uri"]]; [items addObject:item];
  }
  self.items = items;
  [self.table reloadData];
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  EntityCell* cell = [table dequeueReusableCellWithIdentifier:@"entity" forIndexPath:path];
  NSDictionary* item = self.items[path.row];
  BOOL collection = [item[@"type"] isEqualToString:@"collection"];
  [cell showTitle:item[@"name"] subtitle:item[@"subtitle"] artwork:item[@"artwork"]
      placeholder:collection ? [BennuTheme likedSongsArt:60] : [BennuTheme placeholderArt:60] round:[item[@"type"] isEqualToString:@"artist"]];
  return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  NSDictionary* item = self.items[path.row];
  BennuOpen(item[@"uri"], item[@"name"], item[@"artwork"]);
}
@end
