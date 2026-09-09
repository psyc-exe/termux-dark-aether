#!/usr/bin/env bash
# aether-install — modular Termux Linux-distribution installer (Android 12–15+)
# Layout: installer/lib/{ui,exec,toolchain,gpu,desktop}.sh — see docs/termux-distro-installer.md
#
# Two delivery paths share this script:
#   Path 1 (Termux script):  run normally; menus drive the choices.
#   Path 2 (embedded APK):   AetherRuntimeService pre-seeds ~/.aether/state then
#                            calls:  aether-install.sh --base debian --tool kali \
#                              --footprint full --de xfce4 --gl virgl --embedded
#                            All flags pre-seed state; the pipeline sees them as
#                            already-completed steps and runs straight to summary.
set -Eeuo pipefail

AE_HOME=$HOME/.aether
AE_SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export AE_HOME AE_SRC
mkdir -p "$AE_HOME" "$AE_HOME/bin" || install -d -m700 "$AE_HOME" "$AE_HOME/bin" 2>/dev/null || true
touch "$AE_HOME/install.log" "$AE_HOME/state"
[[ -s $AE_HOME/state ]] && . "$AE_HOME/state" 2>/dev/null || true   # --resume / pre-seed

for l in ui exec toolchain gpu desktop; do . "$AE_SRC/installer/lib/$l.sh"; done

# ── embedded / headless flags (Path 2) ────────────────────────────────────────
EMBEDDED=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --base)       AE_DISTRO="$2"; state_save AE_DISTRO; shift 2;;
    --tool)       AE_TOOL="$2"; state_save AE_TOOL; shift 2;;
    --footprint)  AE_FOOT="$2"; state_save AE_FOOT; shift 2;;
    --agents)     AE_AGENTS="$2"; state_save AE_AGENTS; shift 2;;
    --de)         AE_DE="$2"; state_save AE_DE; shift 2;;
    --gl)         AE_GL="$2"; state_save AE_GL; shift 2;;
    --mode)       AE_MODE="$2"; state_save AE_MODE; shift 2;;
    --exec)       AE_EXEC="$2"; state_save AE_EXEC; shift 2;;
    --embedded)   EMBEDDED=1; shift;;
    --resume)     shift;;
    --reset)      rm -f "$AE_HOME/state"; exec "$0";;
    --launcher)   desktop_launcher; exit 0;;
    *) shift;;
  esac
done
# Re-source state so flags take effect
. "$AE_HOME/state" 2>/dev/null || true

on_err() { warn "step failed at line $1 — retry / skip / quit? (install.log has details)"
  select a in retry skip quit; do case $a in retry) return 1;; skip) return 0;; *) exit 1;; esac; done; }
trap 'on_err $LINENO || true' ERR

preflight() {
  detect_android; detect_arch
  header "preflight"
  kv android "${AE_ANDROID:-?} (sdk ${AE_SDK:-?})"; kv arch "${AE_ARCH:-?}"
  [[ ${AE_SDK:-0} -ge 31 ]] || warn "Android <12: phantom-killer tweaks unnecessary"
  [[ $EMBEDDED == 1 ]] && { kv mode "embedded (deps pre-bundled)"; return; }
  spinner "termux base" pkg update -y
  spinner "termux deps" pkg install -y tsu termux-api termux-tools pulseaudio dialog
  storage_setup
}

pipeline() {
  # Embedded (Path 2): privilege is decided by the Android runtime; default to
  # unprivileged proot so the pipeline never blocks on an interactive prompt.
  [[ $EMBEDDED == 1 ]] && { AE_MODE=${AE_MODE:-nonroot}; AE_EXEC=${AE_EXEC:-proot}; state_save AE_MODE AE_EXEC; }
  [[ ${AE_MODE:-}   ]] || privilege_flow
  [[ ${AE_DISTRO:-} ]] || step_base_os
  [[ ${AE_TOOL:-}   ]] || step_toolchain
  [[ ${AE_FOOT:-}   ]] || { step_footprint; AE_FOOT=done; state_save AE_FOOT; }
  [[ ${AE_AGENTS:-} ]] || { step_agents;   AE_AGENTS=done; state_save AE_AGENTS; }
  [[ ${AE_DE:-}     ]] || step_desktop
  [[ ${AE_GL:-} && $AE_DE != none ]] || { gpu_select; display_setup; }
  summary
}

summary() {
  header "done"
  kv base     "${AE_DISTRO} (${AE_EXEC})"
  kv toolchain "${AE_TOOL:-none} · ${AE_FOOT:-skipped}"
  kv agents   "${AE_AGENTS:-skipped}"
  kv desktop  "${AE_DE:-none}"
  kv gpu      "${AE_GL:-n/a}"
  echo; ok "Start your desktop: aether-desktop"
  [[ ${AE_DEX:-0} == 1 ]] && kv dex "launches on external display when connected"
  warn "API keys: put them in $AE_HOME/agent.env (chmod 600 already set)"
}

case ${EMBEDDED:-0} in
  1) pipeline;;
  *) preflight; pipeline;;
esac
