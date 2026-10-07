#include "CSpotCompat.h"
#pragma once

#include <stdint.h>  // for uint32_t
#include <cstddef>   // for byte, size_t
#include <istream>   // for istream
#include <vector>    // for vector

#include "AudioContainer.h"  // for AudioContainer
#include "CodecType.h"       // for AudioCodec, AudioCodec::MP3

namespace bell {
class MP3Container : public AudioContainer {
 public:
  ~MP3Container(){};
  MP3Container(std::istream& istr, const cspot_compat::byte* headingBytes = nullptr);

  cspot_compat::byte* readSample(uint32_t& len) override;
  void parseSetupData() override;
  void consumeBytes(uint32_t len) override;

  bell::AudioCodec getCodec() override { return bell::AudioCodec::MP3; }

 private:
  static constexpr auto MP3_MAX_FRAME_SIZE = 2100;
  static constexpr auto BUFFER_SIZE = 1024 * 10;

  std::vector<cspot_compat::byte> buffer = std::vector<cspot_compat::byte>(BUFFER_SIZE);

  size_t bytesInBuffer = 0;
  size_t dataOffset = 0;
  size_t toConsume = 0;

  bool fillBuffer();
};
}  // namespace bell
