#!/usr/bin/env sh
# scripts/build-shared-lib.sh — Build Termux shared library (termux-shared).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/build/shared-lib"
mkdir -p "$BUILD_DIR"

if [ "${AETHER_USE_EXTERNAL_NATIVE_BUILD:-0}" = 1 ]; then
    echo "build-shared-lib: external native build enabled — deferring to CI ndk-build"
    exit 0
fi

if [ -x /data/data/com.termux/files/usr/bin/clang ]; then
    echo "build-shared-lib: compiling with Termux clang"
    clang -shared -fPIC \
        "$REPO_ROOT/termux-shared/src/main/jni/"*.c \
        -o "$BUILD_DIR/libtermux-shared.so" 2>&1 | tee "$BUILD_DIR/build.log"
    mkdir -p "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a"
    cp "$BUILD_DIR/libtermux-shared.so" "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a/"
else
    echo "build-shared-lib: no Termux clang on host — expecting ndk-build in CI"
    exit 0
fi
