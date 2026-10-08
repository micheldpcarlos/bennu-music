// SPDX-License-Identifier: GPL-3.0-or-later
#import "QueueViewController.h"
#import "BennuTheme.h"
#import "BennuCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
@interface QueueViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) NSArray* uris;
@property(nonatomic, strong) NSDictionary* tracksByUri;
@property(nonatomic, strong) CatalogRequest* request;
@property(nonatomic, strong) UIButton* closeButton;
@end
@implementation QueueViewController
- (instancetype)init { if ((self = [super init])) self.isRoot = YES; return self; }
- (void)viewDidLoad {
  [super viewDidLoad];
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self; self.table.rowHeight = 56;
  [self.table registerClass:TrackCell.class forCellReuseIdentifier:@"track"];
  [self.table registerClass:SectionHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
  self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.closeButton setImage:[BennuTheme icon:@"chevronDown" size:28 color:[BennuTheme text]] forState:UIControlStateNormal];
  [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.closeButton];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:BennuTrackChanged object:nil];
  [self reload];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.request cancel]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  self.closeButton.frame = CGRectMake(16, 24, 44, 44);
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  self.table.frame = CGRectMake(0, 72, width, height - 72);
}
- (CGFloat)bottomInset { return 24; }
- (void)reload {
  self.uris = [[PlayerModel shared] queueURIs];
  if (!self.uris.count) { [self.table reloadData]; return; }
  __weak QueueViewController* weakSelf = self;
  self.request = [[CatalogClient shared] request:@"tracks" argument:[self.uris componentsJoinedByString:@","] update:^(NSDictionary* json, BOOL done) {
    QueueViewController* owner = weakSelf; if (!owner) return;
    NSMutableDictionary* byUri = [NSMutableDictionary dictionary];
    for (NSDictionary* track in [json[@"tracks"] isKindOfClass:NSArray.class] ? json[@"tracks"] : @[]) if ([track[@"uri"] isKindOfClass:NSString.class]) byUri[track[@"uri"]] = track;
    owner.tracksByUri = byUri;
    [owner.table reloadData];
  }];
}
- (NSInteger)currentIndex {
  NSString* playing = @([PlayerModel shared].snapshot.trackId);
  for (NSUInteger i = 0; i < self.uris.count; i++) if ([self.uris[i] hasSuffix:playing] && playing.length) return (NSInteger)i;
  return -1;
}
- (void)playerChanged {
  NSArray* latest = [[PlayerModel shared] queueURIs];
  if (![latest isEqualToArray:self.uris]) { [self reload]; return; }
  for (UITableViewCell* cell in self.table.visibleCells) { NSIndexPath* path = [self.table indexPathForCell:cell]; if (path) [self configure:(TrackCell*)cell at:path]; }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return 2; }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  NSInteger current = [self currentIndex];
  if (section == 0) return current >= 0 ? 1 : 0;
  return current >= 0 ? MAX(0, (NSInteger)self.uris.count - current - 1) : (NSInteger)self.uris.count;
}
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = section == 0 ? @"Now playing" : @"Next up";
  return header;
}
- (NSInteger)uriIndexFor:(NSIndexPath*)path {
  NSInteger current = [self currentIndex];
  if (path.section == 0) return current;
  return current >= 0 ? current + 1 + path.row : path.row;
}
- (void)configure:(TrackCell*)cell at:(NSIndexPath*)path {
  NSInteger index = [self uriIndexFor:path];
  if (index < 0 || index >= (NSInteger)self.uris.count) return;
  NSString* uri = self.uris[index];
  NSDictionary* track = self.tracksByUri[uri] ?: @{@"uri": uri, @"title": @"", @"artist": @"", @"loading": @YES};
  [cell showTrack:track number:-1 playing:path.section == 0];
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  TrackCell* cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path];
  [self configure:cell at:path]; return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  NSInteger index = [self uriIndexFor:path];
  if (path.section == 0 || index < 0) return;
  PlayerModel* model = [PlayerModel shared];
  [model playURIs:self.uris index:(NSUInteger)index contextUri:model.contextUri contextName:model.contextName];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end
