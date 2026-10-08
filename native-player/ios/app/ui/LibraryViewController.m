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
  [self.header addSubview:self.titleLabel]; [self.header addSubview:self.status];
  self.table.tableHeaderView = self.header;
  [self rebuild];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:BennuTrackChanged object:nil];
  [self playerChanged];   // the view may be created after the engine is already Ready; the notification only fires on changes
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  self.header.frame = CGRectMake(0, 0, width, 90);
  self.titleLabel.frame = CGRectMake(16, 20, width - 32, 40);
  self.status.frame = CGRectMake(16, 62, width - 32, 20);
  self.table.tableHeaderView = self.header;
}
- (void)playerChanged {
  if ([PlayerModel shared].ready && !self.loadedOnce) { self.loadedOnce = YES; [self load]; }
  if ([PlayerModel shared].snapshot.state == IPadWaiting && self.loadedOnce) { self.loadedOnce = NO; self.playlists = nil; self.recent = nil; [self rebuild]; }
}
- (void)load {
  self.status.text = @"Loading…";
  __weak LibraryViewController* weakSelf = self;
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
- (void)rebuild {
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
