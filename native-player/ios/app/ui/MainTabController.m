// SPDX-License-Identifier: GPL-3.0-or-later
#import "MainTabController.h"
#import "PhoenixTheme.h"
#import "MiniPlayerView.h"
#import "NowPlayingViewController.h"
#import "HomeViewController.h"
#import "SearchViewController.h"
#import "LibraryViewController.h"
#import "PlayerModel.h"
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
      image:[PhoenixTheme icon:icon size:26 color:[PhoenixTheme subtext]]
      selectedImage:[PhoenixTheme icon:icon size:26 color:[PhoenixTheme text]]];
  return navigation;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  sharedTabController = self;
  self.view.backgroundColor = [PhoenixTheme background];
  self.tabBar.barTintColor = [UIColor blackColor];
  self.tabBar.translucent = NO;
  self.tabBar.tintColor = [PhoenixTheme text];
  [[UITabBarItem appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [PhoenixTheme subtext]} forState:UIControlStateNormal];
  [[UITabBarItem appearance] setTitleTextAttributes:@{NSForegroundColorAttributeName: [PhoenixTheme text]} forState:UIControlStateSelected];
  self.viewControllers = @[
    [self tab:[[HomeViewController alloc] init] title:@"Home" icon:@"home"],
    [self tab:[[SearchViewController alloc] init] title:@"Search" icon:@"search"],
    [self tab:[[LibraryViewController alloc] init] title:@"Your Library" icon:@"library"]];
  self.miniPlayer = [[MiniPlayerView alloc] initWithFrame:CGRectZero];
  __weak MainTabController* weakSelf = self;
  self.miniPlayer.onTap = ^{ [weakSelf showNowPlaying]; };
  [self.view addSubview:self.miniPlayer];
  [[PlayerModel shared] start];
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
