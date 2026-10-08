// SPDX-License-Identifier: GPL-3.0-or-later
#import "Navigation.h"
// Album, playlist or liked-songs page: big header with Play/Shuffle, then the track list.
@interface ListViewController : BennuViewController
- (instancetype)initWithKind:(NSString*)kind uri:(NSString*)uri name:(NSString*)name artwork:(NSString*)artwork;
@end
