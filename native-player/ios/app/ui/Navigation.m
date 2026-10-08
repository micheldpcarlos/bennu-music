// SPDX-License-Identifier: GPL-3.0-or-later
#import "Navigation.h"
#import "BennuTheme.h"
#import "MainTabController.h"
#import "ListViewController.h"
#import "ArtistViewController.h"
#import "PlayerModel.h"
void BennuOpen(NSString* uri, NSString* name, NSString* artwork) {
  if (![uri isKindOfClass:NSString.class]) return;
  UIViewController* screen = nil;
  if ([uri hasPrefix:@"spotify:album:"]) screen = [[ListViewController alloc] initWithKind:@"album" uri:uri name:name artwork:artwork];
  else if ([uri hasPrefix:@"spotify:playlist:"]) screen = [[ListViewController alloc] initWithKind:@"playlist" uri:uri name:name artwork:artwork];
  else if ([uri hasSuffix:@":collection"]) screen = [[ListViewController alloc] initWithKind:@"collection" uri:uri name:@"Liked Songs" artwork:nil];
  else if ([uri hasPrefix:@"spotify:artist:"]) screen = [[ArtistViewController alloc] initWithURI:uri name:name];
  if (screen) [[MainTabController shared] push:screen];
}
void BennuTrackMenu(UIViewController* from, NSDictionary* track, UIView* anchor) {
  if (![track isKindOfClass:NSDictionary.class]) return;
  NSString* title = [track[@"title"] isKindOfClass:NSString.class] ? track[@"title"] : @"Track";
  UIAlertController* sheet = [UIAlertController alertControllerWithTitle:title message:track[@"artist"] preferredStyle:UIAlertControllerStyleActionSheet];
  [sheet addAction:[UIAlertAction actionWithTitle:@"Play next" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
    if (![[PlayerModel shared] addToQueue:track[@"uri"]]) {
      UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Nothing is playing" message:@"Start a song first, then add tracks to play next." preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
      [from presentViewController:alert animated:YES completion:nil];
    }
  }]];
  if ([track[@"albumUri"] isKindOfClass:NSString.class])
    [sheet addAction:[UIAlertAction actionWithTitle:@"Go to album" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) { BennuOpen(track[@"albumUri"], track[@"album"], track[@"artwork"]); }]];
  NSArray* artists = track[@"artists"];
  if ([artists isKindOfClass:NSArray.class])
    for (NSDictionary* artist in artists)
      if ([artist[@"uri"] isKindOfClass:NSString.class])
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Go to %@", artist[@"name"]] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) { BennuOpen(artist[@"uri"], artist[@"name"], nil); }]];
  [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = anchor;
  sheet.popoverPresentationController.sourceRect = anchor.bounds;
  [from presentViewController:sheet animated:YES completion:nil];
}
@implementation BennuViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [BennuTheme background];
  self.topBar = [[UIView alloc] init];
  self.topBar.backgroundColor = [BennuTheme background];
  [self.view addSubview:self.topBar];
  self.topTitle = [[UILabel alloc] init];
  self.topTitle.font = [BennuTheme bold:17]; self.topTitle.textColor = [BennuTheme text]; self.topTitle.textAlignment = NSTextAlignmentCenter;
  [self.topBar addSubview:self.topTitle];
  self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.backButton setImage:[BennuTheme icon:@"chevronLeft" size:28 color:[BennuTheme text]] forState:UIControlStateNormal];
  [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
  [self.topBar addSubview:self.backButton];
  self.backButton.hidden = self.isRoot;
}
- (void)setupTable {
  self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.table.backgroundColor = [BennuTheme background];
  self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
  [self.view insertSubview:self.table belowSubview:self.topBar];
}
- (CGFloat)bottomInset { return 72; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  CGFloat barHeight = self.isRoot ? 20 : 64;
  self.topBar.frame = CGRectMake(0, 0, width, barHeight);
  self.backButton.frame = CGRectMake(8, 20, 44, 44);
  self.topTitle.frame = CGRectMake(60, 20, width - 120, 44);
  self.table.frame = CGRectMake(0, barHeight, width, height - barHeight);
  self.table.contentInset = UIEdgeInsetsMake(0, 0, [self bottomInset], 0);
  self.table.scrollIndicatorInsets = self.table.contentInset;
}
- (void)goBack { [self.navigationController popViewControllerAnimated:YES]; }
@end
