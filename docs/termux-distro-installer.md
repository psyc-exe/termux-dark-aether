# Aether Distro Installer — Architecture & Implementation Guide

Modular bash installer that turns stock Termux (Android 12–15+) into a Linux
workstation: privilege detection → base OS → security toolchain → footprint →
agentic AI CLIs → desktop + GPU pipeline. Styled after the project's **Aether**
desktop mockups (`src/styles.css`, `TerminalApp.tsx`, `screenshots/`).

Companion code: `installer/aether-install.sh` + `installer/lib/*.sh`
(bash-syntax-checked; helper tests in `installer/tests/`).

> **Provenance note:** every load-bearing compatibility claim below carries a
> source. Community scripts and issue reports are marked as such — they show
> what people have *tried*, not what is guaranteed to work.

---

## 0. What the reference script teaches (and what it hides)

`termuxvoid/termux-desktop` (21 lines) is the entire runtime contract [1]:

```bash
termux-x11 :1 -xstartup "dbus-launch --exit-with-session xfce4-session" >/dev/null 2>&1 &
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 &
```

Three things happen implicitly; the installer makes them explicit:

| Implicit in reference | Explicit in Aether |
|---|---|
| `termux-x11 :1` creates the X socket `$TMPDIR/.X11-unix/X1`; `-xstartup` inherits `DISPLAY=:1` | `lib/display.sh`/`lib/desktop.sh` write `~/.aether/*.env` (`DISPLAY`, `PULSE_SERVER`, GPU vars) sourced by every launcher; the launcher **waits on the socket** instead of fixed `sleep`s |
| Session runs **natively in Termux** (xfce4 from `x11-repo`) | Session may run in **proot/chroot**; X crosses the boundary via `--shared-tmp` (proot) or `mount --bind $TMPDIR /tmp` (chroot) [2] |
| `dbus-launch --exit-with-session` = poor-man's init | Same, plus `lib/services.sh` no-systemd supervisor using the distros' own sysv scripts |
| `am start` opens the X11 activity, fire-and-forget | `am start` after socket-ready poll, `--display 1` for DeX/external display |

---

## 1. Environment detection & privilege flow

```
check.root ──true──▶ [ Rooted (chroot) | Non-rooted (proot) ]
           └─false─▶ [ Quasi-root: Shizuku/rish | Non-root (proot) ]
                              │
                              ▼  shizuku.setup → wait auth → handshake → harden → return
```

### 1.1 `check.root`
```bash
check_root() {
  command -v su >/dev/null || return 1
  timeout 5 su -c 'id -u' 2>/dev/null | grep -qx 0
}
```
`tsu` is used for actual escalation (keeps `$PREFIX` / `LD_PRELOAD`).

### 1.2 Shizuku / rish (quasi-root, uid 2000 `shell`) — *capability honesty*

rish is **adb shell privilege, not root**. It cannot `mount`, `chroot`, or
`unshare` (no unprivileged user namespaces on Android; `CAP_SYS_CHROOT` absent).
Its real value is fixing the **Android 12+ phantom-process killer**, the #1
killer of long proot/apt sessions:

| Need | rish command |
|---|---|
| Disable phantom-process killer (A12+) | `device_config set_sync_disabled_for_tests persistent && device_config put activity_manager max_phantom_processes 2147483647` |
| A12L+ variant | `settings put global settings_enable_monitor_phantom_procs false` |
| Launch X11 on external display | `am start --display 1 -n com.termux.x11/.MainActivity` |

Shizuku itself is started via root, wireless debugging (Android 11+), or a
computer; the wireless-debugging pairing must be repeated after each reboot [3].
Sub-flow (`lib/exec.sh::shizuku_setup`): locate `~/rish` + `~/rish_shizuku.dex`
(user exports from Shizuku → *Use Shizuku in terminal apps*), patch
`RISH_APPLICATION_ID="com.termux"`, then a 60 s handshake loop
(`echo 'id -u' | ~/rish` → expect `2000`). On failure it **falls back to
non-root proot and says so** — never silently.

### 1.3 Execution model matrix

