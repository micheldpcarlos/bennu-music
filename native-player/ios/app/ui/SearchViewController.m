// SPDX-License-Identifier: GPL-3.0-or-later
#import "SearchViewController.h"
#import "PhoenixTheme.h"
#import "PhoenixCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
enum { SearchSongs = 0, SearchArtists, SearchAlbums, SearchCount };
@interface SearchViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UITextField* field;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) NSArray* tracks;
@property(nonatomic, strong) NSArray* artists;
@property(nonatomic, strong) NSArray* albums;
@property(nonatomic, strong) CatalogRequest* request;
@property(nonatomic, strong) NSTimer* debounce;
@property(nonatomic, copy) NSString* lastQuery;
@end
@implementation SearchViewController
- (instancetype)init { if ((self = [super init])) self.isRoot = YES; return self; }
- (void)viewDidLoad {
  [super viewDidLoad];
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  [self.table registerClass:TrackCell.class forCellReuseIdentifier:@"track"];
  [self.table registerClass:EntityCell.class forCellReuseIdentifier:@"entity"];
  [self.table registerClass:SectionHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
  self.table.rowHeight = 60;
  self.header = [[UIView alloc] init];
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:30]; self.titleLabel.textColor = [PhoenixTheme text]; self.titleLabel.text = @"Search";
  self.field = [[UITextField alloc] init];
  self.field.backgroundColor = [UIColor whiteColor]; self.field.textColor = [UIColor blackColor];
  self.field.font = [PhoenixTheme regular:17];
  self.field.layer.cornerRadius = 6;
  self.field.leftView = [[UIImageView alloc] initWithImage:[PhoenixTheme icon:@"search" size:22 color:[UIColor blackColor]]];
  self.field.leftView.frame = CGRectMake(0, 0, 40, 44); self.field.leftViewMode = UITextFieldViewModeAlways;
  self.field.leftView.contentMode = UIViewContentModeCenter;
  self.field.placeholder = @"What do you want to listen to?";
  self.field.returnKeyType = UIReturnKeySearch; self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
  self.field.autocorrectionType = UITextAutocorrectionTypeNo; self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.field.delegate = self;
  [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
  self.status = [[UILabel alloc] init]; self.status.font = [PhoenixTheme regular:14]; self.status.textColor = [PhoenixTheme subtext];
  for (UIView* view in @[self.titleLabel, self.field, self.status]) [self.header addSubview:view];
  self.table.tableHeaderView = self.header;
  self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:PhoenixPlayerChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.request cancel]; [self.debounce invalidate]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  self.header.frame = CGRectMake(0, 0, width, 130);
  self.titleLabel.frame = CGRectMake(16, 20, width - 32, 40);
  self.field.frame = CGRectMake(16, 66, width - 32, 44);
  self.status.frame = CGRectMake(16, 112, width - 32, 18);
  self.table.tableHeaderView = self.header;
}
- (BOOL)textFieldShouldReturn:(UITextField*)field { [field resignFirstResponder]; [self search]; return YES; }
- (void)textChanged {
  [self.debounce invalidate];
  self.debounce = [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(search) userInfo:nil repeats:NO];
}
- (void)searchFor:(NSString*)query { [self view]; self.field.text = query; self.lastQuery = nil; [self search]; }
- (void)search {
  NSString* query = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (query.length < 2 || [query isEqualToString:self.lastQuery]) return;
  self.lastQuery = query;
  [self.request cancel];
  self.status.text = @"Searching…";
  __weak SearchViewController* weakSelf = self;
  self.request = [[CatalogClient shared] request:@"search" argument:query update:^(NSDictionary* json, BOOL done) {
    SearchViewController* owner = weakSelf; if (!owner) return;
    if (json[@"error"]) { owner.status.text = json[@"error"]; return; }
    owner.tracks = [json[@"tracks"] isKindOfClass:NSArray.class] ? json[@"tracks"] : @[];
    owner.artists = [json[@"artists"] isKindOfClass:NSArray.class] ? json[@"artists"] : @[];
    owner.albums = [json[@"albums"] isKindOfClass:NSArray.class] ? json[@"albums"] : @[];
    owner.status.text = done ? (owner.tracks.count ? @"" : @"No results.") : @"Searching…";
    [owner.table reloadData];
  }];
}
- (void)playerChanged { for (UITableViewCell* cell in self.table.visibleCells) { NSIndexPath* path = [self.table indexPathForCell:cell]; if (path && path.section == SearchSongs) [self configure:(TrackCell*)cell at:path]; } }
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return SearchCount; }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  return section == SearchSongs ? self.tracks.count : section == SearchArtists ? self.artists.count : self.albums.count;
}
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = @[@"Songs", @"Artists", @"Albums"][section];
  return header;
}
- (void)configure:(TrackCell*)cell at:(NSIndexPath*)path {
  NSDictionary* track = self.tracks[path.row];
  NSString* playingId = @([PlayerModel shared].snapshot.trackId);
  [cell showTrack:track number:-1 playing:playingId.length && [track[@"id"] isEqualToString:playingId]];
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  if (path.section == SearchSongs) {
    TrackCell* cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path];
    [self configure:cell at:path]; return cell;
  }
  EntityCell* cell = [table dequeueReusableCellWithIdentifier:@"entity" forIndexPath:path];
  if (path.section == SearchArtists) {
    NSDictionary* artist = self.artists[path.row];
    [cell showTitle:artist[@"name"] subtitle:@"Artist" artwork:artist[@"image"] placeholder:[PhoenixTheme placeholderArt:48] round:YES];
  } else {
    NSDictionary* album = self.albums[path.row];
    [cell showTitle:album[@"name"] subtitle:[NSString stringWithFormat:@"Album • %@", album[@"artist"] ?: @""] artwork:album[@"artwork"] placeholder:[PhoenixTheme placeholderArt:48] round:NO];
  }
  return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  [self.field resignFirstResponder];
  if (path.section == SearchSongs) {
    NSMutableArray* uris = [NSMutableArray array];
    for (NSDictionary* track in self.tracks) if ([track[@"uri"] isKindOfClass:NSString.class]) [uris addObject:track[@"uri"]];
    [[PlayerModel shared] playURIs:uris index:path.row contextUri:@"" contextName:[NSString stringWithFormat:@"Search: %@", self.lastQuery]];
  } else if (path.section == SearchArtists) {
    NSDictionary* artist = self.artists[path.row]; PhoenixOpen(artist[@"uri"], artist[@"name"], artist[@"image"]);
  } else {
    NSDictionary* album = self.albums[path.row]; PhoenixOpen(album[@"uri"], album[@"name"], album[@"artwork"]);
  }
}
@end
