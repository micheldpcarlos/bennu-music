#include "CSpotCompat.h"
#pragma once

#include <cstddef>
#include <istream>
#include <streambuf>

namespace bell {
struct MemoryBuffer : std::streambuf {
  MemoryBuffer(cspot_compat::byte const* base, size_t size) {
    cspot_compat::byte* p(const_cast<cspot_compat::byte*>(base));
    this->setg((char*)p, (char*)p, (char*)p + size);
  }
};
struct IMemoryStream : virtual MemoryBuffer, std::istream {
  IMemoryStream(cspot_compat::byte const* base, size_t size)
      : MemoryBuffer(base, size),
        std::istream(static_cast<std::streambuf*>(this)) {}
};
}  // namespace bell
