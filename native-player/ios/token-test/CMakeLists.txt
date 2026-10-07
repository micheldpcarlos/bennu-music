cmake_minimum_required(VERSION 3.16)
project(ipad_token_test LANGUAGES C CXX)
get_filename_component(IOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
add_subdirectory("${IOS_DIR}" engine EXCLUDE_FROM_ALL)
set(CMAKE_CXX_STANDARD 14)
add_executable(cspot-token-test TokenTest.cpp)
set_target_properties(cspot-token-test PROPERTIES MACOSX_BUNDLE FALSE)
target_compile_definitions(cspot-token-test PRIVATE CSPOT_LEGACY_IOS=1)
target_include_directories(cspot-token-test PRIVATE
 "${IOS_DIR}/../compat/vendor/variant/include"
 "${IOS_DIR}/../compat/vendor/optional-lite/include"
 "${IOS_DIR}/../compat/vendor/string-view-lite/include")
target_link_libraries(cspot-token-test PRIVATE cspot "${CMAKE_OSX_SYSROOT}/usr/lib/system/libsystem_dnssd.tbd")
