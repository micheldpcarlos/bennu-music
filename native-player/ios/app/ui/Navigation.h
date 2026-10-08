// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Opens the screen for any Spotify entity uri (album, playlist, artist, liked-songs collection).
void PhoenixOpen(NSString* uri, NSString* name, NSString* artwork);
// Action sheet for a track row: play next, go to album, go to artist.
void PhoenixTrackMenu(UIViewController* from, NSDictionary* track, UIView* anchor);
// Base class: dark background, custom top bar with back button and title on pushed screens.
@interface PhoenixViewController : UIViewController
@property(nonatomic, strong) UITableView* table;
@property(nonatomic, strong) UIView* topBar;
@property(nonatomic, strong) UILabel* topTitle;
@property(nonatomic, strong) UIButton* backButton;
@property(nonatomic) BOOL isRoot;
- (void)setupTable;
- (CGFloat)bottomInset;   // space for the mini player + tab bar
@end
