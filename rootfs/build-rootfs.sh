#!/usr/bin/env bash
# rootfs/build-rootfs.sh — Build the bundled Debian (Aether) rootfs tarball.
# Produces debian-aether-arm64-rootfs.tar.zst + a .sha256 manifest.
# Runs on ubuntu-latest in CI (needs mmdebstrap + zstd + qemu-user-static).
#
# The rootfs is a minimal Debian Trixie arm64 with Aether's base + chosen
# desktop pre-seeded; the bash installer handles the *post-extract* choices
# (toolchain overlay, agents, GPU drivers), so the rootfs stays generic.
set -Eeuo pipefail

ROOTFS_NAME="${ROOTFS_NAME:-debian-aether-arm64-rootfs}"
OUT_DIR="${OUT_DIR:-build/rootfs}"
MANIFESTS="${MANIFESTS:-rootfs/manifests}"
SUITE="${SUITE:-trixie}"
ARCH="${ARCH:-arm64}"

mkdir -p "$OUT_DIR" "$MANIFESTS"

TARBALL="$OUT_DIR/$ROOTFS_NAME.tar.zst"
MIRROR="http://deb.debian.org/debian"

echo "build-rootfs: building $SUITE/$ARCH rootfs"

# 1. debootstrap variant (no systemd; runs under PRoot)
mmdebstrap \
  --architectures="$ARCH" \
  --variant=minbase \
  --include="bash,coreutils,tar,zstd,ca-certificates,curl,gnupg,locales,sudo,dbus-x11,xauth,fonts-dejavu,pulseaudio-utils" \
  "$SUITE" \
  "$OUT_DIR/$ROOTFS_NAME" \
  "$MIRROR"

# 2. remove populated /dev, dereference hardlinks (Android-safe extraction)
rm -rf "$OUT_DIR/$ROOTFS_NAME/dev"
mkdir -p "$OUT_DIR/$ROOTFS_NAME/dev"

# 3. seed Aether user + sudoers + resolver
chroot "$OUT_DIR/$ROOTFS_NAME" /bin/bash -c "
  useradd -m -s /bin/bash -G sudo aether 2>/dev/null || true
  echo 'aether ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/aether
  echo 'nameserver 8.8.8.8' > /etc/resolv.conf
  echo 'aether' > /etc/hostname
  mkdir -p /home/aether/.aether
"

# 4. pack with Android-safe flags (no /dev, no same-owner, deref hardlinks)
tar --zstd -cf "$TARBALL" \
  --no-same-owner --no-same-permissions --delay-directory-restore \
  -C "$OUT_DIR" "$ROOTFS_NAME"

# 5. checksum
sha256sum "$TARBALL" | cut -d' ' -f1 > "$MANIFESTS/$(basename "$TARBALL").sha256"

echo "build-rootfs: wrote $TARBALL ($(du -h "$TARBALL" | cut -f1))"
echo "build-rootfs: checksum $(cat "$MANIFESTS/$(basename "$TARBALL").sha256")"
