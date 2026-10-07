// SPDX-License-Identifier: GPL-3.0-or-later
// Compile the existing CLI engine without modifying its entry point globally.
#define main ipad_cspot_engine_main
#include "../../cspot/targets/cli/main.cpp"
#undef main