| | **chroot** (real root) | **proot-distro** (non-root / quasi) |
|---|---|---|
| Syscall cost | native — zero | ptrace interception; heavy on fs work (`apt`, `npm i`), negligible for GUI |
| Needs | `tsu`, bind mounts; `mount -o remount,dev,suid /data` for suid bins | nothing extra; `pkg i proot-distro` |
| `/dev`,`/proc`,`/sys` | real bind mounts | proot fakes/hides; **"proot is path translation, not kernel isolation"** [16] |
| Fake uid 0 | real | emulated; `chown`/`setuid` succeed silently but don't persist |
| Sockets to Termux | `mount --bind $TMPDIR /tmp` | `--shared-tmp` |
| Risk | bricking `/data` perms if careless | none |

Decision: **root → chroot**, everything else → **proot-distro**; quasi-root =
proot + rish hardening. Persisted as `AE_EXEC` in `~/.aether/state`.

---

## 2. Interactive pipeline

Each step persists to `~/.aether/state` immediately; `aether-install --resume`
continues after a kill.

### Step 1 · Base OS
Debian stable or Ubuntu LTS via `proot-distro install debian|ubuntu` [2]. For
chroot, the proot-distro plugin's rootfs tarball is extracted under `tsu` with
`tar --numeric-owner`.

### Step 2 · Toolchain — *do not mix distro repositories*

**Correction from research:** adding Kali's repo to a non-Kali OS is the
self-described *"single most common reason why Kali Linux systems break"* [4].
The overlay design is therefore:

- **Default:** a **real Kali (NetHunter rootfs)** or **real Parrot rootfs**
  installed as its own proot-distro guest — never repo-surgery on Debian.
- The earlier "pinned overlay" idea survives only as an *expert, unsupported*
  toggle in `lib/toolchain.sh::overlay_kali` with `Pin-Priority: 50` and an
  explicit breakage warning; Ubuntu base refuses it outright.

| Choice | Mechanism |
|---|---|
| Kali NetHunter | official `kali-nethunter-rootfs-*-arm64.tar.xz` as a custom proot-distro plugin; repos already correct (`kali-rolling`, keyring `kali-archive-keyring.gpg`) [4] |
| Parrot OS | Parrot rootfs / `parrot-core` on its own Debian-12-based guest |
| None | plain base |

### Step 3 · Footprint
| Footprint | Kali | Parrot |
|---|---|---|
| Minimal | `kali-linux-core` | `parrot-core` |
| Top-10 | `kali-tools-top10` | curated: nmap metasploit-framework sqlmap aircrack-ng hydra john wireshark burpsuite nikto gobuster |
| Full | `kali-linux-headless` (confirm twice; >10 GB, hours under proot) | `parrot-tools-full` |

`apt` tuning in proot: `-o Dpkg::Options::=--force-unsafe-io`, `nodoc`
path-exclude, `termux-wake-lock` around the install.

### Step 4 · Agentic AI CLIs — corrected execution model

The comfortable myth — "these are pure-JS npm CLIs, install anywhere" — is
wrong on current evidence:

- **Codex is Rust.** The CLI is `codex-rs` (`path = "src/main.rs"`) [5]; the
  npm package is a launcher that `spawn`s a downloaded native binary [6]. The
  launcher does have an `android` case mapping to linux-musl targets [6] —
  that is launcher handling, not a promise every sandbox/tool operation works.
- **TermuxVoid's own packages prove the workaround culture:** its codex
  package installs a third-party fork `@mmmbuto/codex-cli-termux` [7];
  claude-code downloads `claude-linux-arm64.tar.gz` and compiles a C launcher
  hardwired to `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` [8]; opencode does the
  same loader trick [9]. These are **community packaging recipes**, inspected
  not executed — evidence of strategy, not of success.
- **Cline / Kilo Code have native dependencies.** Cline's own build notes say
  cross-compiled builds fail on `@opentui/core`'s FFI layer [10]; Kilo's build
  script explicitly enumerates glibc and musl dynamic loaders — Android/bionic
  is not a target [11]. Community reports: `GLIBC_2.34 not found` on one setup
  [12], `/bin/bash` hard-coded on another [13], a Termux/PRoot failure with a
  device-specific workaround in Kilo's tracker [14]. **Single issue reports ≠
  general truth; treat each tool as "validate before promising."**
- `mmmbuto/codex-vl`: the repo lookup returned GitHub's `404 Not Found` [15].
  The user's malformed `@file` token stays unresolved — no repair attempted.

**Decision — hybrid, distro-first for glibc consumers:**
1. **Try official binaries natively** (codex's android→musl path sometimes
   works); on failure, fall back to termuxvoid's fork/loader **with a warning**.
