// SPDX-License-Identifier: GPL-3.0-or-later
#import "PhoenixCells.h"
#import "PhoenixTheme.h"
#import "ImageCache.h"

@interface TrackCell ()
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* subtitleLabel;
@property(nonatomic, strong) UILabel* durationLabel;
@property(nonatomic, strong) UILabel* numberLabel;
@end
@implementation TrackCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)identifier {
  if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
    self.backgroundColor = [UIColor clearColor];
    UIView* selected = [[UIView alloc] init]; selected.backgroundColor = [PhoenixTheme cardHighlight]; self.selectedBackgroundView = selected;
    self.artwork = [[UIImageView alloc] init]; self.artwork.contentMode = UIViewContentModeScaleAspectFill; self.artwork.clipsToBounds = YES;
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme regular:16]; self.titleLabel.textColor = [PhoenixTheme text];
    self.subtitleLabel = [[UILabel alloc] init]; self.subtitleLabel.font = [PhoenixTheme regular:13]; self.subtitleLabel.textColor = [PhoenixTheme subtext];
    self.durationLabel = [[UILabel alloc] init]; self.durationLabel.font = [PhoenixTheme regular:13]; self.durationLabel.textColor = [PhoenixTheme subtext]; self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.numberLabel = [[UILabel alloc] init]; self.numberLabel.font = [PhoenixTheme regular:14]; self.numberLabel.textColor = [PhoenixTheme subtext]; self.numberLabel.textAlignment = NSTextAlignmentCenter;
    for (UIView* view in @[self.artwork, self.titleLabel, self.subtitleLabel, self.durationLabel, self.numberLabel]) [self.contentView addSubview:view];
  }
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
  BOOL numbered = !self.numberLabel.hidden;
  CGFloat x = 16;
  if (numbered) { self.numberLabel.frame = CGRectMake(x, 0, 28, h); x += 36; }
  if (!self.artwork.hidden) { self.artwork.frame = CGRectMake(x, (h - 44) / 2, 44, 44); x += 56; }
  self.durationLabel.frame = CGRectMake(w - 72, 0, 56, h);
  CGFloat textWidth = w - x - 84;
  self.titleLabel.frame = CGRectMake(x, h / 2 - 19, textWidth, 20);
  self.subtitleLabel.frame = CGRectMake(x, h / 2 + 2, textWidth, 16);
}
- (void)showTrack:(NSDictionary*)track number:(NSInteger)number playing:(BOOL)playing {
  BOOL loading = [track[@"loading"] boolValue];
  NSString* title = track[@"title"]; NSString* artist = track[@"artist"]; NSString* album = track[@"album"];
  self.titleLabel.text = loading || ![title isKindOfClass:NSString.class] || !title.length ? @"Loading…" : title;
  self.titleLabel.textColor = playing ? [PhoenixTheme green] : loading ? [PhoenixTheme subtext] : [PhoenixTheme text];
  NSString* subtitle = [artist isKindOfClass:NSString.class] ? artist : @"";
  if ([album isKindOfClass:NSString.class] && album.length && number < 0) subtitle = subtitle.length ? [NSString stringWithFormat:@"%@ • %@", subtitle, album] : album;
  self.subtitleLabel.text = subtitle;
  NSNumber* duration = track[@"duration"];
  self.durationLabel.text = [duration isKindOfClass:NSNumber.class] && duration.unsignedIntValue ? PhoenixDuration(duration.unsignedIntValue) : @"";
  self.numberLabel.hidden = number < 0;
  self.numberLabel.text = number >= 0 ? [NSString stringWithFormat:@"%ld", (long)number] : @"";
  self.numberLabel.textColor = playing ? [PhoenixTheme green] : [PhoenixTheme subtext];
  self.artwork.hidden = number >= 0;
  if (number < 0) [[ImageCache shared] load:track[@"artworkSmall"] ?: track[@"artwork"] into:self.artwork placeholder:[PhoenixTheme placeholderArt:44]];
  [self setNeedsLayout];
}
@end

