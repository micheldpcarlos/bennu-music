// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <memory>
namespace cspot { struct Context; }
namespace ipad_player {
// Developer aid: if /var/mobile/Documents/phoenix-probe.txt exists, fetch each listed URL once with the
// session token and record status, size, top-level JSON keys and the body. Runs on its own thread.
void runCatalogProbeIfRequested(std::shared_ptr<cspot::Context> context);
}
