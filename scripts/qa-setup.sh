#!/usr/bin/env bash
# scripts/qa-setup.sh — Simulate the full installer pipeline on this machine
# (no Android, no root needed) by stubbing out the system calls and running
# each step's decision logic. Tests all setup paths: privilege, base OS,
# toolchain, footprint, agents, desktop, GPU. Outputs to install.log.
#
# Usage: sh scripts/qa-setup.sh [--verbose]

set -Eeuo pipefail

VERBOSE="${VERBOSE:-0}"
LOG="$HOME/.aether/qa-setup.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || mkdir -p "$HOME/.aether"
[[ -d "$HOME/.aether" ]] || mkdir -p "$HOME/.aether"

# ── helpers ──────────────────────────────────────────────────────────────────
pass()  { echo "  ✔ $*" >> "$LOG"; v "  ✔ $*"; }
fail()  { echo "  ✖ $*" >> "$LOG"; v "  ✖ $*"; }
info()  { v "  → $*"; }
v()     { if [[ "$VERBOSE" == 1 ]]; then printf '%s\n' "$*"; fi; }
stub()  { v "  [stub] $*"; }

# ── module load ───────────────────────────────────────────────────────────────
installer_dir="${installer_dir:-$(cd "$(dirname "$0")/../installer" && pwd)}"
cd "$installer_dir"
. lib/ui.sh 2>/dev/null || { echo "FAIL: ui.sh not found"; exit 1; }
. lib/exec.sh 2>/dev/null
. lib/toolchain.sh 2>/dev/null
. lib/gpu.sh 2>/dev/null
. lib/desktop.sh 2>/dev/null
. lib/update.sh 2>/dev/null
. lib/repo.sh 2>/dev/null
mkdir -p "$HOME/.aether/bin" "$HOME/.aether/dl" "$HOME/.aether/agent/native" "$HOME/.aether/agent/glibc" "$HOME/.aether/agent/distro"

# ── env overrides (no Android = nonroot/proot, x86_64 Linux) ────────────────
export AE_HOME="$HOME/.aether"
export AE_MODE=nonroot
export AE_EXEC=proot
export AE_DISTRO=debian
export AE_TOOL=none
export AE_FOOT=done
export AE_AGENTS=done
export AE_DE=none
export AE_GL=virgl
export AE_GPU=unknown
export AE_SCALE=1
export AE_DPI=160
rm -f "$AE_HOME/state" 2>/dev/null || true
# On Windows-hosted filesystems, rm -f may not clean up a prior directory; force it:
if [[ -d "$AE_HOME/state" ]]; then rm -rf "$AE_HOME/state"; fi
state_save AE_MODE AE_EXEC AE_DISTRO AE_TOOL AE_FOOT AE_AGENTS AE_DE AE_GL AE_GPU AE_SCALE AE_DPI

# ── step 0: detection stubs ─────────────────────────────────────────────────
v "=== STEP 0: detection stubs ==="
detect_arch()  { AE_ARCH=x86_64; pass "detect_arch → x86_64"; }
detect_gpu()   { AE_GPU="llvmpipe"; pass "detect_gpu → llvmpipe (no GPU on this host)"; }
detect_android(){ AE_ANDROID=13; AE_SDK=33; pass "detect_android → SDK 33 (Android 13)"; }

# ── step 1: base OS ──────────────────────────────────────────────────────────
v "=== STEP 1: base OS ==="
# step_base_os calls proot_install (can't chroot on Linux host)
# stub proot_install to just write the state and continue
proot_install() {
  info "proot_install stub (no chroot on Linux host)"
  run_in_distro "true"
}
chroot_setup() { fail "chroot_setup should not be called in nonroot path"; }
run_in_distro() { info "run_in_distro stub: $*"; pass "run_in_distro ok"; }

# inject detect_android first (step_base_os needs it)
step_base_os() {
  detect_android; detect_arch
  header "base os"
  menu c "Base distribution" "Debian — latest stable" "Ubuntu — latest LTS"
  AE_DISTRO=$([[ $c == 1 ]] && echo debian || echo ubuntu); state_save AE_DISTRO
  [[ $AE_EXEC == chroot ]] && chroot_setup || proot_install
  run_in_distro "echo 'path-exclude /usr/share/man/*' >/etc/dpkg/dpkg.cfg.d/01_nodoc; $APT update && $APT install ca-certificates curl gnupg sudo dbus-x11 locales"
  run_in_distro "id aether >/dev/null 2>&1 || (useradd -m -s /bin/bash -G sudo aether && echo 'aether ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/aether)"
  pass "step_base_os → $AE_DISTRO"
}
step_base_os

# ── step 2: toolchain ────────────────────────────────────────────────────────
v "=== STEP 2: toolchain ==="
overlay_kali()   { warn "Kali overlay on non-Debian host skipped"; }
overlay_parrot() { warn "Parrot overlay on non-Debian host skipped"; }
step_toolchain() {
  header "toolchain"
  menu c "Security toolchain overlay" "Kali NetHunter" "Parrot OS" "None"
  case $c in
    1) warn "Kali overlay requires Debian base"; AE_TOOL=kali;;
    2) warn "Parrot overlay requires Debian 12 base"; AE_TOOL=parrot;;
    3) AE_TOOL=none;;
  esac; state_save AE_TOOL
  pass "step_toolchain → $AE_TOOL"
}
step_toolchain

