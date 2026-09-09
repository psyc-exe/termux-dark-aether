# Aether Distro Launcher

Modular bash installer + embedded Android APK that turn stock Termux (or a
self-contained APK) into a Linux workstation with X11 desktop, GPU
acceleration, agentic AI CLIs, and a no-systemd service supervisor — all
packages served from a single GitHub repo for easy updates.

## Two install methods

| Method | Installer ships | Updates |
|---|---|---|
| **Termux script** | `installer/aether-install.sh` + libs (pre-built in repo) | `aether-update` pulls latest HEAD from GH_REPO |
| **Embedded APK** | Forked Termux app (`app/`) + bundled Debian rootfs + PRoot payload | Rebuilt APK, or `aether-update` once running |

Path 2 follows the [Decentricity/Panix](https://github.com/Decentricity/Panix)
pattern: a single APK that embeds Termux core + Termux:X11 + the Debian rootfs,
so no separate Termux app, Termux:X11 APK, or VNC app is required. See
`docs/ARCHITECTURE-embedded.md`, `docs/BUILDING-embedded.md`,
`docs/FIRSTBOOT-embedded.md`.

Both paths run the *same* `installer/` bash modules; Path 2 just pre-seeds
`~/.aether/state` and calls `aether-install.sh --embedded` so the pipeline runs
headless.

## Quick start (Termux script)

```bash
pkg update; pkg install -y tsu termux-x11 termux-api dialog proot-distro
# Download installer + all libs from GH_REPO HEAD:
curl -LO https://github.com/aether-org/termux-distro/raw/main/installer/aether-install.sh
chmod +x aether-install.sh
./aether-install.sh
```

## Quick start (embedded APK)

```bash
# Build the self-contained APK (requires Android SDK 36 + NDK 29 + CMake 3.22.1):
git submodule update --init --recursive
PANIX_INCLUDE_X11_MODULE=1 PANIX_USE_EXTERNAL_NATIVE_BUILD=1 PANIX_SIGN_RELEASE=0 \
  ./scripts/build-aether-apk.sh
# Install Aether-arm64-v8a.apk → first launch extracts rootfs + starts desktop as Home
# See docs/BUILDING-embedded.md for full toolchain + signing requirements.
```

## Architecture

```
User opens Termux (pre-built script or APK boot)
    │
    ▼
lib/exec.sh           privilege flow → root / quasi / non-root
    │  quasi-root uses Shizuku/rish to disable Android phantom-process killer
    ▼  GH_REPO on-demand dl (lib/repo.sh, cached ~/.aether/)
lib/toolchain.sh       base OS → toolchain overlay → footprint → agents
    │
    ▼
lib/gpu.sh             detect GPU → probe → Turnip/Zink | VirGL | LLVMpipe
lib/desktop.sh         tiered DE install → theme → launcher
    │
    ▼
lib/update.sh          check_updates → apply_update → exec --resume
```

## Quick start (standalone APK)

Install `aether-launcher.apk` → first launch installs Termux deps → downloads
full installer from GH_REPO → runs `aether-install.sh --resume`.

## Architecture

```
User opens Termux (pre-built script or APK boot.sh)
    │
    ▼
lib/exec.sh           privilege flow → root / quasi / non-root
    │  quasi-root uses Shizuku/rish to disable Android phantom-process killer
    ▼  GH_REPO on-demand dl (lib/repo.sh, cached ~/.aether/)
lib/toolchain.sh       base OS → toolchain overlay → footprint → agents
    │
    ▼
lib/gpu.sh             detect GPU → probe → Turnip/Zink | VirGL | LLVMpipe
lib/desktop.sh         tiered DE install → theme → launcher
    │
    ▼
lib/update.sh          check_updates → apply_update → exec --resume
```

### Execution model

| Mode | check_root | Runner | Socket |
|---|---|---|---|
| root | true | chroot (tsu, bind /proc /sys /dev /tmp) | mount --bind $TMPDIR /tmp |
| quasi | false | proot-distro (--shared-tmp) + rish | $TMPDIR/.X11-unix/X1 |
| nonroot | false | proot-distro --shared-tmp | $TMPDIR/.X11-unix/X1 |

### GPU — the bionic↔glibc ABI wall

Turnip/Zink need guest-ABI Vulkan ICD — unavailable in proot. Host session
uses Turnip+Zink natively; proot guests use VirGL over a UNIX socket. Probe
with `glxinfo -B`; demote on failure → VirGL → LLVMpipe.

### Agent CLIs

| Tool | Android support |
|---|---|
| codex | Rust binary; sometimes works via termuxvoid fork/loader |
| claude-code / opencode | termuxvoid package only (glibc); official needs GH_REPO loader |
| cline / kilo-code / code-server | glibc only — install inside Debian guest |

Community issues: cline#8455 (GLIBC_2.34), kilo#12445 (PRoot /bin/bash). Single
reports, not universal truths.

### APT flags

```bash
APT='DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-unsafe-io -o Dpkg::Options::=--force-confnew'
```

## Project structure

```
installer/
├── aether-install.sh              entry: preflight → privilege → pipeline
├── lib/
│   ├── ui.sh                      palette, kv/menu/spinner/wait_for_socket
│   ├── exec.sh                    check_root, shizuku, chroot/proot, state
│   ├── toolchain.sh               base OS, overlay_kali/parrot, footprint, agents
│   ├── gpu.sh                     GPU select/probe/env, DPI, orientation, DeX
│   ├── desktop.sh                 tiered DEs, theme, launcher, supervisor
│   ├── repo.sh                    GH_REPO dl, extract, agent on-demand cache
│   ├── apk.sh                     APK wrapper builder (build_apk)
│   └── update.sh                  check_updates, apply_update
├── app/
│   ├── aether-bootstrap.sh        Standalone APK first-launch
│   ├── patch.sh                   GH Actions runner (all/distro/agent/tag)
│   └── update.sh                  aether-update CLI
├── apk/
│   └── aether-bootstrap.sh        APK asset stub
└── tests/test_ui.sh              kv/state/spinner tests

docs/
├── termux-distro-installer.md     architecture guide + sources
├── termux-distro-dual-delivery.md dual delivery design
└── .github/workflows/release.yml  patch → tag → upload release assets
```

## GitHub Actions

`release.yml` on push to `main` (and daily 04:00 UTC):

1. `patch.sh all` — build bin/ + distro tars + agent bundles → `installer/`
2. Tag `aether-YYYYMMDD%H%M`
3. Upload assets to GitHub release (pre-release)

To trigger manually: `./installer/app/patch.sh tag` or run the workflow from the
GitHub Actions UI. Requires `GH_TOKEN` with `contents: write`.

## GitHub repo mirror layout

```
GH_REPO
├── installer/
│   ├── aether-install.sh          ← built from installer/aether-install.sh
│   ├── lib/ui.sh lib/exec.sh ...  ← built from installer/lib/*.sh
│   ├── distro/kali-*.tar.xz       ← Kali NetHunter rootfs
│   ├── distro/parrot-*.tar.xz
│   ├── agent/native/codex/node
│   ├── agent/native/claude-code/node
│   ├── agent/native/opencode/node
│   ├── agent/glibc/cline/debian/
│   └── agent/glibc/kilocode/debian/
├── public/wallpapers/             ← forge.jpg shrine.jpg meridian.jpg veil.jpg
└── .github/workflows/release.yml
```

## Developer setup

```bash
git clone https://github.com/aether-org/termux-distro.git
cd termux-distro
./installer/app/patch.sh all    # build bin/ + distro tars
gh release create "aether-test" --prerelease installer/
# Then install: curl -LO .../aether-install.sh; chmod +x; ./aether-install.sh
```

Requires `gh` CLI authenticated with repo write access.
