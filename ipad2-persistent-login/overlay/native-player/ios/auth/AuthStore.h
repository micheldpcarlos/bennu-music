// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// 1=loaded, 0=not paired, -1=failed. Imports pending credentials before loading.
int ipad_auth_load(char* output, size_t capacity);
int ipad_auth_save(const char* json);
#ifdef __cplusplus
}
#endif
