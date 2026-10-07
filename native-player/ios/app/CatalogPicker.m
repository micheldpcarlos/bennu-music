// SPDX-License-Identifier: GPL-3.0-or-later
#import "CatalogPicker.h"
#import "../PlayerBridge.h"
static NSString* lastCatalogQuery;
@interface CatalogPicker : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UILabel* heading;
@property(nonatomic, strong) UILabel* status;
@property(nonatomic, strong) UITextField* query;
@property(nonatomic, strong) UIButton* searchButton;
@property(nonatomic, strong) UIButton* closeButton;
@property(nonatomic, strong) UITableView* table;
@property(nonatomic, strong) NSArray* tracks;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic) uint64_t revision;
@property(nonatomic) NSTimeInterval retryAt;
@property(nonatomic) BOOL quotaBlocked;
@end
@implementation CatalogPicker
- (UIButton*)button:(NSString*)title action:(SEL)action {
  UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:title forState:UIControlStateNormal];
  button.titleLabel.font = [UIFont systemFontOfSize:18];
  [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:button]; return button;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
  self.heading = [[UILabel alloc] init];
  self.heading.text = @"Spotify Music";
  self.heading.textColor = [UIColor whiteColor];
  self.heading.font = [UIFont boldSystemFontOfSize:24];
  [self.view addSubview:self.heading];
  self.query = [[UITextField alloc] init];
  self.query.borderStyle = UITextBorderStyleRoundedRect;
  self.query.backgroundColor = [UIColor whiteColor];
  self.query.textColor = [UIColor blackColor];
  self.query.text = lastCatalogQuery ?: @"Luiz Gonzaga";
  self.query.placeholder = @"Song or artist";
  self.query.returnKeyType = UIReturnKeySearch;
  self.query.delegate = self;
  self.query.autocorrectionType = UITextAutocorrectionTypeNo;
  [self.view addSubview:self.query];
  self.searchButton = [self button:@"Search" action:@selector(search)];
  self.closeButton = [self button:@"Back" action:@selector(close)];
  self.status = [[UILabel alloc] init];
  self.status.textColor = [UIColor colorWithWhite:0.8 alpha:1];
  self.status.numberOfLines = 3;
  self.status.font = [UIFont systemFontOfSize:16];
  [self.view addSubview:self.status];
  self.tracks = @[];
  self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.table.backgroundColor = self.view.backgroundColor;
  self.table.separatorColor = [UIColor darkGrayColor];
  self.table.rowHeight = 72;
  self.table.dataSource = self; self.table.delegate = self;
  self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.view addSubview:self.table];
  [self search];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  self.heading.frame = CGRectMake(24, 32, width - 190, 48);
  self.closeButton.frame = CGRectMake(width - 134, 32, 110, 44);
  self.query.frame = CGRectMake(24, 96, width - 150, 44);
  self.searchButton.frame = CGRectMake(width - 110, 96, 86, 44);
  self.status.frame = CGRectMake(24, 149, width - 48, 56);
  self.table.frame = CGRectMake(24, 214, width - 48, height - 238);
}
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(poll)
      userInfo:nil repeats:YES];
  [self poll];
}
- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated]; [self.timer invalidate]; self.timer = nil;
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)textFieldShouldReturn:(UITextField*)textField { [self search]; return YES; }
- (void)search {
  [self.view endEditing:YES];
  NSString* query = [self.query.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (query.length == 0) { self.status.text = @"Enter a song or artist name."; return; }
  lastCatalogQuery = [query copy];
  if (!ipad_player_search(query.UTF8String)) {
    self.status.text = @"Wait for the session to connect or the current search to finish."; return;
  }
  self.searchButton.enabled = NO;
  self.status.text = @"Searching Spotify…";
  [self poll];
}
- (void)poll {
  if (self.retryAt > 0) {
    NSTimeInterval remaining = self.retryAt - [[NSDate date] timeIntervalSince1970];
    NSInteger seconds = remaining > 0 ? (NSInteger)remaining + 1 : 0;
    self.searchButton.enabled = seconds <= 0 && !self.quotaBlocked;
    self.status.text = seconds > 0 ? [NSString stringWithFormat:@"Spotify limited search. Try again in %ld seconds.", (long)seconds] : @"You can search again now.";
    if (seconds <= 0) self.retryAt = 0;
  }
  char buffer[65536];
  uint64_t revision = ipad_player_catalog_snapshot(buffer, sizeof(buffer));
  if (!revision || revision == self.revision || !buffer[0]) return;
  self.revision = revision;
  NSData* data = [[NSString stringWithUTF8String:buffer] dataUsingEncoding:NSUTF8StringEncoding];
  if (!data) return;
  NSDictionary* response = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![response isKindOfClass:[NSDictionary class]]) return;
  NSArray* rows = response[@"tracks"];
  NSMutableArray* tracks = [NSMutableArray array];
  if ([rows isKindOfClass:[NSArray class]]) {
    for (id row in rows) if ([row isKindOfClass:[NSDictionary class]]) [tracks addObject:row];
  }
  self.tracks = tracks;
  self.retryAt = [response[@"retry_at"] respondsToSelector:@selector(doubleValue)] ? [response[@"retry_at"] doubleValue] : 0;
  self.quotaBlocked = [response[@"quota_blocked"] respondsToSelector:@selector(boolValue)] && [response[@"quota_blocked"] boolValue];
  BOOL busy = [response[@"busy"] respondsToSelector:@selector(boolValue)] && [response[@"busy"] boolValue];
  self.searchButton.enabled = !busy && !self.quotaBlocked && self.retryAt <= [[NSDate date] timeIntervalSince1970];
  if ([response[@"message"] isKindOfClass:[NSString class]]) self.status.text = response[@"message"];
  [self.table reloadData];
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section { return self.tracks.count; }
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)index {
  UITableViewCell* cell = [table dequeueReusableCellWithIdentifier:@"track"];
  if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"track"];
  NSDictionary* track = self.tracks[index.row];
  cell.backgroundColor = self.view.backgroundColor;
  cell.textLabel.textColor = [UIColor whiteColor];
  cell.detailTextLabel.textColor = [UIColor lightGrayColor];
  cell.textLabel.text = track[@"title"];
  NSString* album = track[@"album"];
  cell.detailTextLabel.text = album.length ? [NSString stringWithFormat:@"%@ • %@", track[@"artist"], album] : track[@"artist"];
  cell.accessoryType = UITableViewCellAccessoryDetailButton;
  return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)index {
  [table deselectRowAtIndexPath:index animated:YES];
  NSString* uri = self.tracks[index.row][@"uri"];
  if ([uri isKindOfClass:[NSString class]] && ipad_player_select_track(uri.UTF8String)) [self close];
  else self.status.text = @"Player unavailable. Wait for the connection and try again.";
}
- (void)tableView:(UITableView*)table accessoryButtonTappedForRowWithIndexPath:(NSIndexPath*)index {
  NSString* address = self.tracks[index.row][@"url"];
  if ([address isKindOfClass:[NSString class]] && [address hasPrefix:@"https://open.spotify.com/track/"])
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:address]];
}
@end
UIViewController* ipad_catalog_picker_controller(void) { return [[CatalogPicker alloc] init]; }
