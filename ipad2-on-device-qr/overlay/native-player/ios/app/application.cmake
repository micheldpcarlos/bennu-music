# The wrapper has a UIKit main run loop and a declared background audio mode.
# Compile Objective-C++ explicitly so the existing C/C++ toolchain stays intact.
set(IPAD_APP_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(IPAD_APP_OBJECT "${CMAKE_CURRENT_BINARY_DIR}/AppMain.o")
add_custom_command(OUTPUT "${IPAD_APP_OBJECT}"
    COMMAND /usr/bin/clang++
      -target armv7-apple-ios9.0 -marm
      -isysroot "${CMAKE_OSX_SYSROOT}"
      -std=c++14 -stdlib=libc++ -nostdinc++
      -isystem "${IPAD_CXX_HEADERS}"
      -fobjc-arc -fblocks
      -c "${IPAD_APP_DIR}/AppMain.mm" -o "${IPAD_APP_OBJECT}"
    DEPENDS "${IPAD_APP_DIR}/AppMain.mm" "${IPAD_APP_DIR}/AppAudioSession.inc"
      "${CMAKE_CURRENT_SOURCE_DIR}/auth/QRSetup.h" "${IPAD_APP_DIR}/NowPlaying.inc" "${CMAKE_CURRENT_SOURCE_DIR}/PlayerBridge.h"
    VERBATIM)
set_source_files_properties("${IPAD_APP_OBJECT}"
    PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
add_executable(ipad-media-app
    "${IPAD_APP_OBJECT}"
    "${IPAD_APP_DIR}/EngineEntry.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/PlayerBridge.cpp"
    "${CSPOT_DIR}/targets/cli/CliPlayer.cpp"
    "${CSPOT_DIR}/targets/cli/CommandLineArguments.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/IOSAudioQueueSink.cpp")
set_target_properties(ipad-media-app PROPERTIES MACOSX_BUNDLE FALSE)
target_include_directories(ipad-media-app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}" "${CSPOT_DIR}/targets/cli")
target_compile_definitions(ipad-media-app PRIVATE CSPOT_ENABLE_IOS_SINK=1 CSPOT_IOS_APP=1)
target_link_libraries(ipad-media-app PRIVATE cspot
    "-framework UIKit" "-framework AVFoundation" "-framework Foundation" "-framework CFNetwork" "-framework Security" "-framework CoreGraphics" "-framework CoreImage" "-framework QuartzCore"
    "${CMAKE_OSX_SYSROOT}/usr/lib/system/libcommonCrypto.tbd"
    "-framework AudioToolbox" "-framework CoreFoundation"
    "${CMAKE_OSX_SYSROOT}/usr/lib/system/libsystem_dnssd.tbd")
# Playback diagnostics shared by the command-line and app executables.
target_sources(cspot-ipad PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/PlaybackMetrics.cpp")
target_sources(ipad-media-app PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/PlaybackMetrics.cpp")

# Secure account persistence compiled as Objective-C with the legacy SDK.
set(IPAD_AUTH_OBJECT "${CMAKE_CURRENT_BINARY_DIR}/AuthStore.o")
add_custom_command(OUTPUT "${IPAD_AUTH_OBJECT}"
 COMMAND /usr/bin/clang -target armv7-apple-ios9.0 -marm
 -isysroot "${CMAKE_OSX_SYSROOT}" -fobjc-arc -fblocks
 -c "${CMAKE_CURRENT_SOURCE_DIR}/auth/AuthStore.m" -o "${IPAD_AUTH_OBJECT}"
 DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/auth/AuthStore.m" "${CMAKE_CURRENT_SOURCE_DIR}/auth/AuthStore.h"
 VERBATIM)
set_source_files_properties("${IPAD_AUTH_OBJECT}" PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
target_sources(ipad-media-app PRIVATE "${IPAD_AUTH_OBJECT}")

set(IPAD_QR_OBJECT "${CMAKE_CURRENT_BINARY_DIR}/QRSetup.o")
add_custom_command(OUTPUT "${IPAD_QR_OBJECT}"
 COMMAND /usr/bin/clang -target armv7-apple-ios9.0 -marm
 -isysroot "${CMAKE_OSX_SYSROOT}" -fobjc-arc -fblocks
 -c "${CMAKE_CURRENT_SOURCE_DIR}/auth/QRSetup.m" -o "${IPAD_QR_OBJECT}"
 DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/auth/QRSetup.m"
 "${CMAKE_CURRENT_SOURCE_DIR}/auth/QRSetup.h"
 "${CMAKE_CURRENT_SOURCE_DIR}/auth/AuthStore.h"
 "${CMAKE_CURRENT_SOURCE_DIR}/auth/OAuthLogin.h"
 VERBATIM)
set_source_files_properties("${IPAD_QR_OBJECT}" PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
target_sources(ipad-media-app PRIVATE "${IPAD_QR_OBJECT}"
 "${CMAKE_CURRENT_SOURCE_DIR}/auth/OAuthLogin.cpp")
