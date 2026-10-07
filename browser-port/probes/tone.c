#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void check(OSStatus status, const char *operation) {
    if (status != noErr) {
        fprintf(stderr, "%s failed: %ld\n", operation, (long)status);
        exit(1);
    }
}

static void finished(void *context, AudioQueueRef queue,
                     AudioQueueBufferRef buffer) {
    puts("Audio buffer consumed.");
}

int main(void) {
    check(AudioSessionInitialize(NULL, NULL, NULL, NULL),
          "AudioSessionInitialize");

    UInt32 category = kAudioSessionCategory_MediaPlayback;
    check(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                                  sizeof(category), &category),
          "Set playback category");
    check(AudioSessionSetActive(true), "Activate audio session");

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = 44100;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags =
        kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    AudioQueueRef queue;
    check(AudioQueueNewOutput(&format, finished, NULL,
                             CFRunLoopGetCurrent(),
                             kCFRunLoopCommonModes, 0, &queue),
          "AudioQueueNewOutput");

    const UInt32 frames = 44100 * 3;
    AudioQueueBufferRef buffer;
    check(AudioQueueAllocateBuffer(queue, frames * 2, &buffer),
          "Allocate buffer");

    int16_t *samples = buffer->mAudioData;
    for (UInt32 i = 0; i < frames; i++) {
        double fade = fmin(1.0, fmin(i / 2205.0,
                                    (frames - 1 - i) / 2205.0));
        samples[i] = (int16_t)(2600 * fade *
            sin(2.0 * 3.141592653589793 * 440 * i / 44100.0));
    }
    buffer->mAudioDataByteSize = frames * 2;

    check(AudioQueueEnqueueBuffer(queue, buffer, 0, NULL),
          "Enqueue buffer");
    check(AudioQueueStart(queue, NULL), "Start playback");
    puts("Playing a quiet 440 Hz tone for three seconds.");
    fflush(stdout);

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 4.0, false);
    check(AudioQueueStop(queue, true), "Stop playback");
    check(AudioQueueDispose(queue, true), "Dispose queue");
    check(AudioSessionSetActive(false), "Deactivate session");
    puts("Done.");
    return 0;
}
