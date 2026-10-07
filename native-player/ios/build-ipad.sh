#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(cd "$NATIVE_DIR/.." && pwd)"
ACTION="${1:-probe}"
case "$ACTION" in probe|build) ;; *) echo 'Usage: build-ipad.sh [probe|build]' >&2; exit 2;; esac
[ "$(uname -s)" = Darwin ] || { echo 'Run this script on the development Mac.' >&2; exit 1; }
for program in xcrun python3; do command -v "$program" >/dev/null; done
# Venv contains the generator and SDK-normalizer dependencies.
if [ -z "${VIRTUAL_ENV:-}" ]; then
    source "$NATIVE_DIR/build-venv/bin/activate"
fi
PYTHON="$(command -v python)"
"$PYTHON" -c 'import yaml' >/dev/null
ORIGINAL_SDK="${IPAD_ORIGINAL_SDK:-$PROJECT_DIR/browser-port/legacy-sdks/iPhoneOS9.3.sdk}"
CXX_HEADERS="${IPAD_CXX_HEADERS:-$PROJECT_DIR/browser-port/toolchains/libcxx-3.8.1.src/include}"
WORK_DIR="$SCRIPT_DIR/build"
SDK="$WORK_DIR/iPhoneOS9.3.sdk"
mkdir -p "$WORK_DIR"
if [ ! -f "$SDK/.normalized-sdk-complete" ]; then
    "$PYTHON" "$SCRIPT_DIR/normalize-sdk.py" "$ORIGINAL_SDK" "$SDK"
fi
[ "$(cat "$SDK/.normalized-sdk-complete")" = "$(cd "$ORIGINAL_SDK" && pwd -P)" ] || {
    echo 'Overlay belongs to a different SDK; use a new build directory.' >&2; exit 1;
}
[ -f "$CXX_HEADERS/string" ] || { echo 'Missing LLVM 3.8.1 libc++ headers.' >&2; exit 1; }
COMPAT="$NATIVE_DIR/compat/vendor"
BELL="$NATIVE_DIR/cspot/cspot/bell"
if [ "$ACTION" = probe ]; then
    xcrun --sdk iphoneos clang++ \
        -target armv7-apple-ios9.0 -marm -isysroot "$SDK" \
        -std=c++14 -stdlib=libc++ -nostdinc++ -isystem "$CXX_HEADERS" \
        -DCSPOT_LEGACY_IOS=1 \
        -I "$COMPAT/variant/include" -I "$COMPAT/optional-lite/include" \
        -I "$COMPAT/string-view-lite/include" \
        -I "$BELL/main/utilities/include" -I "$BELL/main/io/include" \
        -I "$BELL/external/nlohmann_json/include" \
        "$SCRIPT_DIR/tests/compatibility.cpp" "$BELL/main/io/BinaryStream.cpp" \
        -lc++abi -o "$WORK_DIR/ipad-compatibility" 2>&1 | tee "$WORK_DIR/probe.log"
    command -v ldid >/dev/null
    ldid -S "$WORK_DIR/ipad-compatibility"
    echo "Signed probe: $WORK_DIR/ipad-compatibility"
    exit 0
fi
command -v cmake >/dev/null
"$PYTHON" -c 'import pkg_resources; from google.protobuf import message_factory; assert hasattr(message_factory, "GetMessageClass")' >/dev/null
DEPS="$NATIVE_DIR/deps"
TLS="${IPAD_MBEDTLS_SOURCE:-$DEPS/mbedtls-3.6.7}"
if [ ! -d "$TLS" ]; then
    mkdir -p "$DEPS"
    git clone --depth 1 --branch mbedtls-3.6.7 --recurse-submodules --shallow-submodules \
        https://github.com/Mbed-TLS/mbedtls.git "$TLS"
fi
[ -f "$TLS/CMakeLists.txt" ] && [ -d "$TLS/framework/scripts" ] || {
    echo 'Incomplete Mbed TLS checkout; initialize its pinned submodules.' >&2; exit 1;
}
cmake -S "$SCRIPT_DIR" -B "$WORK_DIR/player" \
    -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cmake/armv7-ios9.cmake" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
    -DIPAD_SDK="$SDK" -DIPAD_CXX_HEADERS="$CXX_HEADERS" \
    -DIPAD_MBEDTLS_SOURCE="$TLS" \
    -DPYTHON_EXECUTABLE="$PYTHON" -DPython3_EXECUTABLE="$PYTHON" \
    -DMBEDTLS_FATAL_WARNINGS=OFF \
    2>&1 | tee "$WORK_DIR/configure.log"
cmake --build "$WORK_DIR/player" --parallel "${IPAD_BUILD_JOBS:-4}" \
    2>&1 | tee "$WORK_DIR/build.log"
command -v ldid >/dev/null
ldid -S "$WORK_DIR/player/cspot-ipad"
xcrun otool -L "$WORK_DIR/player/cspot-ipad"
echo "Signed experimental player: $WORK_DIR/player/cspot-ipad"