2. **glibc-only tools (Cline, Kilo, code-server) install inside the Debian
   guest** where the loader actually matches, exposed to Termux via thin
   `proot-distro login --shared-tmp` wrappers in `~/.aether/bin/`.
3. Reject `glibc-runner` + root-only `/bin/bash` symlink hacks as default
   (breaks on OTA); expert toggle only.
4. Shared `~/.aether/agent.env` (chmod 600) holds API keys for both sides.

### Step 5 · Desktop & display pipeline

| Tier | Session | Notes |
|---|---|---|
| CLI only | — | X11 stack optional later |
| Lightweight | `xfce4-session` / `openbox-session` / `i3` | XFCE = reference default; installed **natively in Termux** (fastest, no ABI wall) |
| Mid | `startlxqt`, `mate-session` | from the distro guest |
| Heavy | `startplasma-x11`, `gnome-session --disable-acceleration-check` | ≥8 GB RAM guard; LLVMpipe-only devices warned |

**GPU — the ABI wall is the architecture.** Termux's Mesa/Vulkan drivers are
bionic-linked; a glibc guest **cannot `dlopen` them** — that is precisely the
gap libhybris exists to fill [17]. So:

```
Adreno 6xx/7xx + host session  → Turnip + Zink (Termux: mesa-zink,
                                  mesa-vulkan-icd-freedreno) [18][19]
Adreno 6xx/7xx + proot guest   → VirGL bridge: guest GALLIUM_DRIVER=virpipe →
                                  UNIX socket → host virgl_test_server_android [20][21]
Mali / Adreno 5xx / unknown    → VirGL (PanVK is Mali's Vulkan but experimental
                                  and may need newer kernels than stock [22])
Probe failure                    → LLVMpipe: GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=$(nproc)
```

Probe with `glxinfo -B` in the *target* environment; demote one tier and
re-probe on failure. VirGL's guest↔host link is a real UNIX `socket(PF_UNIX)`
in Termux's patch set [21] — protocol visibility through `--shared-tmp` is the
defensible path; direct guest Zink would require a guest-ABI Vulkan ICD, which
does not exist here.

**Display config (`lib/gpu.sh::display_setup`)**
- DPI from `getprop ro.sf.lcd_density`; ≥400 → `GDK_SCALE=2`, `Xft.dpi`
  (Termux:X11 also accepts a `-dpi` flag [23]).
- Orientation: watcher polls `xdpyinfo` dimensions every 2 s →
  `xrandr --auto` + panel restart (`xfce4-panel -r`).
- DeX/external: `am start --display 1 …` when `dumpsys display` shows a second
  display; `termux-x11-preference "fullscreen"="false"` etc. for desktop mode [23].

**Audio:** host `pulseaudio --start --exit-idle-time=-1
--load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1"`;
guest `PULSE_SERVER=127.0.0.1`.

---

## 3. Sockets, init and permissions — the plumbing

```
Termux (bionic)                        Guest (glibc)
┌──────────────────────────┐          ┌──────────────────────────┐
│ termux-x11 :1            │ X1 sock  │ DISPLAY=:1               │
│  $TMPDIR/.X11-unix/X1  ──┼──────────┼─▶ /tmp/.X11-unix/X1      │
│ pulseaudio tcp :4713  ──────────────┼─▶ PULSE_SERVER=127.0.0.1 │
│ virgl_test_server_android─ .virgl ──┼─▶ GALLIUM_DRIVER=virpipe │
│ am / termux-api          │          │ dbus-launch → session    │
└──────────────────────────┘          └──────────────────────────┘
   proot: --shared-tmp            chroot: mount --bind $TMPDIR /tmp
```

- **No systemd anywhere:** `dbus-launch --exit-with-session` is session leader
  (as in the reference); daemons (postgres for Metasploit, ssh) run via the
  distros' sysv scripts under `lib/services.sh` with pid tracking in
  `~/.aether/run/`.
- **Storage:** `termux-setup-storage` once; guest sees `/sdcard` through
  proot-distro's default binds or a chroot bind mount. Rootfs never lives on
  `/sdcard` (noexec/FAT).
- **Background survival:** wake lock during installs; rish/root hardening
  table from §1.2; pure non-root prints the Developer-options workaround.

---

## 4. UX alignment with the Aether mockups

Tokens from `src/styles.css` (`html[data-wp]`) and `TerminalApp.tsx`:

