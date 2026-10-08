// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
// Track row: small artwork, title, subtitle, duration. Highlights the playing track in green.
@interface TrackCell : UITableViewCell
- (void)showTrack:(NSDictionary*)track number:(NSInteger)number playing:(BOOL)playing;
@end
// Generic row with artwork (square or round), title and subtitle.
@interface EntityCell : UITableViewCell
- (void)showTitle:(NSString*)title subtitle:(NSString*)subtitle artwork:(NSString*)url placeholder:(UIImage*)placeholder round:(BOOL)round;
@end
// Square tile for horizontal shelves: artwork, name, subtitle.
@interface TileCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* nameLabel;
@property(nonatomic, strong) UILabel* subtitleLabel;
- (void)showItem:(NSDictionary*)item;   // keys: name, subtitle, artwork, type
@end
// A table row that hosts a horizontal shelf of TileCells.
@interface ShelfCell : UITableViewCell
@property(nonatomic, strong) NSArray* items;
@property(nonatomic, copy) void (^onSelect)(NSDictionary* item);
+ (CGFloat)height;
@end
// Section title used above shelves and lists.
@interface SectionHeader : UITableViewHeaderFooterView
@property(nonatomic, strong) UILabel* titleLabel;
@end
