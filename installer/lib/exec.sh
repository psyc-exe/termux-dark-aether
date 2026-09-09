#!/usr/bin/env bash
# lib/detect.sh + lib/shizuku.sh + lib/exec.sh — privilege flow and execution model

# ── detection ────────────────────────────────────────────────────────────────
check_root()    { command -v su >/dev/null && timeout 5 su -c 'id -u' 2>/dev/null | grep -qx 0; }
detect_arch()   { AE_ARCH=$(uname -m); [[ $AE_ARCH == aarch64 ]] || warn "arch $AE_ARCH: GPU tiers limited to LLVMpipe"; }
detect_android(){ AE_SDK=$(getprop ro.build.version.sdk); AE_ANDROID=$(getprop ro.build.version.release); }
detect_gpu() {
  if [[ -r /sys/class/kgsl/kgsl-3d0/gpu_model ]]; then
    AE_GPU="adreno:$(cat /sys/class/kgsl/kgsl-3d0/gpu_model)"
  elif [[ -e /sys/class/misc/mali0 ]] || getprop ro.hardware.egl | grep -qi mali; then AE_GPU="mali"
  else AE_GPU="unknown"; fi
}

privilege_flow() {
  header "privilege"
  if check_root; then
    kv root "available"
    menu c "Execution privilege" "Rooted — native chroot (fastest)" "Non-rooted — proot-distro (safe)"
    [[ $c == 1 ]] && AE_MODE=root AE_EXEC=chroot || AE_MODE=nonroot AE_EXEC=proot
  else
    kv root "not available"
    menu c "Execution privilege" "Quasi-root — Shizuku / rish (fix A12+ process limits)" "Non-root — standard proot-distro"
    if [[ $c == 1 ]]; then AE_MODE=quasi AE_EXEC=proot; shizuku_setup; else AE_MODE=nonroot AE_EXEC=proot; fi
  fi
  state_save AE_MODE AE_EXEC
}

# ── shizuku sub-flow ─────────────────────────────────────────────────────────
shizuku_setup() {
  header "shizuku"
  if [[ ! -x ~/rish || ! -f ~/rish_shizuku.dex ]]; then
    if [[ -f ~/rish ]]; then chmod +x ~/rish; else
      warn "rish not found in ~"; kv step1 "Shizuku → Use Shizuku in terminal apps → Export files"
      kv step2 "save rish + rish_shizuku.dex to ~/ (Termux home)"
      am start -n moe.shizuku.privileged.api/.MainActivity >/dev/null 2>&1
      printf "  ${AE_MUTED}press ⏎ when done${AE_R}"; read -r
      [[ -f ~/rish ]] || { warn "still missing — falling back to non-root"; AE_MODE=nonroot; return; }
      chmod +x ~/rish
    fi
  fi
  sed -i 's/^#\?\s*RISH_APPLICATION_ID=.*/RISH_APPLICATION_ID="com.termux"/' ~/rish
  grep -q 'RISH_APPLICATION_ID="com.termux"' ~/rish || sed -i '2i RISH_APPLICATION_ID="com.termux"' ~/rish
  rish_handshake && rish_harden || { warn "Shizuku handshake failed — continuing as non-root"; AE_MODE=nonroot; }
}

rish_handshake() {
  kv wait "authorize Termux in the Shizuku dialog"
  local t=30; while ((t--)); do
    if echo 'id -u' | ~/rish 2>/dev/null | grep -qx 2000; then ok "rish handshake · uid 2000 (shell)"; return 0; fi
    sleep 2; done; return 1
}

rish_harden() {   # Android 12+ phantom-process killer + cached-process limits
  local r=~/rish
  $r -c 'device_config set_sync_disabled_for_tests persistent' 2>/dev/null
  $r -c 'device_config put activity_manager max_phantom_processes 2147483647'
  $r -c 'settings put global settings_enable_monitor_phantom_procs false' 2>/dev/null
  $r -c 'settings put global activity_manager_constants max_cached_processes=256'
  $r -c 'pm grant com.termux android.permission.WRITE_SECURE_SETTINGS' 2>/dev/null
  local v; v=$($r -c 'device_config get activity_manager max_phantom_processes' 2>/dev/null)
  [[ $v == 2147483647 ]] && ok "phantom-process limit lifted" || warn "verify failed ($v)"
}

# ── execution model ──────────────────────────────────────────────────────────
proot_install() {           # AE_DISTRO = debian|ubuntu
  spinner "proot-distro" pkg install -y proot-distro
  proot-distro list 2>/dev/null | grep -q "installed.*$AE_DISTRO\b" && { ok "$AE_DISTRO present"; return; }
  spinner "rootfs $AE_DISTRO" proot-distro install "$AE_DISTRO"
}

chroot_setup() {            # root only; reuse proot-distro's tarball for the rootfs
  AE_ROOT=/data/local/aether/$AE_DISTRO
  local url; url=$(grep -oE 'TARBALL_URL\[.aarch64.\]="[^"]+"' "$PREFIX/etc/proot-distro/$AE_DISTRO.sh" | cut -d'"' -f2)
  tsu -c "mkdir -p $AE_ROOT && cd $AE_ROOT && curl -L '$url' | tar --numeric-owner -xJ"
  cat >"$AE_HOME/chroot-mount.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
R=$AE_ROOT; T=$TMPDIR
mountpoint -q \$R/proc || mount -t proc proc \$R/proc
mountpoint -q \$R/sys  || mount -t sysfs sys \$R/sys
mountpoint -q \$R/dev  || { mount -o bind /dev \$R/dev; mount -t devpts devpts \$R/dev/pts; }
mountpoint -q \$R/tmp  || mount -o bind \$T \$R/tmp          # X11 / virgl sockets
mountpoint -q \$R/sdcard || { mkdir -p \$R/sdcard; mount -o bind /sdcard \$R/sdcard; }
mount -o remount,dev,suid /data 2>/dev/null
EOF
  chmod +x "$AE_HOME/chroot-mount.sh"
}

# run_in_distro <cmd...>  — single entry used by every later step
run_in_distro() {
  if [[ $AE_EXEC == chroot ]]; then
    tsu -c "$AE_HOME/chroot-mount.sh; env -i HOME=/root TERM=$TERM PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      DISPLAY=${DISPLAY:-:1} PULSE_SERVER=127.0.0.1 chroot $AE_ROOT /bin/bash -lc '$*'"
  else
    proot-distro login "$AE_DISTRO" --shared-tmp --kill-on-exit \
      --env DISPLAY="${DISPLAY:-:1}" --env PULSE_SERVER=127.0.0.1 -- bash -lc "$*"
  fi
}

state_save() {
  [[ -f "$AE_HOME/state" ]] || touch "$AE_HOME/state"
  local k; for k in "$@"; do
    grep -v "^${k}=" "$AE_HOME/state" 2>/dev/null > "${AE_HOME}/.state.tmp" && mv "${AE_HOME}/.state.tmp" "$AE_HOME/state" 2>/dev/null || true
    printf '%s=%q\n' "$k" "${!k}" >> "$AE_HOME/state"
  done
}
