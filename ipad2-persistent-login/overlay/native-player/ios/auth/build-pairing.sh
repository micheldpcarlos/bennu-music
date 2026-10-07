#!/bin/bash
set -euo pipefail
TASK_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$TASK_DIR/.." && pwd)"
NATIVE_DIR="$(cd "$IOS_DIR/.." && pwd)"
ROOT_DIR="$(cd "$NATIVE_DIR/.." && pwd)"
if [ -z "${VIRTUAL_ENV:-}" ]; then source "$NATIVE_DIR/build-venv/bin/activate"; fi
PYTHON="$(command -v python)"
cmake -S "$TASK_DIR" -B "$IOS_DIR/build/pairing" \
 -DCMAKE_TOOLCHAIN_FILE="$IOS_DIR/cmake/armv7-ios9.cmake" \
 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
 -DIPAD_SDK="$IOS_DIR/build/iPhoneOS9.3.sdk" \
 -DIPAD_CXX_HEADERS="${IPAD_CXX_HEADERS:-$ROOT_DIR/browser-port/toolchains/libcxx-3.8.1.src/include}" \
 -DIPAD_MBEDTLS_SOURCE="${IPAD_MBEDTLS_SOURCE:-$NATIVE_DIR/deps/mbedtls-3.6.7}" \
 -DPYTHON_EXECUTABLE="$PYTHON" -DPython3_EXECUTABLE="$PYTHON" \
 -DMBEDTLS_FATAL_WARNINGS=OFF
cmake --build "$IOS_DIR/build/pairing" --target cspot-pairing --parallel "${IPAD_BUILD_JOBS:-4}"
ldid -S "$IOS_DIR/build/pairing/cspot-pairing"
echo "Signed diagnostic: $IOS_DIR/build/pairing/cspot-pairing"