| Token | Source | ANSI mapping |
|---|---|---|
| bg `#16120f` / surface `#221c18` | `--ae-bg/--ae-surface` (forge) | menu background |
| fg `#f3eadf`, muted `#b5a090` | `--ae-fg/--ae-muted` | text / 8-char-padded `kv` labels (the mock's `os`/`host`/`kernel` block) |
| accent `#e07a38` (shrine `#e09a4a`, meridian `#d49478`, veil `#c9a06a`) | `--ae-accent` | prompt `guest@lumen ~ ▸`, selected row, header |
| ok | `text-ae-accent-2` | `#7fb77e` ✔; warn reuses accent with ▲ |

Carried rules: `▸` prompt glyph; two-column key/value info block; thin `─`
rule in accent-at-42%; arrow-key numbered menus with accent-filled cursor row
and `↑↓ move · ⏎ select · q quit` footer; whiptail (matching `NEWT_COLORS`)
then plain `select` as fallbacks. Wallpapers from `public/wallpapers/*.jpg`
are copied to `~/.aether/wallpapers/` and applied via `xfconf-query`; GTK gets
`@define-color accent_color #e07a38` on Adwaita-dark. (The mock's rounded
window corners and sidebar are desktop chrome — out of bash's reach; the
installer reproduces palette, layout rhythm, and prompt language only.)

---

## 5. Module layout & verification status

```
installer/
  aether-install.sh        entry: flags, preflight, resumable pipeline, ERR trap
  lib/ui.sh                palette, kv/menu/spinner/wait_for_socket   (tested)
  lib/exec.sh              check_root, shizuku flow, proot/chroot, state  (tested)
  lib/toolchain.sh         base OS, kali/parrot rootfs, footprints, agents
  lib/gpu.sh               gpu_select/probe/env, DPI, orientation, DeX
  lib/desktop.sh           tiered DE install, theme, launcher, svc supervisor
  tests/test_ui.sh         kv format, state round-trip, socket timeout  (PASS)
```

Verified here: `bash -n` clean on all modules; helper tests pass; spinner and
socket-wait exercised. **Not** verified (needs the Android device): actual
apt/proot runs, VirGL rendering, rish handshake timing, per-tool agent CLIs.
The installer treats those as probe-at-runtime with demotion/fallback, which is
the honest design given the evidence above.

## Sources

[1] https://raw.githubusercontent.com/termuxvoid/repo/20d8c9ca29103b819d1a0778a60950f065c00bc3/packages/termux-desktop/data/data/com.termux/files/usr/bin/termux-desktop
[2] https://github.com/termux/proot-distro
[3] https://shizuku.rikka.app/guide/setup/
[4] https://www.kali.org/docs/general-use/kali-linux-sources-list-repositories/
[5] https://raw.githubusercontent.com/openai/codex/main/codex-rs/cli/Cargo.toml
[6] https://raw.githubusercontent.com/openai/codex/main/codex-cli/bin/codex.js
[7] https://raw.githubusercontent.com/termuxvoid/repo/main/packages/codex-cli/DEBIAN/postinst
[8] https://raw.githubusercontent.com/termuxvoid/repo/main/packages/claude-code/DEBIAN/postinst
[9] https://raw.githubusercontent.com/termuxvoid/repo/main/packages/opencode/DEBIAN/postinst
[10] https://raw.githubusercontent.com/cline/cline/main/apps/cli/script/build.ts
[11] https://raw.githubusercontent.com/Kilo-Org/kilocode/main/packages/opencode/script/build.ts
[12] https://api.github.com/repos/cline/cline/issues/8455
[13] https://api.github.com/repos/cline/cline/issues/13722
[14] https://github.com/Kilo-Org/kilocode/issues/12445
[15] https://api.github.com/repos/mmmbuto/codex-vl
[16] https://raw.githubusercontent.com/termux/proot-distro/master/README.md
[17] https://raw.githubusercontent.com/libhybris/libhybris/master/README.md
[18] https://docs.mesa3d.org/drivers/freedreno.html
[19] https://docs.mesa3d.org/drivers/zink.html
[20] https://raw.githubusercontent.com/termux/termux-packages/master/packages/virglrenderer-android/build.sh
[21] https://raw.githubusercontent.com/termux/termux-packages/master/packages/virglrenderer/vtest-vtest_protocol.h.patch
[22] https://docs.mesa3d.org/drivers/panfrost.html
[23] https://github.com/termux/termux-x11
