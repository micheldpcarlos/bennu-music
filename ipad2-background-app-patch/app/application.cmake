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
    DEPENDS "${IPAD_APP_DIR}/AppMain.mm"
    VERBATIM)
set_source_files_properties("${IPAD_APP_OBJECT}"
    PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE)
add_executable(ipad-media-app
    "${IPAD_APP_OBJECT}"
    "${IPAD_APP_DIR}/EngineEntry.cpp"
    "${CSPOT_DIR}/targets/cli/CliPlayer.cpp"
    "${CSPOT_DIR}/targets/cli/CommandLineArguments.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/IOSAudioQueueSink.cpp")
set_target_properties(ipad-media-app PROPERTIES MACOSX_BUNDLE FALSE)
target_include_directories(ipad-media-app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}" "${CSPOT_DIR}/targets/cli")
target_compile_definitions(ipad-media-app PRIVATE CSPOT_ENABLE_IOS_SINK=1)
target_link_libraries(ipad-media-app PRIVATE cspot
    "-framework UIKit" "-framework Foundation"
    "-framework AudioToolbox" "-framework CoreFoundation"
    "${CMAKE_OSX_SYSROOT}/usr/lib/system/libsystem_dnssd.tbd")
