// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
int ipad_oauth_reusable_credentials(const char* token, char* output, size_t capacity);
#ifdef __cplusplus
}
#endif
