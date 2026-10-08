// SPDX-License-Identifier: GPL-3.0-or-later
#import "DevURLs.h"
#import <UIKit/UIKit.h>
#import "MainTabController.h"
#import "Navigation.h"
#import "SearchViewController.h"
#import "PlayerModel.h"
#import "SetupViewController.h"
#import "NowPlayingViewController.h"
#import "../../auth/AuthStore.h"
static NSDictionary* queryOf(NSURL* url) {
  NSMutableDictionary* result = [NSMutableDictionary dictionary];
  // Shells running `uiopen` split at & and ; so test URLs encode the separator as %26 or %3B.
  NSString* raw = [[url.query stringByReplacingOccurrencesOfString:@"%26" withString:@"&"] stringByReplacingOccurrencesOfString:@"%3B" withString:@"&"];
  for (NSString* pair in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&;"]]) {
    NSRange equal = [pair rangeOfString:@"="];
    if (equal.location == NSNotFound) continue;
    NSString* key = [pair substringToIndex:equal.location];
    NSString* value = [[pair substringFromIndex:equal.location + 1] stringByRemovingPercentEncoding] ?: @"";
    result[key] = value;
  }
  return result;
}
static void screenshot(void) {
  UIWindow* window = UIApplication.sharedApplication.keyWindow;
  UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 1);
  [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
  UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  BOOL ok = [UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:@"phoenix-screen.png"] atomically:YES];
  fprintf(stderr, "DEV: screenshot %s\n", ok ? "saved" : "failed");
}
BOOL PhoenixHandleURL(NSURL* url) {
  NSString* action = url.host ?: @"";
  NSDictionary* query = queryOf(url);
  MainTabController* tabs = [MainTabController shared];
  fprintf(stderr, "DEV: url action=%s\n", action.UTF8String);
  if ([action isEqualToString:@"screenshot"]) {
    // Give pending layout/image loads a moment, then capture.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ screenshot(); });
  } else if ([action isEqualToString:@"tab"]) {
    NSInteger index = [query[@"n"] integerValue];
    if (index >= 0 && index < (NSInteger)tabs.viewControllers.count) { [tabs dismissViewControllerAnimated:NO completion:nil]; tabs.selectedIndex = index; }
  } else if ([action isEqualToString:@"open"]) {
    [tabs dismissViewControllerAnimated:NO completion:nil];
    PhoenixOpen(query[@"uri"], query[@"name"] ?: @"", query[@"artwork"] ?: @"");
  } else if ([action isEqualToString:@"search"]) {
    [tabs dismissViewControllerAnimated:NO completion:nil];
    tabs.selectedIndex = 1;
    UINavigationController* navigation = tabs.viewControllers[1];
    SearchViewController* search = (SearchViewController*)navigation.viewControllers.firstObject;
    [navigation popToRootViewControllerAnimated:NO];
    [search searchFor:query[@"q"] ?: @""];
  } else if ([action isEqualToString:@"nowplaying"]) {
    fprintf(stderr, "DEV: context name='%s' uri='%s'\n", [PlayerModel shared].contextName.UTF8String ?: "", [PlayerModel shared].contextUri.UTF8String ?: "");
    if (!tabs.presentedViewController) [tabs showNowPlaying];
  } else if ([action isEqualToString:@"back"]) {
    UINavigationController* navigation = (UINavigationController*)tabs.selectedViewController;
    if (tabs.presentedViewController) [tabs dismissViewControllerAnimated:NO completion:nil];
    else [navigation popViewControllerAnimated:NO];
  } else if ([action isEqualToString:@"play"]) {
    [[PlayerModel shared] playContext:query[@"uri"] name:query[@"name"] ?: @"" shuffle:[query[@"shuffle"] boolValue]];
  } else if ([action isEqualToString:@"setup"]) {
    if (tabs.presentedViewController) [tabs dismissViewControllerAnimated:NO completion:nil];
    UIViewController* setup = [[SetupViewController alloc] init];
    setup.modalPresentationStyle = UIModalPresentationFullScreen;
    [tabs presentViewController:setup animated:NO completion:nil];
  } else if ([action isEqualToString:@"scroll"]) {
    UINavigationController* navigation = (UINavigationController*)tabs.selectedViewController;
    PhoenixViewController* top = (PhoenixViewController*)navigation.topViewController;
    if ([top isKindOfClass:PhoenixViewController.class]) [top.table setContentOffset:CGPointMake(0, [query[@"y"] floatValue]) animated:NO];
  } else if ([action isEqualToString:@"viz"]) {
    if (!tabs.presentedViewController) [tabs showNowPlaying];
    NowPlayingViewController* nowPlaying = (NowPlayingViewController*)tabs.presentedViewController;
    if ([nowPlaying isKindOfClass:NowPlayingViewController.class]) [nowPlaying showVisualization:query[@"family"] ?: @"Bars and Waves" preset:query[@"preset"] ?: @"Bars"];
  } else if ([action isEqualToString:@"cancelsearch"]) {
    UINavigationController* navigation = tabs.viewControllers[1];
    SearchViewController* search = (SearchViewController*)navigation.viewControllers.firstObject;
    [search cancel];
  } else if ([action isEqualToString:@"repeat"]) {
    ipad_player_set_repeat([query[@"mode"] intValue]);
  } else if ([action isEqualToString:@"enqueue"]) {
    NSString* json = [NSString stringWithFormat:@"{\"uris\":[\"%@\"]}", query[@"uri"] ?: @""];
    fprintf(stderr, "DEV: enqueue -> %d\n", ipad_player_queue_tracks(json.UTF8String));
  } else if ([action isEqualToString:@"drop"]) {
    ipad_engine_drop_connection();
  } else if ([action isEqualToString:@"visible"]) {
    ipad_engine_set_discoverable([query[@"on"] boolValue]);
  } else if ([action isEqualToString:@"signout"]) {
    if (tabs.presentedViewController) [tabs dismissViewControllerAnimated:NO completion:nil];
    if (ipad_auth_clear()) [[PlayerModel shared] signOut];
  } else if ([action isEqualToString:@"pause"]) {
    [[PlayerModel shared] togglePause];
  } else if ([action isEqualToString:@"next"]) {
    [[PlayerModel shared] next];
  } else return NO;
  return YES;
}
