#include "AppAudioSession.inc"
// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <cstdio>
#include <exception>

int ipad_cspot_engine_main(int argc, char** argv);

static void* runEngine(void*) {
  @autoreleasepool {
    char name[] = "ipad-media-player";
    char bitrate[] = "-b";
    char value[] = "160";
    char* arguments[] = {name, bitrate, value, nullptr};
    try {
      int result = ipad_cspot_engine_main(3, arguments);
      std::fprintf(stderr, "APP: engine returned %d\n", result);
    } catch (const std::exception& error) {
      std::fprintf(stderr, "APP: engine exception: %s\n", error.what());
    } catch (...) {
      std::fprintf(stderr, "APP: engine failed with unknown exception\n");
    }
  }
  return nullptr;
}

@interface IPadPlayerDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation IPadPlayerDelegate
- (void)audioSessionEvent:(NSNotification*)notification {
  std::fprintf(stderr, "SESSION: notification=%s info=%s\n",
      notification.name.UTF8String, notification.userInfo.description.UTF8String);
  ipadLogAudioSession();
}

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)options {
  (void)application;
  (void)options;
  NSString* documents = NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* log = [documents stringByAppendingPathComponent:@"cspot-app.log"];
  std::freopen(log.fileSystemRepresentation, "a", stdout);
  std::freopen(log.fileSystemRepresentation, "a", stderr);
  std::setvbuf(stdout, nullptr, _IOLBF, 0);
  std::setvbuf(stderr, nullptr, _IOLBF, 0);
  std::fprintf(stderr, "APP: launched; log=%s\n", log.fileSystemRepresentation);

  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  UIViewController* controller = [[UIViewController alloc] init];
  controller.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
  UILabel* label = [[UILabel alloc] initWithFrame:CGRectZero];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.textColor = UIColor.whiteColor;
  label.font = [UIFont systemFontOfSize:24];
  label.text = @"iPad Media Player\n\nChoose CSpot player in Spotify.\n\nKeep this app open while testing playback.";
  [controller.view addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
    [label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
    [label.widthAnchor constraintEqualToAnchor:controller.view.widthAnchor multiplier:0.85]
  ]];
  self.window.rootViewController = controller;
  [self.window makeKeyAndVisible];

  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(audioSessionEvent:)
      name:AVAudioSessionInterruptionNotification object:nil];
  [center addObserver:self selector:@selector(audioSessionEvent:)
      name:AVAudioSessionRouteChangeNotification object:nil];
  pthread_t worker;
  int result = pthread_create(&worker, nullptr, runEngine, nullptr);
  if (result == 0) pthread_detach(worker);
  else {
    std::fprintf(stderr, "APP: worker creation failed: %d\n", result);
    label.text = @"The player could not start. Close and reopen this app.";
  }
  return YES;
}
- (void)applicationDidEnterBackground:(UIApplication*)application {
  (void)application;
  std::fprintf(stderr, "APP: entered background\n");
  ipadLogAudioSession();
}
- (void)applicationDidBecomeActive:(UIApplication*)application {
  (void)application;
  std::fprintf(stderr, "APP: became active\n");
  ipadLogAudioSession();
}
@end

int main(int argc, char** argv) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil,
        NSStringFromClass([IPadPlayerDelegate class]));
  }
}
