// SPDX-License-Identifier: GPL-3.0-or-later
#import "MainTabController.h"
#import "BennuTheme.h"
#import "MiniPlayerView.h"
#import "NowPlayingViewController.h"
#import "HomeViewController.h"
#import "SearchViewController.h"
#import "LibraryViewController.h"
#import "PlayerModel.h"
#import "SetupViewController.h"
static MainTabController* sharedTabController;
@interface MainTabController ()
@property(nonatomic, strong) MiniPlayerView* miniPlayer;
@end
@implementation MainTabController
+ (instancetype)shared { return sharedTabController; }
- (UINavigationController*)tab:(UIViewController*)root title:(NSString*)title icon:(NSString*)icon {
  UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:root];
  navigation.navigationBarHidden = YES;
  navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
      image:[BennuTheme icon:icon size:26 color:[BennuTheme subtext]]
      selectedImage:[BennuTheme icon:icon size:26 color:[BennuTheme text]]];
  return navigation;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  sharedTabController = self;
  self.view.backgroundColor = [BennuTheme background];
  self.tabBar.barTintColor = [UIColor blackColor];
  self.tabBar.translucent = NO;
  self.tabBar.tintColor = [BennuTheme text];
  [[UITabBarItem appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [BennuTheme subtext]} forState:UIControlStateNormal];
  [[UITabBarItem appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [BennuTheme text]} forState:UIControlStateSelected];
  self.viewControllers = @[
    [self tab:[[HomeViewController alloc] init] title:@"Home" icon:@"home"],
    [self tab:[[SearchViewController alloc] init] title:@"Search" icon:@"search"],
    [self tab:[[LibraryViewController alloc] init] title:@"Your Library" icon:@"library"]];
  self.miniPlayer = [[MiniPlayerView alloc] initWithFrame:CGRectZero];
  __weak MainTabController* weakSelf = self;
  self.miniPlayer.onTap = ^{ [weakSelf showNowPlaying]; };
  [self.view addSubview:self.miniPlayer];
  [[PlayerModel shared] start];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerChanged) name:BennuMusicChanged object:nil];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
// No saved account: the engine stays in the waiting state, so open the welcome setup.
- (void)playerChanged {
  static int waitingTicks = 0;
  if ([PlayerModel shared].snapshot.state != IPadWaiting) { waitingTicks = 0; return; }
  if (self.presentedViewController) return;
  if (++waitingTicks < 4) return;  // two seconds, to let a saved account load first
  SetupViewController* setup = [[SetupViewController alloc] init];
  setup.welcome = YES;
  setup.modalPresentationStyle = UIModalPresentationFullScreen;
  [self presentViewController:setup animated:YES completion:nil];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  CGFloat tabTop = self.tabBar.frame.origin.y;
  self.miniPlayer.frame = CGRectMake(8, tabTop - 64, width - 16, 58);
  [self.view bringSubviewToFront:self.miniPlayer];
}
- (void)push:(UIViewController*)controller {
  UINavigationController* navigation = (UINavigationController*)self.selectedViewController;
  if ([navigation isKindOfClass:UINavigationController.class]) [navigation pushViewController:controller animated:YES];
}
- (void)showNowPlaying {
  NowPlayingViewController* nowPlaying = [[NowPlayingViewController alloc] init];
  nowPlaying.modalPresentationStyle = UIModalPresentationFullScreen;
  nowPlaying.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
  [self presentViewController:nowPlaying animated:YES completion:nil];
}
- (BOOL)prefersStatusBarHidden { return NO; }
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
@end
