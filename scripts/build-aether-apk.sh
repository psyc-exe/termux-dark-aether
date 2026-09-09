#!/usr/bin/env sh
# scripts/build-aether-apk.sh — Top-level orchestrator for the Aether embedded APK.
# Mirrors Decentricity/Panix build-panix.sh: verifies toolchain, bundles the
# Debian rootfs + pinned PRoot payload as APK assets, builds native libs, runs
# Gradle assembleRelease, and signs (optional).
#
# Requirements (on the build host):
#   - Termux app fork checked out as the repo root (this script lives in scripts/)
#   - third_party/termux-x11 vendored (git subtree) when AETHER_INCLUDE_X11_MODULE=1
#   - rootfs/ build recipe + manifests under rootfs/manifests/
#   - signing properties file when AETHER_SIGN_RELEASE=1
#
# See docs/BUILDING-embedded.md for full details.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/data/data/com.termux/files/home/android-tooling/android-sdk}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
JAVA_HOME="${JAVA_HOME:-/data/data/com.termux/files/usr/lib/jvm/java-21-openjdk}"
GRADLE_BIN="${GRADLE_BIN:-$REPO_ROOT/gradlew}"
AAPT2_OVERRIDE="${AAPT2_OVERRIDE:-}"
if [ -z "$AAPT2_OVERRIDE" ] && [ -x /data/data/com.termux/files/usr/bin/aapt2 ]; then
    AAPT2_OVERRIDE=/data/data/com.termux/files/usr/bin/aapt2
fi
ZIPALIGN="${ZIPALIGN:-/data/data/com.termux/files/usr/bin/zipalign}"
APKSIGNER="${APKSIGNER:-/data/data/com.termux/files/usr/bin/apksigner}"
AETHER_KEYSTORE_PROPERTIES="${AETHER_KEYSTORE_PROPERTIES:-/data/data/com.termux/files/home/.signing/aether-release.properties}"
AETHER_SIGN_RELEASE="${AETHER_SIGN_RELEASE:-1}"
AETHER_USE_EXTERNAL_NATIVE_BUILD="${AETHER_USE_EXTERNAL_NATIVE_BUILD:-0}"
AETHER_INCLUDE_X11_MODULE="${AETHER_INCLUDE_X11_MODULE:-0}"
BUILD_LOG_DIR="$REPO_ROOT/build/aether-logs"
ROOTFS_NAME="debian-aether-arm64-rootfs.tar.zst"
ROOTFS_ASSET="$REPO_ROOT/app/src/main/assets/$ROOTFS_NAME"
ROOTFS_ASSET_SHA="$ROOTFS_ASSET.sha256"
ROOTFS_SHA_FILE="$REPO_ROOT/rootfs/manifests/$ROOTFS_NAME.sha256"
PROOT_NAME="termux-proot-aarch64.tar.zst"
PROOT_ASSET="$REPO_ROOT/app/src/main/assets/$PROOT_NAME"
PROOT_ASSET_SHA="$PROOT_ASSET.sha256"
PROOT_SHA_FILE="$REPO_ROOT/rootfs/manifests/$PROOT_NAME.sha256"
X11_CPP_DIR="$REPO_ROOT/third_party/termux-x11/lorie/src/main/cpp"

mkdir -p "$BUILD_LOG_DIR"

fail() {
    printf 'build-aether-apk: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [ -e "$1" ] || fail "missing $2: $1"
}

require_exec() {
    [ -x "$1" ] || fail "missing executable $2: $1"
}

refresh_proot_asset() {
    "$SCRIPT_DIR/build-proot-payload.sh"
    mkdir -p "$(dirname "$PROOT_ASSET")"
    cp "$REPO_ROOT/build/proot/$PROOT_NAME" "$PROOT_ASSET"
    cp "$PROOT_SHA_FILE" "$PROOT_ASSET_SHA"
}

require_exec "$GRADLE_BIN" "Gradle"
require_exec "$JAVA_HOME/bin/java" "Java"
require_file "$ANDROID_SDK_ROOT/platforms/android-36/android.jar" "Android SDK platform android-36"
if [ -n "$AAPT2_OVERRIDE" ]; then
    require_exec "$AAPT2_OVERRIDE" "aapt2 override"
fi
if [ "$AETHER_SIGN_RELEASE" = 1 ]; then
    require_exec "$ZIPALIGN" "zipalign"
    require_exec "$APKSIGNER" "apksigner"
    require_file "$AETHER_KEYSTORE_PROPERTIES" "Aether signing properties"
fi
if [ "$AETHER_INCLUDE_X11_MODULE" = 1 ]; then
    require_file "$X11_CPP_DIR/xorgproto/include/X11/Xpoll.h.in" "Termux:X11 xorgproto submodule; run git submodule update --init --recursive"
    require_file "$X11_CPP_DIR/xserver/dix/main.c" "Termux:X11 xserver submodule; run git submodule update --init --recursive"
    require_file "$X11_CPP_DIR/libx11/src/OpenDis.c" "Termux:X11 libx11 submodule; run git submodule update --init --recursive"
    require_file "$X11_CPP_DIR/pixman/pixman/pixman.c" "Termux:X11 pixman submodule; run git submodule update --init --recursive"
fi

# ── rootfs asset ──────────────────────────────────────────────────────────────
if [ ! -e "$ROOTFS_ASSET" ] && [ -e "$REPO_ROOT/build/rootfs/$ROOTFS_NAME" ]; then
    mkdir -p "$(dirname "$ROOTFS_ASSET")"
    cp "$REPO_ROOT/build/rootfs/$ROOTFS_NAME" "$ROOTFS_ASSET"
