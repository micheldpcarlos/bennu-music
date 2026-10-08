// SPDX-License-Identifier: GPL-3.0-or-later
#import "VisualizerMenu.h"
#import "VisualizerView.h"
#import "BennuTheme.h"
@interface VisualizerMenu () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UIView* backdrop;
@property(nonatomic, strong) UIView* panel;
@property(nonatomic, strong) UITableView* familyTable;
@property(nonatomic, strong) UITableView* presetTable;
@property(nonatomic, strong) NSArray* families;
@property(nonatomic, copy) NSString* family;
@property(nonatomic, copy) NSString* preset;
@end
@implementation VisualizerMenu
- (UITableView*)table {
  UITableView* table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  table.backgroundColor = [UIColor clearColor]; table.separatorStyle = UITableViewCellSeparatorStyleNone;
  table.rowHeight = 40; table.dataSource = self; table.delegate = self; table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  [table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
  return table;
}
- (void)showIn:(UIView*)parent anchor:(UIView*)anchor selectedFamily:(NSString*)family preset:(NSString*)preset {
  self.families = [VisualizerView families];
  self.family = [self.families containsObject:family] ? family : self.families.firstObject;
  self.preset = preset;
  self.frame = parent.bounds; self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.backdrop = [[UIView alloc] initWithFrame:self.bounds];
  self.backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
  [self.backdrop addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)]];
  [self addSubview:self.backdrop];
  CGRect anchorFrame = [anchor convertRect:anchor.bounds toView:parent];
  CGFloat width = MIN(460, parent.bounds.size.width - 32);
  CGFloat below = parent.bounds.size.height - CGRectGetMaxY(anchorFrame) - 24, above = anchorFrame.origin.y - 24;
  BOOL openUp = below < 220 && above > below;   // the button sits in the bottom row on phones
  CGFloat height = MIN(openUp ? above : below, 420);
  CGFloat familyWidth = width < 400 ? 140 : 180;
  CGFloat panelY = openUp ? anchorFrame.origin.y - 6 - height : CGRectGetMaxY(anchorFrame) + 6;
  self.panel = [[UIView alloc] initWithFrame:CGRectMake(MAX(16, parent.bounds.size.width - width - 16), panelY, width, height)];
  self.panel.backgroundColor = [BennuTheme card]; self.panel.layer.cornerRadius = 10; self.panel.clipsToBounds = YES;
  [self addSubview:self.panel];
  UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, width - 32, 40)];
  title.text = @"Visualizations"; title.font = [BennuTheme bold:15]; title.textColor = [BennuTheme subtext];
  [self.panel addSubview:title];
  self.familyTable = [self table]; self.presetTable = [self table];
  self.familyTable.frame = CGRectMake(0, 40, familyWidth, height - 40);
  self.presetTable.frame = CGRectMake(familyWidth, 40, width - familyWidth, height - 40);
  UIView* divider = [[UIView alloc] initWithFrame:CGRectMake(familyWidth, 40, 1, height - 40)]; divider.backgroundColor = [BennuTheme cardHighlight];
  [self.panel addSubview:self.familyTable]; [self.panel addSubview:self.presetTable]; [self.panel addSubview:divider];
  [parent addSubview:self];
  self.panel.alpha = 0; self.panel.transform = CGAffineTransformMakeScale(0.96, 0.96);
  [UIView animateWithDuration:0.15 animations:^{ self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity; }];
  NSInteger familyRow = [self.families indexOfObject:self.family];
  [self.familyTable selectRowAtIndexPath:[NSIndexPath indexPathForRow:familyRow inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
}
- (void)dismiss {
  [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0; } completion:^(BOOL finished) { [self removeFromSuperview]; }];
}
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  return table == self.familyTable ? self.families.count : [VisualizerView presetsForFamily:self.family].count;
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  UITableViewCell* cell = [table dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
  BOOL isFamily = table == self.familyTable;
  NSString* name = isFamily ? self.families[path.row] : [VisualizerView presetsForFamily:self.family][path.row];
  BOOL selected = isFamily ? [name isEqualToString:self.family] : [name isEqualToString:self.preset];
  cell.backgroundColor = [UIColor clearColor];
  UIView* highlight = [[UIView alloc] init]; highlight.backgroundColor = [BennuTheme cardHighlight]; cell.selectedBackgroundView = highlight;
  cell.textLabel.text = name; cell.textLabel.font = isFamily ? [BennuTheme bold:15] : [BennuTheme regular:15];
  cell.textLabel.textColor = selected ? [BennuTheme green] : [BennuTheme text];
  cell.accessoryType = isFamily ? UITableViewCellAccessoryDisclosureIndicator : (selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone);
  cell.tintColor = [BennuTheme green];
  return cell;
}
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  if (table == self.familyTable) { self.family = self.families[path.row]; [self.familyTable reloadData]; [self.presetTable reloadData]; return; }
  [table deselectRowAtIndexPath:path animated:NO];
  NSString* preset = [VisualizerView presetsForFamily:self.family][path.row];
  if (self.onPick) self.onPick(self.family, preset);
  [self dismiss];
}
@end
