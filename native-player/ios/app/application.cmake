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
      "${IPAD_APP_DIR}/ui/MainTabController.h" "${IPAD_APP_DIR}/ui/DevURLs.h" "${CMAKE_CURRENT_SOURCE_DIR}/PlayerBridge.h"
    VERBATIM)
set_source_files_properties("${IPAD_APP_OBJECT}"
    PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
add_executable(ipad-media-app
    "${IPAD_APP_OBJECT}"
    "${IPAD_APP_DIR}/EngineEntry.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/PlayerBridge.cpp"
    "${CSPOT_DIR}/targets/cli/CliPlayer.cpp"
    "${CSPOT_DIR}/targets/cli/CommandLineArguments.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/IOSAudioQueueSink.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/AudioTap.cpp")
set_target_properties(ipad-media-app PROPERTIES MACOSX_BUNDLE FALSE)
target_include_directories(ipad-media-app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}" "${CSPOT_DIR}/targets/cli")
target_compile_definitions(ipad-media-app PRIVATE CSPOT_ENABLE_IOS_SINK=1 CSPOT_IOS_APP=1)
target_link_libraries(ipad-media-app PRIVATE cspot
    "-framework UIKit" "-framework AVFoundation" "-framework Foundation" "-framework CFNetwork" "-framework Security" "-framework CoreGraphics" "-framework CoreImage" "-framework QuartzCore"
    "${CMAKE_OSX_SYSROOT}/usr/lib/system/libcommonCrypto.tbd"
    "-framework AudioToolbox" "-framework CoreFoundation" "-framework MediaPlayer" "-framework Accelerate"
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

target_sources(ipad-media-app PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/auth/OAuthLogin.cpp")

# Objective-C screens: one object per app/*.m, all depending on the shared headers.
file(GLOB IPAD_UI_SOURCES "${IPAD_APP_DIR}/ui/*.m")
set(IPAD_UI_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/PlayerBridge.h" "${CMAKE_CURRENT_SOURCE_DIR}/auth/DeviceAuth.h")
file(GLOB IPAD_UI_HEADER_FILES "${IPAD_APP_DIR}/ui/*.h")
foreach(IPAD_UI_SOURCE ${IPAD_UI_SOURCES})
  get_filename_component(IPAD_UI_NAME "${IPAD_UI_SOURCE}" NAME_WE)
  set(IPAD_UI_OBJECT "${CMAKE_CURRENT_BINARY_DIR}/ui-${IPAD_UI_NAME}.o")
  add_custom_command(OUTPUT "${IPAD_UI_OBJECT}"
    COMMAND /usr/bin/clang -target armv7-apple-ios9.0 -marm
    -isysroot "${CMAKE_OSX_SYSROOT}" -fobjc-arc -fblocks -Os -Wall -Wno-unused-parameter
    -c "${IPAD_UI_SOURCE}" -o "${IPAD_UI_OBJECT}"
    DEPENDS "${IPAD_UI_SOURCE}" ${IPAD_UI_HEADER_FILES} ${IPAD_UI_HEADERS} VERBATIM)
  set_source_files_properties("${IPAD_UI_OBJECT}" PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
  target_sources(ipad-media-app PRIVATE "${IPAD_UI_OBJECT}")
endforeach()
target_sources(ipad-media-app PRIVATE
 "${CMAKE_CURRENT_SOURCE_DIR}/auth/DeviceAuth.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/Catalog.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/SpclientClient.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/CatalogProbe.cpp"
 "${CMAKE_CURRENT_SOURCE_DIR}/Pathfinder.cpp")
