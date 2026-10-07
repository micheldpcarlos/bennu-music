// SPDX-License-Identifier: GPL-3.0-or-later
// Included only by AppMain.mm; these APIs exist on iOS 9.
#import <AVFoundation/AVFoundation.h>
#include <dispatch/dispatch.h>
#include <cstdio>

static void ipadLogAudioSession() {
  AVAudioSession* session = AVAudioSession.sharedInstance;
  AVAudioSessionPortDescription* output = session.currentRoute.outputs.firstObject;
  const char* port = output ? output.portType.UTF8String : "none";
  std::fprintf(stderr,
      "SESSION: category=%s mode=%s rate=%.0f io_ms=%.2f volume=%.2f output=%s\n",
      session.category.UTF8String, session.mode.UTF8String,
      session.sampleRate, session.IOBufferDuration * 1000.0,
      session.outputVolume, port);
}

bool ipadAppActivateAudioSession() {
  __block BOOL success = NO;
  void (^configure)(void) = ^{
    AVAudioSession* session = AVAudioSession.sharedInstance;
    NSError* error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&error]) {
      std::fprintf(stderr, "SESSION: setCategory failed: %s\n",
          error.description.UTF8String);
      return;
    }
    if (![session setMode:AVAudioSessionModeDefault error:&error]) {
      std::fprintf(stderr, "SESSION: setMode failed: %s\n",
          error.description.UTF8String);
      return;
    }
    success = [session setActive:YES error:&error];
    if (!success) std::fprintf(stderr, "SESSION: activation failed: %s\n",
        error.description.UTF8String);
    ipadLogAudioSession();
  };
  if (NSThread.isMainThread) configure();
  else dispatch_sync(dispatch_get_main_queue(), configure);
  return success;
}

void ipadAppDeactivateAudioSession() {
  void (^deactivate)(void) = ^{
    NSError* error = nil;
    if (![AVAudioSession.sharedInstance setActive:NO error:&error]) {
      std::fprintf(stderr, "SESSION: deactivation failed: %s\n",
          error.description.UTF8String);
    }
  };
  if (NSThread.isMainThread) deactivate();
  else dispatch_sync(dispatch_get_main_queue(), deactivate);
}
