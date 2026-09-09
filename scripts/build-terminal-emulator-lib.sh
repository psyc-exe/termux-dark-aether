#!/usr/bin/env sh
# scripts/build-terminal-emulator-lib.sh — Build Termux terminal-emulator JNI lib.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/build/terminal-emulator-lib"
mkdir -p "$BUILD_DIR"

if [ "${AETHER_USE_EXTERNAL_NATIVE_BUILD:-0}" = 1 ]; then
    echo "build-terminal-emulator-lib: external native build enabled — deferring to CI ndk-build"
    exit 0
fi

if [ -x /data/data/com.termux/files/usr/bin/clang ]; then
    echo "build-terminal-emulator-lib: compiling with Termux clang"
    clang -shared -fPIC \
        "$REPO_ROOT/terminal-emulator/src/main/jni/"*.c \
        -o "$BUILD_DIR/libterminal-emulator.so" 2>&1 | tee "$BUILD_DIR/build.log"
    mkdir -p "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a"
    cp "$BUILD_DIR/libterminal-emulator.so" "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a/"
else
    echo "build-terminal-emulator-lib: no Termux clang on host — expecting ndk-build in CI"
    exit 0
fi
