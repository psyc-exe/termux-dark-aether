# Aether Embedded APK — Architecture

Aether's **Path 2** is a single, self-contained Android APK: a Termux-derived
application that bundles Termux core, an *embedded* Termux:X11 server, a pinned
Debian (or Kali/Parrot) rootfs, and a pinned PRoot payload — so no separate
Termux app, Termux:X11 APK, or VNC app is required. First boot extracts the
rootfs, starts embedded X11, and launches the chosen desktop as the Android
**Home** launcher. This is the same pattern as
[Decentricity/Panix](https://github.com/Decentricity/Panix), adapted to Aether's
modular installer.

## Repository layout (build-time)

```
aether-apk/                         ← this repo's android/ subtree
├── app/                           ← forked Termux app module + Aether glue
│   ├── src/main/
│   │   ├── AndroidManifest.xml    ← package net.aether.distro, HOME + launcher
│   │   ├── assets/                ← bundled at build time (see build-aether-apk.sh)
│   │   │   ├── debian-aether-arm64-rootfs.tar.zst
│   │   │   ├── debian-aether-arm64-rootfs.tar.zst.sha256
│   │   │   ├── termux-proot-aarch64.tar.zst
│   │   │   └── termux-proot-aarch64.tar.zst.sha256
│   │   ├── java/net/aether/distro/
│   │   │   ├── AetherHomeActivity.java      ← subclasses vendored X11 MainActivity
│   │   │   ├── AetherRuntimeService.java    ← foreground service, state machine
│   │   │   ├── AetherRuntimeManager.java    ← rootfs txn: copy/verify/extract/configure
│   │   │   └── AetherX11Bridge.java         ← starts CmdEntryPoint via app_process
│   │   └── res/ …
├── terminal-emulator/             ← from Termux fork (submodule)
├── terminal-view/                 ← from Termux fork (submodule)
├── termux-shared/                 ← from Termux fork (submodule)
├── third_party/termux-x11/        ← Termux:X11 vendored via git subtree
├── rootfs/                        ← rootfs build recipe + manifests
│   ├── manifests/*.sha256         ← checksums the build copies into assets
│   └── build-rootfs.sh            ← produces debian-aether-*.tar.zst
├── scripts/
│   ├── build-aether-apk.sh        ← top-level orchestrator (mirrors build-panix.sh)
│   ├── build-proot-payload.sh     ← pins proot + libs from verified .deb
│   ├── build-bootstrap-lib.sh
│   ├── build-terminal-emulator-lib.sh
│   ├── build-shared-lib.sh
│   └── inspect-aether-apk.sh      ← post-build structure assertions
└── .github/workflows/build.yml    ← CI: SDK/NDK, rootfs, proot, unsigned APK
```

## Package identity

- Android package id: **`net.aether.distro`** (own namespace — avoids the
  `com.termux.*` path conflicts Panix documents).
- Java/Kotlin namespaces are migrated to `net.aether.distro` where the Aether
  glue lives; the vendored Termux/Termux:X11 code keeps its upstream namespaces
  to minimise refactor risk (same trade-off Panix made).
- `AetherHomeActivity` subclasses the vendored Termux:X11 `MainActivity`,
  preserving its `LorieView` surface, input, resize, clipboard, and binder
  connection, while adding the Aether emergency menu overlay + runtime status.

## Runtime path

```
Debian GUI application
  → X11 protocol
  → local Unix socket shared through Aether tmp
  → embedded Termux:X11 server (libXlorie.so from APK)
  → Android native Surface in AetherHomeActivity
```

- `AetherX11Bridge` starts `com.termux.x11.CmdEntryPoint` via Android
  `app_process`, with `CLASSPATH` pointed at the Aether APK and `TMPDIR` at
  Aether's private shared tmp.
- `XKB_CONFIG_ROOT` is set to the bundled Debian rootfs XKB directory so the
  embedded X11 server does not depend on Termux paths.
- Release packaging stores `lib/arm64-v8a/libXlorie.so` **uncompressed**
  because the embedded X11 command entry point loads it directly from the APK.

## First-boot state machine

`AetherRuntimeManager` persists states under
`$AETHER_FILES_DIR/aether-state/`; `AetherRuntimeService` runs the machine from
a foreground service. The Home activity starts the service, polls status, and
exposes recovery controls.

```
NOT_INSTALLED → VERIFYING_ASSET → INSTALLING_PROOT → EXTRACTING
  → CONFIGURING → READY → STARTING_X11 → STARTING_DESKTOP → RUNNING
  → (STOPPING) → READY
  → (FAILED) → recovery menu
```

See [FIRSTBOOT.md](FIRSTBOOT.md) for the transactional contract.

## How Aether's bash installer fits

The `installer/` bash modules are **not** reimplemented in Java. Instead:

- The Android glue handles the *system* layer: asset extraction, PRoot install,
  embedded X11 start, desktop launch.
- The bash installer (`installer/aether-install.sh`) handles the *choice* layer:
  base OS, toolchain overlay, footprint, agents, desktop, GPU — driven
  **non-interactively** via flags when launched from the embedded context:
  `aether-install.sh --base debian --tool kali --footprint full --de xfce4 --gl virgl`.
- In interactive Path-1 (standalone Termux) the same script presents the menus
  normally; the Android glue simply pre-seeds `~/.aether/state` and calls it
  headless.

This keeps one source of truth for install logic across both delivery paths.
