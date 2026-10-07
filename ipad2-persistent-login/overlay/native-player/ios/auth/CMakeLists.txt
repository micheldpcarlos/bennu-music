cmake_minimum_required(VERSION 3.16)
project(ipad_pairing LANGUAGES C CXX)
get_filename_component(IOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
add_subdirectory("${IOS_DIR}" engine EXCLUDE_FROM_ALL)
set(CMAKE_CXX_STANDARD 14)
add_executable(cspot-pairing PairingTest.cpp)
set_target_properties(cspot-pairing PROPERTIES MACOSX_BUNDLE FALSE)
target_compile_definitions(cspot-pairing PRIVATE CSPOT_LEGACY_IOS=1)
target_include_directories(cspot-pairing PRIVATE
 "${IOS_DIR}/../compat/vendor/variant/include"
 "${IOS_DIR}/../compat/vendor/optional-lite/include"
 "${IOS_DIR}/../compat/vendor/string-view-lite/include")
target_link_libraries(cspot-pairing PRIVATE cspot "${CMAKE_OSX_SYSROOT}/usr/lib/system/libsystem_dnssd.tbd")