@interface EntityCell ()
@property(nonatomic, strong) UIImageView* artwork;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* subtitleLabel;
@end
@implementation EntityCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)identifier {
  if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
    self.backgroundColor = [UIColor clearColor];
    UIView* selected = [[UIView alloc] init]; selected.backgroundColor = [PhoenixTheme cardHighlight]; self.selectedBackgroundView = selected;
    self.artwork = [[UIImageView alloc] init]; self.artwork.contentMode = UIViewContentModeScaleAspectFill; self.artwork.clipsToBounds = YES;
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme regular:16]; self.titleLabel.textColor = [PhoenixTheme text];
    self.subtitleLabel = [[UILabel alloc] init]; self.subtitleLabel.font = [PhoenixTheme regular:13]; self.subtitleLabel.textColor = [PhoenixTheme subtext];
    for (UIView* view in @[self.artwork, self.titleLabel, self.subtitleLabel]) [self.contentView addSubview:view];
  }
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat w = self.contentView.bounds.size.width, h = self.contentView.bounds.size.height;
  CGFloat size = h - 12;
  self.artwork.frame = CGRectMake(16, 6, size, size);
  self.titleLabel.frame = CGRectMake(28 + size, h / 2 - 19, w - size - 60, 20);
  self.subtitleLabel.frame = CGRectMake(28 + size, h / 2 + 2, w - size - 60, 16);
}
- (void)showTitle:(NSString*)title subtitle:(NSString*)subtitle artwork:(NSString*)url placeholder:(UIImage*)placeholder round:(BOOL)round {
  self.titleLabel.text = title ?: @""; self.subtitleLabel.text = subtitle ?: @"";
  self.artwork.layer.cornerRadius = round ? (self.contentView.bounds.size.height - 12) / 2 : 2;
  [[ImageCache shared] load:url into:self.artwork placeholder:placeholder];
}
@end

@implementation TileCell
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.artwork = [[UIImageView alloc] init]; self.artwork.contentMode = UIViewContentModeScaleAspectFill; self.artwork.clipsToBounds = YES; self.artwork.layer.cornerRadius = 4;
    self.nameLabel = [[UILabel alloc] init]; self.nameLabel.font = [PhoenixTheme bold:14]; self.nameLabel.textColor = [PhoenixTheme text]; self.nameLabel.numberOfLines = 2;
    self.subtitleLabel = [[UILabel alloc] init]; self.subtitleLabel.font = [PhoenixTheme regular:12]; self.subtitleLabel.textColor = [PhoenixTheme subtext];
    for (UIView* view in @[self.artwork, self.nameLabel, self.subtitleLabel]) [self.contentView addSubview:view];
  }
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat w = self.contentView.bounds.size.width;
  self.artwork.frame = CGRectMake(0, 0, w, w);
  self.nameLabel.frame = CGRectMake(0, w + 8, w, 36);
  self.subtitleLabel.frame = CGRectMake(0, w + 46, w, 16);
}
- (void)showItem:(NSDictionary*)item {
  NSString* type = item[@"type"];
  BOOL round = [type isEqualToString:@"artist"];
  self.artwork.layer.cornerRadius = round ? self.contentView.bounds.size.width / 2 : 4;
  self.nameLabel.text = item[@"name"] ?: @"";
  self.subtitleLabel.text = item[@"subtitle"] ?: @"";
  UIImage* placeholder = [type isEqualToString:@"collection"] ? [PhoenixTheme likedSongsArt:150] : [PhoenixTheme placeholderArt:150];
  [[ImageCache shared] load:item[@"artwork"] into:self.artwork placeholder:placeholder];
}
@end

@interface ShelfCell () <UICollectionViewDataSource, UICollectionViewDelegate>
@property(nonatomic, strong) UICollectionView* collection;
@end
@implementation ShelfCell
+ (CGFloat)height { return 232; }
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)identifier {
  if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
    self.backgroundColor = [UIColor clearColor]; self.selectionStyle = UITableViewCellSelectionStyleNone;
    UICollectionViewFlowLayout* layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(150, 216); layout.minimumLineSpacing = 16;
    layout.sectionInset = UIEdgeInsetsMake(4, 16, 4, 16);
    self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collection.backgroundColor = [UIColor clearColor];
    self.collection.showsHorizontalScrollIndicator = NO;
    self.collection.dataSource = self; self.collection.delegate = self;
    [self.collection registerClass:TileCell.class forCellWithReuseIdentifier:@"tile"];
    [self.contentView addSubview:self.collection];
  }
  return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.collection.frame = self.contentView.bounds; }
- (void)setItems:(NSArray*)items { _items = items; [self.collection reloadData]; }
- (NSInteger)collectionView:(UICollectionView*)view numberOfItemsInSection:(NSInteger)section { return self.items.count; }
- (UICollectionViewCell*)collectionView:(UICollectionView*)view cellForItemAtIndexPath:(NSIndexPath*)path {
  TileCell* cell = [view dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:path];
  [cell showItem:self.items[path.item]];
  return cell;
}
- (void)collectionView:(UICollectionView*)view didSelectItemAtIndexPath:(NSIndexPath*)path {
  if (self.onSelect) self.onSelect(self.items[path.item]);
}
@end

@implementation SectionHeader
- (instancetype)initWithReuseIdentifier:(NSString*)identifier {
  if ((self = [super initWithReuseIdentifier:identifier])) {
    self.contentView.backgroundColor = [PhoenixTheme background];
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [PhoenixTheme bold:22]; self.titleLabel.textColor = [PhoenixTheme text];
    [self.contentView addSubview:self.titleLabel];
  }
  return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.titleLabel.frame = CGRectMake(16, 12, self.contentView.bounds.size.width - 32, 28); }
@end
