#include "AppAudioSession.inc"
// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <atomic>
#include <cstdio>
#include <exception>
#import "ui/MainTabController.h"
#import "ui/DevURLs.h"
#include "../PlayerBridge.h"

int ipad_cspot_engine_main(int argc, char** argv);

static std::atomic<bool> engineRunning{false};
static void* runEngine(void*) {
  @autoreleasepool {
    char name[] = "ipad-media-player";
    char bitrate[] = "-b";
    char value[] = "160";
    char* arguments[] = {name, bitrate, value, nullptr};
    ipad_player_waiting();
    try {
      int result = ipad_cspot_engine_main(3, arguments);
      std::fprintf(stderr, "APP: engine returned %d\n", result);
      ipad_player_failed(result ? "The player could not connect." : "The player stopped.");
    } catch (const std::exception& error) {
      std::fprintf(stderr, "APP: engine exception: %s\n", error.what());
      ipad_player_failed(error.what());
    } catch (...) {
      std::fprintf(stderr, "APP: engine failed with unknown exception\n");
      ipad_player_failed("The player encountered an unexpected error.");
    }
  }
  engineRunning.store(false);
  return nullptr;
}

static void startEngine() {
  bool expected = false;
  if (!engineRunning.compare_exchange_strong(expected, true)) return;
  pthread_t worker;
  int result = pthread_create(&worker, nullptr, runEngine, nullptr);
  if (result == 0) pthread_detach(worker);
  else {
    engineRunning.store(false);
    std::fprintf(stderr, "APP: worker creation failed: %d\n", result);
    ipad_player_failed("The player could not start.");
  }
}

@interface IPadPlayerDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation IPadPlayerDelegate
- (void)accountPaired:(NSNotification*)notification {
  (void)notification;
  startEngine();
}
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
  self.window.rootViewController = [[MainTabController alloc] init];
  [self.window makeKeyAndVisible];

  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(audioSessionEvent:)
      name:AVAudioSessionInterruptionNotification object:nil];
  [center addObserver:self selector:@selector(audioSessionEvent:)
      name:AVAudioSessionRouteChangeNotification object:nil];
  [center addObserver:self selector:@selector(accountPaired:)
      name:@"IPadAccountPaired" object:nil];
  startEngine();
  return YES;
}
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)source annotation:(id)annotation {
  std::fprintf(stderr, "APP: opened via url scheme\n");
  return PhoenixHandleURL(url);
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
