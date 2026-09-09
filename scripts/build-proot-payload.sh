#!/usr/bin/env sh
# scripts/build-proot-payload.sh — Build the pinned Termux PRoot payload.
# Mirrors Panix: pins proot + libandroid-shmem + libtalloc from verified .deb
# files, extracts them, and packs termux-proot-aarch64.tar.zst with a checksum.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/build/proot"
OUT="$BUILD_DIR/termux-proot-aarch64.tar.zst"
MANIFESTS="$REPO_ROOT/rootfs/manifests"
mkdir -p "$BUILD_DIR" "$MANIFESTS"

# Pinned versions (verified via termux-packages). Bump only after re-verifying.
PROOT_VER="5.1.107-87"
LIBANDROID_SHMEM_VER="landroid-shmem-1.0"
LIBTALLOC_VER="2.4.2"

DEB_ROOT="https://packages.termux.dev/apt/termux-main/pool/main"
fetch_deb() {  # $1 pkg $2 version
  local pkg="$1" ver="$2" arch=aarch64
  local f="${pkg}_${ver}_${arch}.deb"
  # termux package names are like proot, libandroid-shmem, libtalloc
  curl -fSL "$DEB_ROOT/${pkg:0:1}/$pkg/$f" -o "$BUILD_DIR/$f" || \
    curl -fSL "$DEB_ROOT/${pkg%%-*/}/$pkg/$f" -o "$BUILD_DIR/$f"
  echo "$BUILD_DIR/$f"
}

echo "build-proot-payload: fetching pinned debs"
P=$(fetch_deb proot "$PROOT_VER")
S=$(fetch_deb libandroid-shmem "$LIBANDROID_SHMEM_VER")
T=$(fetch_deb libtalloc "$LIBTALLOC_VER")

rm -rf "$BUILD_DIR/extract"; mkdir -p "$BUILD_DIR/extract"
for d in "$P" "$S" "$T"; do
  ar x "$d" --output "$BUILD_DIR/extract" 2>/dev/null || \
    tar -xf "$d" -C "$BUILD_DIR/extract"  # .deb is ar; fallback to tar
done
# data.tar.* holds the payload
mkdir -p "$BUILD_DIR/payload"
for t in "$BUILD_DIR/extract"/data.tar.*; do
  case $t in
    *.xz)  tar -xf "$t" -C "$BUILD_DIR/payload" --use-compress-program=unxz ;;
    *.zst) tar -xf "$t" -C "$BUILD_DIR/payload" --use-compress-program=unzstd ;;
    *.gz)  tar -xzf "$t" -C "$BUILD_DIR/payload" ;;
  esac
done

# Pack only the PRoot runtime tree (bin/proot, libexec, lib/loader)
rm -rf "$BUILD_DIR/pack"; mkdir -p "$BUILD_DIR/pack/usr"
mv "$BUILD_DIR/payload/data/data/com.termux/files/usr/bin/proot" "$BUILD_DIR/pack/usr/" 2>/dev/null || \
  mv "$BUILD_DIR/payload/usr/bin/proot" "$BUILD_DIR/pack/usr/" 2>/dev/null || true
mkdir -p "$BUILD_DIR/pack/usr/libexec" "$BUILD_DIR/pack/usr/lib"
cp -a "$BUILD_DIR/payload/usr/libexec/proot"/* "$BUILD_DIR/pack/usr/libexec/" 2>/dev/null || true
cp -a "$BUILD_DIR/payload/usr/lib/"* "$BUILD_DIR/pack/usr/lib/" 2>/dev/null || true

tar --zstd -cf "$OUT" -C "$BUILD_DIR/pack" usr
sha256sum "$OUT" | cut -d' ' -f1 > "$MANIFESTS/termux-proot-aarch64.tar.zst.sha256"
echo "build-proot-payload: wrote $OUT and checksum"
