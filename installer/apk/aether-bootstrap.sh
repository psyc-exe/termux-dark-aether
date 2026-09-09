#!/usr/bin/env bash
# aether-bootstrap.sh — On-first-launch payload for the standalone APK.
# Embedded in assets/boot.sh; runs from Termux (not root).
# Checks GH_REPO for updates; installs Termux deps; extracts distro tarballs;
# delegates to the real aether-install.sh --resume.
set -Eeuo pipefail

installer_dir="${AE_HOME:-/data/data/com.termux/files/usr/etc/aether}"

env_ensure() {
  AE_HOME="${AE_HOME:-/data/data/com.termux/files/usr/etc/aether}"
  GH_REPO="${GH_REPO:-$(cd "$(dirname -- "${BASH_SOURCE[0]}")/../.." && git remote get-url origin 2>/dev/null || echo https://github.com/aether-org/termux-distro.git)}"
  mkdir -p "$AE_HOME/bin" "$AE_HOME/dl" "$AE_HOME/agent/native" "$AE_HOME/agent/glibc" "$AE_HOME/agent/distro"
  : ${AE_DL:=$AE_HOME/dl}
  : ${AE_INSTALLER_DIR:=installer}
}

first_run() {
  env_ensure
  clear
  header "Aether"
  kv "source" "$GH_REPO @ ${GH_BRANCH:-HEAD}"
  kv "termux home" "$PREFIX"

  # termux deps required by the installer
  spinner "termux deps" pkg update -y
  spinner "termux deps" pkg install -y -o Dpkg::Options::=--force-confnew \
    tsu termux-x11 termux-api termux-tools dialog proot-distro | tail -n+2

  spinner "termux api" termux-setup-storage 2>/dev/null || true
  storage_setup

  # download real installer from GH
  spinner "installer" curl -sSLo "$installer_dir/bin/aether-install.sh" \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/aether-install.sh")"
  chmod +x "$installer_dir/bin/aether-install.sh"

  # download libs
  spinner "ui lib"   curl -sSLo "$installer_dir/lib/ui.sh"        \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/lib/ui.sh")"
  spinner "exec lib" curl -sSLo "$installer_dir/lib/exec.sh"       \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/lib/exec.sh")"
  spinner "gpu lib"  curl -sSLo "$installer_dir/lib/gpu.sh"        \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/lib/gpu.sh")"
  spinner "desktop lib" curl -sSLo "$installer_dir/lib/desktop.sh" \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/lib/desktop.sh")"
  spinner "toolchain lib" curl -sSLo "$installer_dir/lib/toolchain.sh" \
    "$(_resolve_gh_url "${AE_INSTALLER_DIR}/lib/toolchain.sh")"

  chmod +x "$installer_dir/lib/"*.sh

  # env env (exec needs to know whether to chroot or proot)
  . "$installer_dir/lib/exec.sh"
  case ${AE_MODE:-} in root|quasi) : ;; *) privilege_flow;; esac
  # from that point, install.sh --resume already knows what it needs to
  exec "$installer_dir/bin/aether-install.sh" --resume
}

_resolve_gh_url() { printf "%s/raw/%s/%s" "$GH_REPO" "${GH_BRANCH:-HEAD}" "$1"; }
storage_setup() { command -v termux-setup-storage >/dev/null && termux-setup-storage || true; }
header() { echo; printf "\e[48;2;226;184;105m %s \e[0m\n" "$1"; }
kv()   { printf "  \e[38;2;226;184;105m%-12s\e[0m %s\n" "$1:" "$2"; }

main() { env_ensure; first_run; }
main "$@"
