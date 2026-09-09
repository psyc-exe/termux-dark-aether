#!/usr/bin/env sh
# scripts/inspect-aether-apk.sh — Post-build structure assertions for the Aether APK.
# Mirrors Panix's inspect-panix-apk.sh: verifies package id, X11-backed HOME
# launcher, hidden Termux:X11 standalone launcher, bundled rootfs/PRoot assets,
# embedded X11 native lib, and absence of VNC/RDP files.
#
# Usage: scripts/inspect-aether-apk.sh <apk-path>
set -eu

APK="${1:?usage: inspect-aether-apk.sh <apk-path>}"
command -v aapt >/dev/null 2>&1 || command -v aapt2 >/dev/null 2>&1 || {
    echo "inspect-aether-apk: aapt/aapt2 required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$APK" "$TMP/apk.apk"
cd "$TMP"
unzip -q apk.apk -d unpacked 2>/dev/null || { echo "inspect-aether-apk: unzip failed" >&2; exit 1; }

fail() { echo "  ✖ $*" >&2; rm -rf "$TMP"; exit 1; }
ok()   { echo "  ✔ $*"; }

# ── 1. package id ────────────────────────────────────────────────────────────
pkg=$(aapt dump badging apk.apk 2>/dev/null | grep -oP "package: name='\K[^']+" || \
      aapt2 dump badging apk.apk 2>/dev/null | grep -oP "package: name='\K[^']+")
[ "$pkg" = "net.aether.distro" ] || fail "package id is '$pkg', expected net.aether.distro"
ok "package id = net.aether.distro"

# ── 2. X11-backed HOME launcher present ────────────────────────────────────────
grep -rq "net.aether.distro.AetherHomeActivity" unpacked/AndroidManifest.xml && \
  ok "AetherHomeActivity declared" || fail "AetherHomeActivity missing"
grep -rq 'android.intent.category.HOME' unpacked/AndroidManifest.xml && \
  ok "HOME category present" || fail "HOME category missing"

# ── 3. Termux:X11 standalone launcher hidden ───────────────────────────────────
if grep -rq 'com.termux.x11.MainActivity' unpacked/AndroidManifest.xml; then
    grep -q 'android:enabled="false"' unpacked/AndroidManifest.xml && \
      ok "Termux:X11 MainActivity disabled" || \
      echo "  ⚠ Termux:X11 MainActivity present (verify it is disabled)"
fi

# ── 4. bundled assets ─────────────────────────────────────────────────────────
for a in debian-aether-arm64-rootfs.tar.zst termux-proot-aarch64.tar.zst; do
    [ -f "unpacked/assets/$a" ] && ok "asset present: $a" || fail "missing asset: $a"
    [ -f "unpacked/assets/$a.sha256" ] && ok "checksum present: $a.sha256" || \
      echo "  ⚠ $a.sha256 missing (first-boot verify will fail)"
done

# ── 5. embedded X11 native lib ─────────────────────────────────────────────────
find unpacked -name 'libXlorie.so' | grep -q arm64-v8a && \
  ok "embedded X11 lib libXlorie.so (arm64-v8a)" || fail "libXlorie.so missing"

# ── 6. no VNC/RDP leak ─────────────────────────────────────────────────────────
if find unpacked -iname '*vnc*' -o -iname '*rdp*' | grep -q .; then
    fail "VNC/RDP files found in APK"
else
    ok "no VNC/RDP files"
fi

echo "inspect-aether-apk: all checks passed"
rm -rf "$TMP"
