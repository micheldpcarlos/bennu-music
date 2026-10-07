// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>
namespace ipad_metrics {
void startReporter();
void decoded(std::size_t bytes);
void enqueued(std::size_t bytes);
void consumed(std::size_t bytes);
void emptyRead();
void waiting(bool value);
}