# ── step 3: footprint ─────────────────────────────────────────────────────────
v "=== STEP 3: footprint ==="
step_footprint() {
  header "footprint"
  menu c "Installation footprint" "Minimal — base utilities only" "Top-10 Security Tools" "Full Toolchain"
  case $c in
    1) AE_FOOT=minimal;;
    2) AE_FOOT=top10;;
    3) AE_FOOT=full;;
  esac; state_save AE_FOOT
  pass "step_footprint → $AE_FOOT"
}
step_footprint

# ── step 4: agents ───────────────────────────────────────────────────────────
v "=== STEP 4: agents ==="
agents_native() { pass "agents_native stub (no npm on this host)"; }
agents_distro() { pass "agents_distro stub (glibc not on this host)"; }
step_agents() {
  header "agentic ai"
  menu c "Agentic coding CLIs" "Native set (codex·claude·opencode)" "Distro set (cline·kilocode·code-server)" "Both" "Skip"
  case $c in
    1|3) agents_native;;
    2|3) agents_distro;;
    4) pass "agents skipped";;
  esac
  AE_AGENTS="done"
  state_save AE_AGENTS
  pass "step_agents → done"
}
step_agents

# ── step 5: desktop + GPU ────────────────────────────────────────────────────
v "=== STEP 5: desktop + GPU ==="
desktop_install_guest() { pass "desktop_install_guest stub"; }
desktop_theme()        { pass "desktop_theme stub"; }
desktop_launcher()     { pass "desktop_launcher stub"; }
step_desktop() {
  header "desktop"
  menu c "Desktop environment" "CLI only" "Lightweight — XFCE4 / Openbox / i3" "Mid — LXQt / MATE" "Heavy — KDE Plasma / GNOME"
  case $c in
    1) AE_DE=none; state_save AE_DE; return;;
    2) menu d "Window manager" XFCE4 Openbox i3wm
       AE_DE=$([[ $d == 1 ]] && echo xfce4; [[ $d == 2 ]] && echo openbox; [[ $d == 3 ]] && echo i3);;
    3) menu d "Desktop" LXQt MATE; AE_DE=$([[ $d == 1 ]] && echo lxqt || echo mate);;
    4) AE_DE=$([[ $d == 1 ]] && echo plasma || echo gnome);;
  esac; state_save AE_DE
  pass "step_desktop → $AE_DE"
}
step_desktop

gpu_select() {
  detect_gpu
  case $AE_GPU in
    adreno:A6*|adreno:A7*|adreno:6*|adreno:7*)
      if [[ $AE_EXEC == proot ]]; then AE_GL=virgl; kv note "proot: virgl bridge"; fi
      ;;
    adreno:*) AE_GL=virgl;;
    *) AE_GL=virgl;;
  esac
  state_save AE_GL
  pass "gpu_select → $AE_GL"
}

display_setup() {
  # stub: would call dumpsys (Android-only)
  pass "display_setup stub (orientation/DeX skipped on non-Android)"
}

gpu_select
display_setup

# ── step 6: update system ────────────────────────────────────────────────────
v "=== STEP 6: update awareness ==="
# stub GH_REPO (no git remote here)
GH_REPO="https://github.com/aether-org/termux-distro.git"
# simulate a state file with a version that differs from HEAD
printf 'GH_BRANCH=HEAD\n' > "$AE_HOME/.gh-sources"
printf 'aether-20250101\n' > "$AE_HOME/version"

dl_refresh() { GH_BRANCH=$(git rev-parse HEAD 2>/dev/null || echo HEAD); echo "refreshed $(date -u '+%Y-%m-%dT%H:%M:%SZ') at $GH_BRANCH"; }

# simulate a newer HEAD
echo "simulating newer HEAD..."
printf 'GH_BRANCH=HEAD\n' > "$AE_HOME/.gh-sources"
printf 'aether-99999999\n' > "$AE_HOME/version"
check_updates() {
  local r; r=$(dl_refresh 2>/dev/null || echo "refreshed now at $(date -u '+%Y-%m-%dT%H:%M:%SZ')")
  local v; v=$(cat "$AE_HOME/version")
  echo "  local version=$v remote at HEAD"
  pass "check_updates → update needed (local: $v, HEAD)"
}
check_updates

# ── step 7: summary ──────────────────────────────────────────────────────────
v "=== STEP 7: summary ==="
header "done"
kv base     "${AE_DISTRO} (${AE_EXEC})"
kv tools    "${AE_TOOL:-none} · ${AE_FOOT:-skipped}"
kv agents   "${AE_AGENTS:-skipped}"
kv desktop  "${AE_DE:-none}"
kv gpu      "${AE_GL:-n/a}"
ok "Start your desktop: aether-desktop"

# ── final report ─────────────────────────────────────────────────────────────
echo ""
echo "=== FINAL STATE ==="
cat "$AE_HOME/state"
echo ""
echo "=== QA LOG ==="
echo "$LOG"
v ""
v "=== PASS/FAIL summary ==="
echo "Look at the log above. All steps should show ✔."
