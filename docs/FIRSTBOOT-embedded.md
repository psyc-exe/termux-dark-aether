# First Boot (Embedded APK)

Aether first boot is **transactional**: install private runtime tools, verify
bundled assets, extract Debian into a staging directory, configure it, then start
embedded X11 and the chosen desktop. The contract is identical to Panix's
`FIRSTBOOT.md`, adapted to Aether's multi-choice installer.

## State machine

`AetherRuntimeManager` persists these states under
`$AETHER_FILES_DIR/aether-state/`; `AetherRuntimeService` runs the machine from a
foreground service. The Home activity starts the service, polls status, and
exposes recovery controls.

| State | Action |
|---|---|
| `NOT_INSTALLED` | entry point |
| `VERIFYING_ASSET` | verify rootfs + proot `.sha256` against APK assets |
| `INSTALLING_PROOT` | extract pinned `termux-proot-aarch64.tar.zst` into private prefix |
| `EXTRACTING` | extract rootfs into `debian.staging` with safe tar flags |
| `CONFIGURING` | ensure `/home/aether`, `/tmp`, passwd/group, sudoers, resolver, version marker |
| `READY` | rootfs healthy, not yet running desktop |
| `STARTING_X11` | `app_process` → `CmdEntryPoint` on `:1`, `TMPDIR` + `XKB_CONFIG_ROOT` set |
| `STARTING_DESKTOP` | launch chosen DE through bundled PRoot (or native for CLI-only) |
| `RUNNING` | desktop live as Home |
| `STOPPING` | user/launcher stop → back to `READY` |
| `FAILED` | → recovery menu |

## Invariant

> An existing healthy rootfs must **never** be destroyed because a new extraction
> failed. Extraction happens into `debian.staging`; it moves into `debian` only
> after verification and health checks pass. A failed extraction leaves the prior
> healthy rootfs in place.

## Implemented behavior (mirrors Panix device-proven steps)

- Installs the embedded Termux bootstrap into Aether's private `files/usr` path
  so bundled `bash`, `tar`, and `zstd` are available.
- Copies, verifies, and extracts the pinned `termux-proot-aarch64.tar.zst`
  payload into the private prefix.
- Copies `debian-aether-arm64-rootfs.tar.zst` + `.sha256` from APK assets into
  private storage.
- Verifies rootfs SHA-256 **before** extraction.
- Extracts the rootfs with Android-safe tar flags:
  `--no-same-owner --no-same-permissions --delay-directory-restore`.
- Builds the archive without populated `/dev` entries and with hardlinks
  dereferenced so Android app storage can extract it.
- Extracts into `debian.staging`; ensures `/home/aether`, `/tmp`, `passwd`,
  `group`, sudoers, resolver config, and an Aether rootfs version marker.
- Moves staging → `debian` only after health checks pass.
- Starts embedded X11 on `:1` via `app_process`; `TMPDIR` → rootfs `/tmp`,
  `XKB_CONFIG_ROOT` → bundled Debian XKB dir.
- Starts the desktop supervisor through bundled PRoot with `PROOT_LOADER`,
  `PROOT_TMP_DIR`, and `LD_LIBRARY_PATH` pointed at the Aether private prefix.
- Applies phone-friendly X11 defaults: scaled resolution, `displayScale=200`,
  fullscreen, visible extra-key bar.

## Desktop choice

Unlike Panix (hardcoded XFCE), Aether reads the user's selection from
`~/.aether/state` (written by the bash installer, or pre-seeded by the Android
UI) and launches the matching session:

| `AE_DE` | Session |
|---|---|
| `none` | CLI only — no X11 start |
| `xfce4` | `xfce4-session` |
| `openbox` | `openbox-session` |
| `i3` | `i3` |
| `lxqt` | `startlxqt` (inside rootfs) |
| `mate` | `mate-session` (inside rootfs) |
| `plasma` | `startplasma-x11` (inside rootfs) |
| `gnome` | `gnome-session --disable-acceleration-check` (inside rootfs) |

## Recovery controls (always present)

Start Runtime · Restart Desktop · Stop Desktop · Reset Debian · Open X11 Surface
· Open Aether Logs · Open Aether Terminal · Open Android Apps · Open Android
Settings · Choose Home App. These exist so a broken launcher build never traps
the user — the same safety principle Panix bakes in.
