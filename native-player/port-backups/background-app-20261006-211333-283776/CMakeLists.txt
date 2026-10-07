cmake_minimum_required(VERSION 3.16)
project(cspot_ipad LANGUAGES C CXX)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "Use the armv7-ios9 toolchain; this target is not a host build")
endif()
get_filename_component(NATIVE_PLAYER_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(CSPOT_DIR "${NATIVE_PLAYER_DIR}/cspot")
set(COMPAT_DIR "${NATIVE_PLAYER_DIR}/compat/vendor")
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
add_compile_definitions(CSPOT_LEGACY_IOS=1)
include_directories(SYSTEM
    "${COMPAT_DIR}/variant/include"
    "${COMPAT_DIR}/optional-lite/include"
    "${COMPAT_DIR}/string-view-lite/include")

if(NOT IPAD_MBEDTLS_SOURCE OR NOT EXISTS "${IPAD_MBEDTLS_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR "IPAD_MBEDTLS_SOURCE must name a complete recursive Mbed TLS checkout")
endif()
set(ENABLE_TESTING OFF CACHE BOOL "" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
set(USE_STATIC_MBEDTLS_LIBRARY ON CACHE BOOL "" FORCE)
add_compile_definitions(MBEDTLS_PLATFORM_MS_TIME_ALT)
add_subdirectory("${IPAD_MBEDTLS_SOURCE}" mbedtls)
target_sources(mbedcrypto PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/mbedtls-ios-time.c")

set(BELL_SINK_PORTAUDIO OFF CACHE BOOL "" FORCE)
set(BELL_SINK_ALSA OFF CACHE BOOL "" FORCE)
set(BELL_DISABLE_SINKS ON CACHE BOOL "" FORCE)
set(BELL_CODEC_VORBIS ON CACHE BOOL "" FORCE)
# EncodedAudioStream unconditionally includes the MP3 decoder.
set(BELL_CODEC_MP3 ON CACHE BOOL "" FORCE)
set(BELL_CODEC_AAC OFF CACHE BOOL "" FORCE)
set(BELL_CODEC_OPUS OFF CACHE BOOL "" FORCE)
set(BELL_CODEC_ALAC OFF CACHE BOOL "" FORCE)
set(BELL_DISABLE_MQTT ON CACHE BOOL "" FORCE)
set(BELL_DISABLE_FMT ON CACHE BOOL "" FORCE)
set(BELL_DISABLE_WEBSERVER OFF CACHE BOOL "" FORCE)
add_subdirectory("${CSPOT_DIR}/cspot" cspot)
# Disabled sink collection does not provide the common AudioSink include.
target_include_directories(bell PUBLIC "${CSPOT_DIR}/cspot/bell/main/audio-sinks/include")

add_executable(cspot-ipad
    "${CSPOT_DIR}/targets/cli/main.cpp"
    "${CSPOT_DIR}/targets/cli/CliPlayer.cpp"
    "${CSPOT_DIR}/targets/cli/CommandLineArguments.cpp"
    IOSAudioQueueSink.cpp)
target_include_directories(cspot-ipad PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${CSPOT_DIR}/targets/cli")
target_compile_definitions(cspot-ipad PRIVATE CSPOT_ENABLE_IOS_SINK=1)
target_link_libraries(cspot-ipad PRIVATE cspot "-framework AudioToolbox" "-framework CoreFoundation" "${CMAKE_OSX_SYSROOT}/usr/lib/system/libsystem_dnssd.tbd")
set_target_properties(cspot-ipad PROPERTIES MACOSX_BUNDLE FALSE)
