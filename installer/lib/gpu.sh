#!/usr/bin/env bash
# lib/gpu.sh + lib/display.sh — step 5 display pipeline

# ── GPU ──────────────────────────────────────────────────────────────────────
# Turnip = Adreno 6xx+ only (Mesa Freedreno Vulkan 1.3). Mali uses Panfrost/PanVK
# but often needs newer kernels than Android ships. The bionic<->glibc ABI wall
# means the guest (proot/chroot) CANNOT dlopen Termux's bionic Vulkan/Mesa
# drivers directly. Hardware GL across the boundary requires an IPC bridge:
# VirGL (guest virpipe client -> host virgl_test_server_android over UNIX socket).
# Zink inside proot is only possible with a guest-ABI-compatible Vulkan ICD,
# which we do not have; so Zink runs in the TERMUX host session only.
gpu_select() {
  detect_gpu
  case $AE_GPU in
    adreno:A6*|adreno:A7*|adreno:6*|adreno:7*)
      # Turnip only works in the host (bionic). For proot guests we still use
      # VirGL because the guest cannot load bionic Vulkan drivers.
      if [[ $AE_EXEC == proot ]]; then
        AE_GL=virgl; host_pkgs="virglrenderer-android"
        kv note "Turnip is host-only; proot guest uses VirGL bridge"
      else
        AE_GL=zink;   # Turnip+Zink in TERMUX host (fastest, native Vulkan)
        host_pkgs="mesa-zink mesa-vulkan-icd-freedreno vulkan-loader-android"
      fi
      ;;
    adreno:*) AE_GL=virgl; host_pkgs="virglrenderer-android";;
    mali|*)   AE_GL=virgl; host_pkgs="virglrenderer-android";;   # Mali: no Turnip, PanVK may fail on stock kernels
  esac
  header "gpu"; kv gpu "$AE_GPU"; kv plan "$AE_GL"
  spinner "gpu stack" pkg install -y $host_pkgs mesa-utils
  gpu_probe || { warn "$AE_GL probe failed — LLVMpipe fallback"; AE_GL=llvmpipe; }
  gpu_env > "$AE_HOME/gpu.env"; state_save AE_GL
}

gpu_probe() {
  case $AE_GL in
    zink)  timeout 15 zink_test 2>/dev/null || GALLIUM_DRIVER=zink timeout 15 glxinfo -B 2>/dev/null | grep -qi zink;;
    virgl) pgrep -f virgl_test_server >/dev/null || virgl_test_server_android >/dev/null 2>&1 &
           GALLIUM_DRIVER=virpipe timeout 15 glxinfo -B 2>/dev/null | grep -qi virgl;;
    *)     return 1;;
  esac
}

gpu_env() {   # sourced by launcher + run_in_distro env list
  case $AE_GL in
    zink)     echo 'export MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink TU_DEBUG=noconform';;
    virgl)    echo 'export GALLIUM_DRIVER=virpipe' ; echo 'export MESA_GL_VERSION_OVERRIDE=4.6';;
    llvmpipe) echo "export GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=$(nproc 2>/dev/null || echo 4) LIBGL_ALWAYS_SOFTWARE=1";;
  esac
}

# ── display / DPI / orientation / DeX ────────────────────────────────────────
display_setup() {
  local dpi; dpi=$(getprop ro.sf.lcd_density 2>/dev/null || echo 160)
  case ${dpi:-160} in
    ''|*[!0-9]*) dpi=160;;
    4[0-9][0-9]|5[0-9][0-9]|6[0-9][0-9]) AE_SCALE=2;;   # ≥400 -> HiDPI
    *) AE_SCALE=1;;
  esac
  cat >"$AE_HOME/display.env" <<EOF
export AE_DPI=$dpi AE_SCALE=$AE_SCALE
export GDK_SCALE=$AE_SCALE QT_SCALE_FACTOR=$AE_SCALE
EOF
  state_save AE_DPI AE_SCALE
  # orientation watcher: XFCE/LXQt re-layout on rotate (spawned from launcher)
  cat >"$AE_HOME/bin/aether-orient-watch" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
prev=""
while sleep 2; do
  cur=$(DISPLAY=${DISPLAY:-:1} xdpyinfo 2>/dev/null | awk '/dimensions/{print $2}')
  [[ -n $cur && $cur != "$prev" ]] || continue; prev=$cur
  DISPLAY=:1 xrandr --output default --auto 2>/dev/null
  DISPLAY=:1 xfce4-panel -r 2>/dev/null || DISPLAY=:1 lxqt-panel -r 2>/dev/null
done
EOF
  chmod +x "$AE_HOME/bin/aether-orient-watch"
  # DeX / external display: offer when a second display exists
  if dumpsys display 2>/dev/null | grep -q 'mDisplayId=1'; then
    confirm "External display detected — also launch on DeX/desktop display?" && AE_DEX=1 && state_save AE_DEX
  fi
}
