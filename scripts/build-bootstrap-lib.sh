#!/usr/bin/env sh
# scripts/build-bootstrap-lib.sh — Build the Termux bootstrap native library.
# The bootstrap provides the minimal /data/data net.aether.distro/files/usr
# environment (bash, tar, zstd, etc.) extracted at first boot.
#
# Real compilation uses the Termux toolchain (clang) on-device or NDK in CI.
# This wrapper documents the contract; the actual ndk-build/cargo step is
# delegated to the upstream Termux build (via PANIX_USE_EXTERNAL_NATIVE_BUILD).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/build/bootstrap-lib"
mkdir -p "$BUILD_DIR"

if [ "${AETHER_USE_EXTERNAL_NATIVE_BUILD:-0}" = 1 ]; then
    echo "build-bootstrap-lib: external native build enabled — deferring to CI ndk-build"
    exit 0
fi

# On-device path (Termux clang): build the bootstrap JNI lib
if [ -x /data/data/com.termux/files/usr/bin/clang ]; then
    echo "build-bootstrap-lib: compiling with Termux clang"
    # $REPO_ROOT/terminal-emulator hosts the bootstrap sources upstream
    clang -shared -fPIC \
        "$REPO_ROOT/terminal-emulator/src/main/jni/"*.c \
        -o "$BUILD_DIR/libbootstrap.so" 2>&1 | tee "$BUILD_DIR/build.log"
    mkdir -p "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a"
    cp "$BUILD_DIR/libbootstrap.so" "$REPO_ROOT/app/src/main/jniLibs/arm64-v8a/"
else
    echo "build-bootstrap-lib: no Termux clang on host — expecting ndk-build in CI"
    exit 0
fi
