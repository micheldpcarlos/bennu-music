// SPDX-License-Identifier: GPL-3.0-or-later
#import "SearchViewController.h"
#import "PhoenixTheme.h"
#import "PhoenixCells.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
enum { SearchSongs = 0, SearchArtists, SearchAlbums, SearchCount };
enum { FilterAll = 0, FilterSongs, FilterArtists, FilterAlbums };
static NSString* const kRecentSearches = @"PhoenixRecentSearches";

// Genre tile used by the browse grid.
@interface CategoryCell : UICollectionViewCell
@property(nonatomic, strong) UILabel* nameLabel;
@end
@implementation CategoryCell
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.contentView.layer.cornerRadius = 8; self.contentView.clipsToBounds = YES;
    self.nameLabel = [[UILabel alloc] init]; self.nameLabel.font = [PhoenixTheme bold:19]; self.nameLabel.textColor = [PhoenixTheme text]; self.nameLabel.numberOfLines = 2;
    [self.contentView addSubview:self.nameLabel];
  }
  return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.nameLabel.frame = CGRectMake(14, 12, self.contentView.bounds.size.width - 28, 50); }
@end

@interface SearchViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property(nonatomic, strong) UIView* header;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UITextField* field;
@property(nonatomic, strong) UIButton* cancelButton;
@property(nonatomic, strong) UIScrollView* pills;
@property(nonatomic, strong) NSArray* pillButtons;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UICollectionView* browse;
@property(nonatomic, strong) NSArray* categories;     // @{name, color, query}
@property(nonatomic, strong) NSArray* recentSearches;
@property(nonatomic, strong) NSArray* tracks;
@property(nonatomic, strong) NSArray* artists;
@property(nonatomic, strong) NSArray* albums;
@property(nonatomic, strong) CatalogRequest* request;
@property(nonatomic, strong) NSTimer* debounce;
@property(nonatomic, copy) NSString* lastQuery;
@property(nonatomic) NSInteger filter;
@property(nonatomic) BOOL showingResults;
@end
@implementation SearchViewController
- (instancetype)init { if ((self = [super init])) self.isRoot = YES; return self; }
- (UIColor*)hex:(unsigned)value { return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0 green:((value >> 8) & 0xff) / 255.0 blue:(value & 0xff) / 255.0 alpha:1]; }
- (void)viewDidLoad {
  [super viewDidLoad];
  self.categories = @[
    @{@"name": @"Sertanejo", @"color": @0x8D67AB}, @{@"name": @"Pop", @"color": @0x148A08}, @{@"name": @"Hip-Hop", @"color": @0xBC5900},
    @{@"name": @"Rock", @"color": @0xE91429}, @{@"name": @"MPB", @"color": @0x1E3264}, @{@"name": @"Funk", @"color": @0xE13300},
    @{@"name": @"Samba & Pagode", @"color": @0xDC148C}, @{@"name": @"Eletrônica", @"color": @0x0D73EC}, @{@"name": @"Indie", @"color": @0x608108},
    @{@"name": @"Metal", @"color": @0x503750}, @{@"name": @"Jazz", @"color": @0x8C1932}, @{@"name": @"R&B", @"color": @0xAF2896},
    @{@"name": @"Reggae", @"color": @0x477D95}, @{@"name": @"Latina", @"color": @0xE1118C}, @{@"name": @"Clássica", @"color": @0x7D4B32},
    @{@"name": @"Lo-fi", @"color": @0x509BF5}, @{@"name": @"Forró", @"color": @0xF59B23}, @{@"name": @"Gospel", @"color": @0x006450},
    @{@"name": @"Anos 2000", @"color": @0xB02897}, @{@"name": @"Anos 80", @"color": @0x27856A}, @{@"name": @"Trap", @"color": @0x8E66AC}];
  self.recentSearches = [NSUserDefaults.standardUserDefaults arrayForKey:kRecentSearches] ?: @[];
  [self setupTable];
  self.table.dataSource = self; self.table.delegate = self;
  [self.table registerClass:TrackCell.class forCellReuseIdentifier:@"track"];
  UILongPressGestureRecognizer* press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
  press.minimumPressDuration = 0.5;
  [self.table addGestureRecognizer:press];
  [self.table registerClass:EntityCell.class forCellReuseIdentifier:@"entity"];
  [self.table registerClass:SectionHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
  self.table.rowHeight = 60;
  self.table.hidden = YES;
  UICollectionViewFlowLayout* layout = [[UICollectionViewFlowLayout alloc] init];
  layout.minimumInteritemSpacing = 12; layout.minimumLineSpacing = 12; layout.sectionInset = UIEdgeInsetsMake(8, 16, 24, 16);
  self.browse = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
  self.browse.backgroundColor = [PhoenixTheme background];
  self.browse.dataSource = self; self.browse.delegate = self;
  self.browse.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  [self.browse registerClass:CategoryCell.class forCellWithReuseIdentifier:@"category"];
  [self.browse registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"recent"];
  [self.browse registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"title"];
  [self.view insertSubview:self.browse belowSubview:self.topBar];
  self.header = [[UIView alloc] init];
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:30]; self.titleLabel.textColor = [PhoenixTheme text]; self.titleLabel.text = @"Search";
  self.field = [[UITextField alloc] init];
  self.field.backgroundColor = [UIColor whiteColor]; self.field.textColor = [UIColor blackColor];
  self.field.font = [PhoenixTheme regular:17]; self.field.layer.cornerRadius = 6;
  self.field.leftView = [[UIImageView alloc] initWithImage:[PhoenixTheme icon:@"search" size:22 color:[UIColor blackColor]]];
  self.field.leftView.frame = CGRectMake(0, 0, 40, 44); self.field.leftViewMode = UITextFieldViewModeAlways; self.field.leftView.contentMode = UIViewContentModeCenter;
  self.field.placeholder = @"What do you want to listen to?";
  self.field.returnKeyType = UIReturnKeySearch; self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
  self.field.autocorrectionType = UITextAutocorrectionTypeNo; self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.field.delegate = self;
  [self.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
  self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
  [self.cancelButton setTitleColor:[PhoenixTheme text] forState:UIControlStateNormal];
  self.cancelButton.titleLabel.font = [PhoenixTheme regular:17];
  [self.cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
  self.cancelButton.hidden = YES;
  self.pills = [[UIScrollView alloc] init]; self.pills.showsHorizontalScrollIndicator = NO;
  NSMutableArray* pillButtons = [NSMutableArray array]; CGFloat x = 0;
  NSArray* names = @[@"All", @"Songs", @"Artists", @"Albums"];
  for (NSUInteger i = 0; i < names.count; i++) {
    UIButton* pill = [UIButton buttonWithType:UIButtonTypeCustom];
    [pill setTitle:names[i] forState:UIControlStateNormal];
    pill.titleLabel.font = [PhoenixTheme regular:14];
    pill.layer.cornerRadius = 16; pill.layer.borderWidth = 1; pill.layer.borderColor = [PhoenixTheme cardHighlight].CGColor;
    pill.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    [pill sizeToFit]; pill.frame = CGRectMake(x, 0, pill.frame.size.width, 32); x += pill.frame.size.width + 8;
    pill.tag = (NSInteger)i;
    [pill addTarget:self action:@selector(pillTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.pills addSubview:pill]; [pillButtons addObject:pill];
  }
  self.pills.contentSize = CGSizeMake(x, 32);
  self.pillButtons = pillButtons;
  self.status = [[UILabel alloc] init]; self.status.font = [PhoenixTheme regular:14]; self.status.textColor = [PhoenixTheme subtext];
  for (UIView* view in @[self.titleLabel, self.field, self.cancelButton, self.pills, self.status]) [self.header addSubview:view];
  [self.view addSubview:self.header];
  [self stylePills];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:PhoenixTrackChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [self.request cancel]; [self.debounce invalidate]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  BOOL results = self.showingResults;
  CGFloat headerHeight = results ? 170 : 120;
  self.header.frame = CGRectMake(0, 20, width, headerHeight);
  self.titleLabel.frame = CGRectMake(16, 0, width - 32, 40);
  BOOL editing = self.field.isFirstResponder || self.field.text.length > 0;
  self.cancelButton.hidden = !editing;
  CGFloat fieldWidth = editing ? width - 32 - 76 : width - 32;
  self.field.frame = CGRectMake(16, 46, fieldWidth, 44);
  self.cancelButton.frame = CGRectMake(width - 16 - 68, 46, 68, 44);
  self.pills.frame = CGRectMake(16, 100, width - 32, 32);
  self.pills.hidden = !results;
  self.status.frame = CGRectMake(16, results ? 140 : 94, width - 32, 22);
  CGFloat top = 20 + headerHeight;
  self.table.frame = CGRectMake(0, top, width, height - top);
  self.browse.frame = CGRectMake(0, top, width, height - top);
  self.table.contentInset = UIEdgeInsetsMake(0, 0, [self bottomInset], 0);
  self.browse.contentInset = UIEdgeInsetsMake(0, 0, [self bottomInset], 0);
}
- (void)stylePills {
  for (UIButton* pill in self.pillButtons) {
    BOOL on = pill.tag == self.filter;
    pill.backgroundColor = on ? [PhoenixTheme green] : [PhoenixTheme card];
    [pill setTitleColor:on ? [UIColor blackColor] : [PhoenixTheme text] forState:UIControlStateNormal];
  }
}
- (void)pillTapped:(UIButton*)pill { self.filter = pill.tag; [self stylePills]; [self.table reloadData]; }
- (void)setShowingResults:(BOOL)showing {
  _showingResults = showing;
  self.table.hidden = !showing; self.browse.hidden = showing;
  [self.view setNeedsLayout];
}
- (BOOL)textFieldShouldReturn:(UITextField*)field { [field resignFirstResponder]; [self search]; return YES; }
- (void)textFieldDidBeginEditing:(UITextField*)field { [self.view setNeedsLayout]; }
- (void)textFieldDidEndEditing:(UITextField*)field { [self.view setNeedsLayout]; }
- (void)textChanged {
  [self.view setNeedsLayout];
  [self.debounce invalidate];
  if (self.field.text.length == 0) { [self showBrowse]; return; }
  self.debounce = [NSTimer scheduledTimerWithTimeInterval:0.7 target:self selector:@selector(search) userInfo:nil repeats:NO];
}
- (void)cancel {
  [self.debounce invalidate];
  [self.request cancel];
  self.field.text = @""; [self.field resignFirstResponder];
  [self showBrowse];
}
- (void)showBrowse {
  self.lastQuery = nil; self.tracks = @[]; self.artists = @[]; self.albums = @[];
  self.status.text = @"";
  self.showingResults = NO;
  [self.table reloadData];   // the hidden table must not keep rows pointing at the emptied arrays
  [self.browse reloadData];
}
- (void)rememberSearch:(NSString*)query {
  NSMutableArray* recent = [NSMutableArray arrayWithArray:self.recentSearches];
  [recent removeObject:query]; [recent insertObject:query atIndex:0];
  while (recent.count > 8) [recent removeLastObject];
  self.recentSearches = recent;
  [NSUserDefaults.standardUserDefaults setObject:recent forKey:kRecentSearches];
}
- (void)searchFor:(NSString*)query { [self view]; self.field.text = query; self.lastQuery = nil; [self.view setNeedsLayout]; [self search]; }
- (void)search {
  NSString* query = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (query.length < 2 || [query isEqualToString:self.lastQuery]) return;
  self.lastQuery = query;
  [self.request cancel];
  self.showingResults = YES;
  self.status.text = @"Searching…";
  [self rememberSearch:query];
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
- (void)playerChanged {
  if (self.table.hidden) return;
  for (UITableViewCell* cell in self.table.visibleCells) { NSIndexPath* path = [self.table indexPathForCell:cell]; if (path && path.section == SearchSongs && path.row < (NSInteger)self.tracks.count) [self configure:(TrackCell*)cell at:path]; }
}
- (void)longPress:(UILongPressGestureRecognizer*)gesture {
  if (gesture.state != UIGestureRecognizerStateBegan) return;
  NSIndexPath* path = [self.table indexPathForRowAtPoint:[gesture locationInView:self.table]];
  if (!path || path.section != SearchSongs || path.row >= (NSInteger)self.tracks.count) return;
  PhoenixTrackMenu(self, self.tracks[path.row], [self.table cellForRowAtIndexPath:path]);
}
// ---- results table
- (BOOL)sectionVisible:(NSInteger)section {
  if (self.filter == FilterAll) return YES;
  return (section == SearchSongs && self.filter == FilterSongs) || (section == SearchArtists && self.filter == FilterArtists) || (section == SearchAlbums && self.filter == FilterAlbums);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return SearchCount; }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  if (![self sectionVisible:section]) return 0;
  NSInteger count = section == SearchSongs ? self.tracks.count : section == SearchArtists ? self.artists.count : self.albums.count;
  if (self.filter == FilterAll && section != SearchSongs) count = MIN(count, 4);  // "All" shows a preview; pills show everything
  return count;
}
- (CGFloat)tableView:(UITableView*)table heightForHeaderInSection:(NSInteger)section { return [self tableView:table numberOfRowsInSection:section] ? 48 : 0; }
- (UIView*)tableView:(UITableView*)table viewForHeaderInSection:(NSInteger)section {
  SectionHeader* header = [table dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
  header.titleLabel.text = @[@"Songs", @"Artists", @"Albums"][section];
  return header;
}
- (void)configure:(TrackCell*)cell at:(NSIndexPath*)path {
  if (path.row >= (NSInteger)self.tracks.count) return;
  NSDictionary* track = self.tracks[path.row];
  NSString* playingId = @([PlayerModel shared].snapshot.trackId);
  [cell showTrack:track number:-1 playing:playingId.length && [track[@"id"] isEqualToString:playingId]];
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  if (path.section == SearchSongs) { TrackCell* cell = [table dequeueReusableCellWithIdentifier:@"track" forIndexPath:path]; [self configure:cell at:path]; return cell; }
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
// ---- browse grid: recent searches, then categories
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView*)view { return 2; }
- (NSInteger)collectionView:(UICollectionView*)view numberOfItemsInSection:(NSInteger)section { return section == 0 ? self.recentSearches.count : self.categories.count; }
- (CGSize)collectionView:(UICollectionView*)view layout:(UICollectionViewLayout*)layout sizeForItemAtIndexPath:(NSIndexPath*)path {
  CGFloat width = view.bounds.size.width - 32;
  if (path.section == 0) return CGSizeMake(width, 44);
  NSInteger columns = width > 700 ? 4 : width > 480 ? 3 : 2;
  CGFloat tile = (width - 12 * (columns - 1)) / columns;
  return CGSizeMake(floor(tile), 96);
}
- (CGSize)collectionView:(UICollectionView*)view layout:(UICollectionViewLayout*)layout referenceSizeForHeaderInSection:(NSInteger)section {
  return CGSizeMake(view.bounds.size.width, (section == 0 && self.recentSearches.count == 0) ? 0 : 44);
}
- (UICollectionReusableView*)collectionView:(UICollectionView*)view viewForSupplementaryElementOfKind:(NSString*)kind atIndexPath:(NSIndexPath*)path {
  UICollectionReusableView* header = [view dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"title" forIndexPath:path];
  UILabel* label = (UILabel*)[header viewWithTag:7];
  if (!label) { label = [[UILabel alloc] init]; label.tag = 7; label.font = [PhoenixTheme bold:20]; label.textColor = [PhoenixTheme text]; [header addSubview:label]; }
  label.frame = CGRectMake(16, 10, view.bounds.size.width - 32, 28);
  label.text = path.section == 0 ? @"Recent searches" : @"Browse all";
  return header;
}
- (UICollectionViewCell*)collectionView:(UICollectionView*)view cellForItemAtIndexPath:(NSIndexPath*)path {
  if (path.section == 0) {
    UICollectionViewCell* cell = [view dequeueReusableCellWithReuseIdentifier:@"recent" forIndexPath:path];
    UILabel* label = (UILabel*)[cell.contentView viewWithTag:8];
    if (!label) {
      label = [[UILabel alloc] init]; label.tag = 8; label.font = [PhoenixTheme regular:17]; label.textColor = [PhoenixTheme text]; [cell.contentView addSubview:label];
      UIImageView* icon = [[UIImageView alloc] initWithImage:[PhoenixTheme icon:@"search" size:20 color:[PhoenixTheme subtext]]]; icon.tag = 9; [cell.contentView addSubview:icon];
    }
    [cell.contentView viewWithTag:9].frame = CGRectMake(0, 12, 20, 20);
    label.frame = CGRectMake(32, 0, cell.contentView.bounds.size.width - 32, 44);
    label.text = self.recentSearches[path.item];
    return cell;
  }
  CategoryCell* cell = [view dequeueReusableCellWithReuseIdentifier:@"category" forIndexPath:path];
  NSDictionary* category = self.categories[path.item];
  cell.contentView.backgroundColor = [self hex:[category[@"color"] unsignedIntValue]];
  cell.nameLabel.text = category[@"name"];
  return cell;
}
- (void)collectionView:(UICollectionView*)view didSelectItemAtIndexPath:(NSIndexPath*)path {
  NSString* query = path.section == 0 ? self.recentSearches[path.item] : self.categories[path.item][@"name"];
  [self searchFor:query];
}
@end
