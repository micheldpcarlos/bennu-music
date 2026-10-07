#include <stdio.h>
#include <string>
#include <functional>
#include <mpark/variant.hpp>
#include <nonstd/optional.hpp>
#include <nonstd/string_view.hpp>

int main() {
    mpark::variant<int, bool, std::string> value(42);
    if (mpark::get<int>(value) != 42) return 1;

    value = std::string("iPad");
    if (mpark::get<std::string>(value) != "iPad") return 2;

    nonstd::optional<bool> queued;
    if (queued) return 3;
    queued = false;
    if (!queued || *queued) return 4;

    std::string text("Spotify");
    nonstd::string_view view(text.data(), text.size());
    if (view.substr(0, 4) != nonstd::string_view("Spot")) return 5;

    size_t hash = std::hash<nonstd::string_view>()(view);
    printf("Backports working: variant, optional, string_view; hash=%lu\n",
           static_cast<unsigned long>(hash));
    return 0;
}
