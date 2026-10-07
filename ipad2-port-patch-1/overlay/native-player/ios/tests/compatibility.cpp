#include "CSpotCompat.h"
#include "BinaryStream.h"
#include <cassert>
#include <cstdio>
#include <functional>
#include <sstream>
#include <string>
#include <thread>
#include "nlohmann/json.hpp"

int main() {
    cspot_compat::variant<int, bool, std::string> value(7);
    assert(cspot_compat::get<int>(value) == 7);
    value = std::string("iPad");
    assert(cspot_compat::get<std::string>(value) == "iPad");
    bool caught = false;
    try { (void)cspot_compat::get<bool>(value); }
    catch (const std::exception&) { caught = true; }
    assert(caught);

    cspot_compat::optional<bool> queued;
    assert(!queued);
    queued = false;
    assert(queued && !*queued);
    std::string text("{\"ok\":true}");
    cspot_compat::string_view view(text.data(), text.size());
    auto json = nlohmann::json::parse(view.begin(), view.end());
    assert(json["ok"] == true);
    (void)std::hash<cspot_compat::string_view>()(view);

    std::mutex mutex;
    int result = 0;
    std::thread worker([&] {
        std::lock_guard<decltype(mutex)> lock(mutex);
        result = 42;
    });
    worker.join();
    assert(result == 42);

    std::ostringstream encoded;
    bell::BinaryStream writer(static_cast<std::ostream*>(&encoded));
    writer.setByteOrder(cspot_compat::endian::big);
    writer << static_cast<uint16_t>(0x1234) << static_cast<uint32_t>(0x12345678);
    std::string bytes = encoded.str();
    assert(bytes.size() == 6 && static_cast<unsigned char>(bytes[0]) == 0x12);
    std::istringstream decoded(bytes);
    bell::BinaryStream reader(static_cast<std::istream*>(&decoded));
    reader.setByteOrder(cspot_compat::endian::big);
    uint16_t shortValue = 0;
    uint32_t longValue = 0;
    reader >> shortValue >> longValue;
    assert(shortValue == 0x1234 && longValue == 0x12345678);
    puts("Compatibility passed: variants, exceptions, optional, JSON, threads, byte order");
}
