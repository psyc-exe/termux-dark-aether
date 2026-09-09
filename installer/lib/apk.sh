#!/usr/bin/env bash
# lib/apk.sh — Aether embedded APK build entry points.
#
# Path 2 (single self-contained APK) is built the Panix way: fork the entire
# Termux app tree, vendor Termux:X11 as a subtree, and bundle the Debian rootfs
# + pinned PRoot payload as APK assets. The real orchestration lives in
# scripts/build-aether-apk.sh (mirrors Decentricity/Panix build-panix.sh).
#
# This file is a thin dispatcher + guard so the installer/CI can call a single
# `apk_build` function regardless of host. See docs/ARCHITECTURE-embedded.md and
# docs/BUILDING-embedded.md.

set -Eeuo pipefail

AE_APK_REPO_ROOT="${AE_APK_REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

apk_build() {
  # Delegates to the Gradle-based orchestrator.
  local mode="${1:-release}"   # release | ci (unsigned)
  pushd "$AE_APK_REPO_ROOT" >/dev/null || return 1
  case $mode in
    ci)
      AETHER_INCLUDE_X11_MODULE=1 AETHER_USE_EXTERNAL_NATIVE_BUILD=1 \
        AETHER_SIGN_RELEASE=0 bash scripts/build-aether-apk.sh
      ;;
    release)
      bash scripts/build-aether-apk.sh
      ;;
    *)
      echo "apk_build: unknown mode '$mode' (expected release|ci)" >&2
      return 1
      ;;
  esac
  local rc=$?
  popd >/dev/null || true
  return $rc
}

apk_inspect() {
  # Verify the built APK matches the embedded contract.
  local apk="${1:?apk_inspect <apk-path>}"
  bash "$AE_APK_REPO_ROOT/scripts/inspect-aether-apk.sh" "$apk"
}

# Convenience: build rootfs + proot payload (CI steps).
apk_build_rootfs()  { bash "$AE_APK_REPO_ROOT/rootfs/build-rootfs.sh"; }
apk_build_proot()   { bash "$AE_APK_REPO_ROOT/scripts/build-proot-payload.sh"; }
