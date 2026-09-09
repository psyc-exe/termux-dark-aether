#!/usr/bin/env bash
# scripts/dev-setup.sh — bootstrap a dev environment for the Aether installer
# branch on a fresh Termux install. Installs the full toolchain and runs
# the installer in first-run mode so you can test changes immediately.
#
# Usage: sh scripts/dev-setup.sh [branch]
# Default branch: main

set -Eeuo pipefail

BRANCH="${1:-main}"

echo "Aether Dev Setup"

# ── prerequisites ──────────────────────────────────────────────────────────────
spinner "termux repo" pkg install -y x11-repo termux-x11 termux-api termux-tools dialog proot-distro | tail -n+2

# ── dev-only Termux packages ───────────────────────────────────────────────────
# These are not bundled in the APK or standalone installer — only for dev machines.
spinner "dev tools" pkg install -y git curl socat vimpager rlwrap 2>/dev/null || \
  spinner "dev tools" pkg install -y git curl socat

# ── first-run bootstrap ───────────────────────────────────────────────────────
mkdir -p /data/data/com.termux/files/usr/etc/aether

# Download installer from GH_REPO
GH_REPO="${GH_REPO:-https://github.com/aether-org/termux-distro.git}"
installer_dir="/data/data/com.termux/files/usr/etc/aether"

spinner "installer" curl -sSLo "$installer_dir/bin/aether-install.sh" \
  "$GH_REPO/raw/$BRANCH/installer/aether-install.sh"
chmod +x "$installer_dir/bin/aether-install.sh"

for l in ui.sh exec.sh toolchain.sh gpu.sh desktop.sh; do
  spinner "$l" curl -sSLo "$installer_dir/lib/$l" \
    "$GH_REPO/raw/$BRANCH/installer/lib/$l"
  chmod +x "$installer_dir/lib/$l"
done

# ── run ──────────────────────────────────────────────────────────────────────
# env to trigger first-run path (env_ensure inside bootstrap uses AE_HOME)
export AE_HOME="$installer_dir"
exec "$installer_dir/bin/aether-install.sh"