fi

# ── proot payload asset ────────────────────────────────────────────────────────
if [ ! -e "$PROOT_ASSET" ] || [ ! -e "$PROOT_ASSET_SHA" ] || [ ! -e "$PROOT_SHA_FILE" ]; then
    refresh_proot_asset
elif [ "$(sha256sum "$PROOT_ASSET" | cut -d ' ' -f 1)" != "$(cut -d ' ' -f 1 "$PROOT_SHA_FILE")" ]; then
    refresh_proot_asset
fi

require_file "$PROOT_ASSET" "bundled PRoot payload asset"
require_file "$PROOT_SHA_FILE" "bundled PRoot payload checksum"
require_file "$PROOT_ASSET_SHA" "bundled PRoot payload checksum asset"

require_file "$ROOTFS_ASSET" "bundled Debian rootfs asset"
require_file "$ROOTFS_SHA_FILE" "bundled Debian rootfs checksum"
cp "$ROOTFS_SHA_FILE" "$ROOTFS_ASSET_SHA"
require_file "$ROOTFS_ASSET_SHA" "bundled Debian rootfs checksum asset"

# ── native libs ────────────────────────────────────────────────────────────────
if [ "$AETHER_USE_EXTERNAL_NATIVE_BUILD" != 1 ]; then
    "$SCRIPT_DIR/build-bootstrap-lib.sh"
    "$SCRIPT_DIR/build-terminal-emulator-lib.sh"
    "$SCRIPT_DIR/build-shared-lib.sh"
fi

# ── checksum verification (transactional safety) ───────────────────────────────
expected_rootfs_sha=$(cut -d ' ' -f 1 "$ROOTFS_SHA_FILE")
actual_rootfs_sha=$(sha256sum "$ROOTFS_ASSET" | cut -d ' ' -f 1)
if [ "$expected_rootfs_sha" != "$actual_rootfs_sha" ]; then
    fail "rootfs checksum verification failed"
fi

expected_proot_sha=$(cut -d ' ' -f 1 "$PROOT_SHA_FILE")
actual_proot_sha=$(sha256sum "$PROOT_ASSET" | cut -d ' ' -f 1)
if [ "$expected_proot_sha" != "$actual_proot_sha" ]; then
    fail "PRoot payload checksum verification failed"
fi

# ── gradle assemble ────────────────────────────────────────────────────────────
export ANDROID_HOME
export ANDROID_SDK_ROOT
export JAVA_HOME
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
export PATH="$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

cd "$REPO_ROOT"

GRADLE_ARGS="--no-daemon clean :app:downloadBootstraps :app:assembleRelease"
if [ -n "$AAPT2_OVERRIDE" ]; then
    GRADLE_ARGS="$GRADLE_ARGS -Pandroid.aapt2FromMavenOverride=$AAPT2_OVERRIDE"
fi
if [ "$AETHER_INCLUDE_X11_MODULE" = 1 ]; then
    GRADLE_ARGS="$GRADLE_ARGS -PAETHER_INCLUDE_X11_MODULE=1"
fi

if ! "$GRADLE_BIN" $GRADLE_ARGS > "$BUILD_LOG_DIR/assembleRelease.log" 2>&1; then
    cat "$BUILD_LOG_DIR/assembleRelease.log"
    fail "Gradle release assemble failed"
fi
cat "$BUILD_LOG_DIR/assembleRelease.log"

APK="$REPO_ROOT/app/build/outputs/apk/release/Aether-arm64-v8a.apk"
require_file "$APK" "release APK"

# ── signing ────────────────────────────────────────────────────────────────────
if [ "$AETHER_SIGN_RELEASE" = 1 ]; then
    set -a
    . "$AETHER_KEYSTORE_PROPERTIES"
    set +a

    : "${AETHER_KEYSTORE:?missing AETHER_KEYSTORE in signing properties}"
    : "${AETHER_KEY_ALIAS:?missing AETHER_KEY_ALIAS in signing properties}"
    : "${AETHER_KEYSTORE_PASSWORD:?missing AETHER_KEYSTORE_PASSWORD in signing properties}"
    : "${AETHER_KEY_PASSWORD:?missing AETHER_KEY_PASSWORD in signing properties}"

    require_file "$AETHER_KEYSTORE" "Aether release keystore"

    ALIGNED_APK="$REPO_ROOT/app/build/outputs/apk/release/Aether-arm64-v8a-aligned.apk"
    SIGNED_APK="$REPO_ROOT/app/build/outputs/apk/release/Aether-arm64-v8a-signed.apk"

    "$ZIPALIGN" -f -p 4 "$APK" "$ALIGNED_APK"
    "$APKSIGNER" sign \
        --ks "$AETHER_KEYSTORE" \
        --ks-key-alias "$AETHER_KEY_ALIAS" \
        --ks-pass env:AETHER_KEYSTORE_PASSWORD \
        --key-pass env:AETHER_KEY_PASSWORD \
        --out "$SIGNED_APK" \
        "$ALIGNED_APK"
    "$APKSIGNER" verify --verbose "$SIGNED_APK"
    mv "$SIGNED_APK" "$APK"
    rm -f "$ALIGNED_APK"
fi

(cd "$(dirname "$APK")" && sha256sum "$(basename "$APK")") > "$APK.sha256"
printf 'Built %s\n' "$APK"
printf 'Checksum %s\n' "$APK.sha256"
