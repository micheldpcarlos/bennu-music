#pragma once
// Keep compatibility types out of namespace std. Select backports only for iOS 9.
#include <cstddef>
#include <mutex>
#ifdef CSPOT_LEGACY_IOS
#ifndef optional_CONFIG_SELECT_OPTIONAL
#define optional_CONFIG_SELECT_OPTIONAL 1
#endif
#ifndef nssv_CONFIG_SELECT_STRING_VIEW
#define nssv_CONFIG_SELECT_STRING_VIEW 1
#endif
#include <nonstd/optional.hpp>
#include <nonstd/string_view.hpp>
#include <mpark/variant.hpp>
#else
#include <optional>
#include <string_view>
#include <variant>
#include <bit>
#endif

namespace cspot_compat {
#ifdef CSPOT_LEGACY_IOS
using nonstd::optional;
using nonstd::nullopt;
using nonstd::string_view;
using mpark::variant;
using mpark::get;
enum class byte : unsigned char {};
enum class endian {
    little = 1234, big = 4321,
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    native = little
#elif defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    native = big
#else
#error Unsupported compiler byte order
#endif
};
#else
using std::optional;
using std::nullopt;
using std::string_view;
using std::variant;
using std::get;
using std::byte;
using std::endian;
#endif
static_assert(sizeof(byte) == 1, "Audio bytes must occupy one byte");
} // namespace cspot_compat
