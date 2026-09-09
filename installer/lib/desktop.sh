#!/usr/bin/env bash
# lib/desktop.sh + lib/services.sh — step 5 session + no-systemd supervisor

# ── desktop tiers ────────────────────────────────────────────────────────────
step_desktop() {
  header "desktop"
  menu c "Desktop environment" \
    "CLI only — no X11" \
    "Lightweight — XFCE4 / Openbox / i3 (recommended)" \
    "Mid — LXQt / MATE" \
    "Heavy — KDE Plasma / GNOME (needs ≥8 GB RAM + hardware GL)"
  case $c in
    1) AE_DE=none; state_save AE_DE; return;;
    2) menu d "Window manager" XFCE4 Openbox i3wm
       AE_DE=$([[ $d == 1 ]] && echo xfce4; [[ $d == 2 ]] && echo openbox; [[ $d == 3 ]] && echo i3);;
    3) menu d "Desktop" LXQt MATE; AE_DE=$([[ $d == 1 ]] && echo lxqt || echo mate);;
    4) (( $(free -m | awk '/Mem:/{print $2}') >= 7500 )) || warn "low RAM — heavy DE will thrash"
       menu d "Desktop" Plasma GNOME; AE_DE=$([[ $d == 1 ]] && echo plasma || echo gnome);;
  esac; state_save AE_DE
  spinner "x11 repo" pkg install -y x11-repo termux-x11-nightly
  case $AE_DE in
    xfce4)   spinner xfce4 pkg install -y xfce4;;
    openbox) spinner openbox pkg install -y openbox obconf;;
    i3)      spinner i3     pkg install -y i3 i3status dmenu;;
    *)       desktop_install_guest;;   # LXQt/MATE/Plasma/GNOME from the distro
  esac
  desktop_theme; desktop_launcher
}

desktop_install_guest() {
  local pk=$AE_DE; [[ $AE_DE == lxqt ]] && pk="task-lxqt-desktop"; [[ $AE_DE == mate ]] && pk="task-mate-desktop"
  [[ $AE_DE == plasma ]] && pk="kde-plasma-desktop"; [[ $AE_DE == gnome ]] && pk="gnome-core"
  spinner "$AE_DE (distro)" run_in_distro "$APT install $pk"
}

# Aether theme: palette from src/styles.css (forge), wallpapers from public/wallpapers
desktop_theme() {
  install -d "$AE_HOME/wallpapers"; cp -n "$AE_SRC/public/wallpapers/"*.jpg "$AE_HOME/wallpapers/" 2>/dev/null
  local wall=$AE_HOME/wallpapers/forge.jpg
  cat >"$AE_HOME/gtk.css" <<EOF
@define-color accent_color #e07a38;
@define-color theme_bg_color #16120f;
@define-color theme_fg_color #f3eadf;
EOF
  if [[ $AE_DE == xfce4 ]]; then
    DISPLAY=:1 xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita-dark 2>/dev/null
    DISPLAY=:1 xfconf-query -c xsettings -p /Xft/DPI -s "${AE_DPI:-160}" 2>/dev/null
    DISPLAY=:1 xfconf-query -c xfce4-desktop --create \
      -p /backdrop/screen0/monitorscreen/workspace0/last-image -t string -s "$wall" 2>/dev/null
  fi
}

# Launcher = reference-script shape, but env-driven and socket-waited
desktop_launcher() {
  local sess
  case $AE_DE in
    xfce4) sess=xfce4-session;; openbox) sess=openbox-session;; i3) sess=i3;;
    lxqt)  sess=startlxqt;; mate) sess=mate-session;;
    plasma) sess=startplasma-x11;; gnome) sess='gnome-session --disable-acceleration-check';;
  esac
  mkdir -p "$PREFIX/bin"
  cat >"$PREFIX/bin/aether-desktop" <<EOF
#!/data/data/com.termux/files/usr/bin/env bash
# Aether desktop launcher — termuxvoid termux-desktop pattern, hardened
. $AE_HOME/gpu.env 2>/dev/null; . $AE_HOME/display.env 2>/dev/null
export DISPLAY=:1
[[ $AE_DE == lxqt || $AE_DE == mate || $AE_DE == plasma || $AE_DE == gnome ]] && \\
  STARTUP="proot-distro login $AE_DISTRO --shared-tmp --user aether --kill-on-exit -- dbus-launch --exit-with-session $sess" \\
  || STARTUP="dbus-launch --exit-with-session $sess"
termux-x11 :1 -legacy-drawing -xstartup "\$STARTUP" >/dev/null 2>&1 &
printf "Starting aether-desktop\r"; s=0
while [[ ! -S \$TMPDIR/.X11-unix/X1 && \$s -lt 20 ]]; do
  printf "Starting aether-desktop%*s\r" \$((s%5)) '' | tr ' ' '.'; sleep 1; ((s++)); done
[[ -S \$TMPDIR/.X11-unix/X1 ]] || { echo "X11 failed — check \$TMPDIR/install.log"; exit 1; }
$AE_HOME/bin/aether-orient-watch >/dev/null 2>&1 &
am start ${AE_DEX:+--display 1} --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 &
EOF
  chmod +x "$PREFIX/bin/aether-desktop"
  ok "launcher → \$PREFIX/bin/aether-desktop"
}

# ── services without systemd (init handling) ─────────────────────────────────
SVDIR="$AE_HOME/run"
svc_register() {  # svc_register postgresql  → run script using sysv init
  mkdir -p "$SVDIR/$1"
  cat >"$SVDIR/$1/run" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec proot-distro login $AE_DISTRO --shared-tmp --kill-on-exit -- service $1 start
EOF
  chmod +x "$SVDIR/$1/run"
}
svc_start() { for s in "$@"; do setsid "$SVDIR/$s/run" >/dev/null 2>&1 & done; }

storage_setup() { [[ -d ~/storage/shared ]] || spinner storage termux-setup-storage; }
