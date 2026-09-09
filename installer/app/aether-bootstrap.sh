# aether-bootstrap.sh — Standalone APK integration point.
# Uses the SAME installer script (GH-hosted) as the plain Termux install path,
# keeping the two entry points behaviour-identical. The only extra work on
# first-launch is downloading the full script bundle before piping to --resume.

installer_dir="${installer_dir:-/data/data/com.termux/files/usr/etc/aether}"

first_run() {
  env_ensure
  header "Aether"
  kv "source" "$GH_REPO @ $(_branch)"
  kv "termux home" "$PREFIX"

  # termux deps required by the installer
  spinner "termux deps" pkg update -y
  spinner "termux deps" pkg install -y -o Dpkg::Options::=--force-confnew \
    tsu termux-x11 termux-api termux-tools dialog proot-distro | tail -n+2

  spinner "termux api" termux-setup-storage 2>/dev/null || true
  storage_setup

  # download real installer from GH
  mkdir -p "$installer_dir/bin" "$installer_dir/lib"
  spinner "installer" curl -sSLo "$installer_dir/bin/aether-install.sh" \
    "$(_resolve "${AE_CHECKOUT}/aether-install.sh")"
  chmod +x "$installer_dir/bin/aether-install.sh"
  for l in ui.sh exec.sh toolchain.sh gpu.sh desktop.sh; do
    spinner "$l" curl -sSLo "$installer_dir/lib/$l" \
      "$(_resolve "${AE_CHECKOUT}/lib/$l")"
    chmod +x "$installer_dir/lib/$l"
  done

  # env env (exec needs to know whether to chroot or proot)
  . "$installer_dir/lib/exec.sh"
  [[ "${AE_MODE:-}" =~ ^(root|quasi)$ ]] || privilege_flow
  exec "$installer_dir/bin/aether-install.sh" --resume
}

_resolve() { printf "%s/raw/%s/%s" "$GH_REPO" "$(_branch)" "$1"; }
_branch() {
  gh_fetch_cached "HEAD/ref-$(date +%s)" 2>/dev/null | grep -m1 "GH_BRANCH" | cut -d"=" -f2 || echo HEAD
}
storage_setup() { command -v termux-setup-storage >/dev/null && termux-setup-storage || true; }
header() { echo; printf "\e[48;2;226;184;105m %s \e[0m\n" "$1"; }
kv()   { printf "  \e[38;2;226;184;105m%-12s\e[0m %s\n" "$1:" "$2"; }
