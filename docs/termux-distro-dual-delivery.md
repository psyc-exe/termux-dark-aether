# Aether Installer — Dual Delivery (Termux script + Embedded APK)

Two install paths, shared installer logic:

- **Path 1 — Termux script**: all resources download on demand from `GH_REPO`
  (`main` HEAD, release tags for stable). No bundled assets beyond the script
  itself; `lib/repo.sh` fetches rootfs, agent CLIs, and GPU stack at runtime.
- **Path 2 — Embedded APK**: a single self-contained APK that forks the entire
  Termux app tree, vendors Termux:X11 as a subtree, and bundles the Debian
  rootfs (~220 MB) + pinned PRoot payload as APK assets — no separate Termux
  app, Termux:X11 APK, or VNC needed. Pattern:
  [Decentricity/Panix](https://github.com/Decentricity/Panix). See
  `docs/ARCHITECTURE-embedded.md`, `docs/BUILDING-embedded.md`,
  `docs/FIRSTBOOT-embedded.md`.

Both paths run the *same* `installer/` bash modules; Path 2 just pre-seeds
`~/.aether/state` and calls `aether-install.sh --embedded` so the pipeline runs
headless.

---

## Delivery paths

| | **Path 1 — Termux script** | **Path 2 — Embedded APK** |
|---|---|---|
| Installer ships | `installer/aether-install.sh` + `lib/*.sh` (pre-built in repo) | Forked Termux app (`app/`) + bundled rootfs/PRoot assets |
| First run | Uses pre-shipped `bin/` and `lib/` | `AetherRuntimeService` extracts bundled rootfs → embedded X11 → desktop as Home |
| Runtime deps | User installs Termux first | None beyond the APK itself |
| Updates | `aether-update --resume` (pulls latest HEAD) | Rebuilt APK, or `aether-update` once running |
| Assets on device | `bin/`, `lib/`, `dl/`, `agent/{native,glibc}/` | `app/src/main/assets/*`, extracted to `files/` |

---

## Remote resource layout (GH_REPO, used by Path 1 + updates)

The same repo that holds the APK workflow also serves installer assets via
`/raw/<branch>/installer/` — no second repo, no second CDN.

```
GH_REPO
├── installer/
│   ├── aether-install.sh          ← built from aether-install.sh
│   ├── lib/
│   │   ├── ui.sh
│   │   ├── exec.sh
│   │   ├── toolchain.sh
│   │   ├── gpu.sh
│   │   └── desktop.sh
│   ├── distro/                     ← GitHub ignores via installer/.gitignore
│   │   ├── kali-nethunter-*.tar.xz  ← built by patch.sh → distro/ step
│   │   └── parrot-*.tar.xz
│   ├── agent/
│   │   ├── native/
│   │   │   ├── codex/node             ← pre-built install artifact
│   │   │   ├── claude-code/node      ← pre-built install artifact
│   │   │   └── opencode/node
│   │   └── glibc/
│   │       ├── cline/debian/          ← shell wrapper (run_in_distro)
│   │       ├── kilocode/debian/
│   │       └── code-server/debian/
│   └── wallpapers/                 ← forge-aether.jpg
├── public/
│   └── wallpapers/
└── .github/
    └── workflows/
        ├── release.yml            ← triggers on push to main (Path 1 updates)
        └── build.yml             ← builds the embedded APK (Path 2)
```

---

## How update works

```bash
# From within Aether (both paths):
.
├── lib/update.sh check_updates
│   curls HEAD/installer/lib/ui.sh → compare to local hash
│   returns exit 1 if different (update needed)
│
└── lib/update.sh apply_update
    1. Backup $AE_HOME/bin/ + lib/ + version to $AE_HOME/.update-<ts>
    2. curl HEAD/installer/aether-install.sh → bin/
    3. curl HEAD/installer/lib/{ui,exec,gpu,desktop,toolchain}.sh → lib/
    4. restore ~/.aether/agent.env + ~/.bashrc lines
    5. exec aether-install.sh --resume

# Update frequency:
#   --force  : updates even if version matches (manual)
#   --check-only : just print whether update needed
#   Cron: daily 04:00 UTC check via schedule trigger in workflow

# GitHub Actions:
#   release.yml  — Path 1: on push to main / daily, tag + upload release assets
#   build.yml    — Path 2: SDK/NDK, build rootfs, pin PRoot, unsigned APK
```

---

## Bootstrap scripts (embedded per path)

### Path 1 — Termux script (pre-built in installer/bin/)
```bash
# aether-install.sh entry (same on all paths)
case $1 in
  --resume)   pipeline ;;       # already ran preflight; just continue
  --reset)    rm -f state; exec "$0" ;;
  --embedded) pipeline ;;       # Path 2: state pre-seeded, skip preflight
  *)          preflight; pipeline ;;
esac
```

### Path 2 — Embedded APK (Android glue, not bash)
```kotlin
// AetherRuntimeService.runStateMachine() (app/src/main/java/net/aether/distro/)
// 1. verify bundled rootfs + proot .sha256 against APK assets
// 2. extract debian-aether-arm64-rootfs.tar.zst → debian/ (staging → atomic move)
// 3. install proot payload into files/usr
// 4. configure rootfs (user, sudoers, resolver, version marker)
// 5. read ~/.aether/state (pre-seeded by installer flags) → start embedded X11
// 6. AetherX11Bridge starts com.termux.x11.CmdEntryPoint via app_process on :1
// 7. desktop session launched by embedded X11 -xstartup
```

The bash installer's `--embedded` flags map 1:1 to the state file the service reads:
```bash
aether-install.sh --base debian --tool kali --footprint full --de xfce4 --gl virgl --embedded
# → AE_DISTRO=debian AE_TOOL=kali AE_FOOT=full AE_DE=xfce4 AE_GL=virgl
```

---

## Agent CLI on-demand download

`lib/repo.sh` caches in `~/.aether/agent/`:

| Package | Source path in GH_REPO | Install method | Cache signal |
|---|---|---|---|
| codex | `installer/agent/native/codex/bin/` | npm i -g, npm i, or raw copy | `~/.aether/agent/native/codex/done` |
| claude-code | `installer/agent/native/claude-code/` | npm i -g, npm i, or raw copy | `~/.aether/agent/native/claude-code/done` |
| opencode | `installer/agent/native/opencode/` | npm i -g, npm i, or raw copy | `~/.aether/agent/native/opencode/done` |
| cline | `installer/agent/glibc/cline/` | build inside distro, distro wrapper | `~/.aether/agent/glibc/cline/done` |
| kilocode | `installer/agent/glibc/kilocode/` | build inside distro, distro wrapper | `~/.aether/agent/glibc/kilocode/done` |

Native caches: `npm i -g` → `done` with date stamp; `npm i` (dep) → same.
Glibc caches: wrapper script in `~/.aether/bin/`, `done` with distro + date.
Skipped entirely if `done` file exists — redownload only if cache date is old or forced.

---

## GPU / distro on-demand

Distro tarballs (`installer/distro/*.tar.xz`) are streamed and cached in
`~/.aether/dl/` — proot-distro installs from tar directly:

```bash
proot-distro install -y --from-raw-tar "$AE_HOME/dl/kali-20250101.tar.xz"
```

Or, if proot-distro is unavailable on the device (older Termux), the tar
extracts into `$AE_HOME/distro/kali/` and `step_base_os` can do a manual
`tar xf` + `command -v tsu >/dev/null && tsu -c 'tar xf' …`.

Agent-patch distro mirrors: `lib/repo.sh::dl_agent_glibc` runs inside the
distro to compile Node + the agent; it can also push a patched patch tarball
to `$AE_HOME/dl/agent-$name.patch` if `node build.js patch` is available.

In **Path 2 (embedded)** the rootfs is bundled and extracted at first boot
(`docs/FIRSTBOOT-embedded.md`), so distro on-demand download applies only to
post-install expansions (Kali/Parrot overlays, agent CLIs, GPU stack).

---

## Quick path summary (how a user installs)

```bash
# Method A — Termux script (pre-built in repo):
termux-setup-storage
# copy aether-install.sh to Termux home via Termux:API, or:
curl -LO https://github.com/aether-org/termux-distro/raw/main/installer/aether-install.sh
chmod +x aether-install.sh
./aether-install.sh

# Method B — Embedded APK (build then install):
./scripts/build-aether-apk.sh        # or: gh workflow run build.yml
# install Aether-arm64-v8a.apk → first launch extracts rootfs + starts desktop
# (see docs/BUILDING-embedded.md for toolchain + signing requirements)

# Update (both methods):
aether-update
```

---

## Build machine setup (for maintainers)

```bash
# Path 1 release automation:
#   git clone https://github.com/aether-org/termux-distro.git
#   ./installer/app/patch.sh all    # build bin/ + distro tars
#   gh release create "aether-test" --prerelease installer/

# Path 2 embedded APK (requires Android SDK 36 + NDK 29 + CMake 3.22.1):
#   git submodule update --init --recursive
#   PANIX_INCLUDE_X11_MODULE=1 PANIX_USE_EXTERNAL_NATIVE_BUILD=1 \
#     PANIX_SIGN_RELEASE=0 ./scripts/build-aether-apk.sh
#   See docs/BUILDING-embedded.md and .github/workflows/build.yml
```
