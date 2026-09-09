# Contributing

## Getting started

1. Fork the repo and create a feature branch (`git checkout -b feat/short-description`)
2. Make your changes (see conventions in `CLAUDE.md`)
3. Test: `aether-install.sh --resume` after each change
4. Open a PR targeting `main`

## Conventions

- Bash: `set -Eeuo pipefail`; `ERR` trap with retry/skip/quit
- Palette: forge `#e07a38` on `#16120f`; kv menus with 24-bit truecolor
- State: `~/.aether/state` and `~/.aether/install.log`
- All downloads cached once in `~/.aether/{agent,dl}/`
- No secrets in source; `GH_TOKEN` is a secret; `agent.env` is chmod 600
- Mockups in `screenshots/` and `src/styles.css`; bash installer mirrors palette only

## Opening a PR

Use the [pull request template](.github/pull_request_template.md).

## Termux X11 note

The `termux-x11` package (required for GUI) is developed separately at
[termux/termux-x11](https://github.com/termux/termux-x11). Aether
currently requires `termux-x11-nightly`.

## Android 12+ compatibility

- Phantom-process killer: handled via Shizuku/rish (not root)
- `/proc` bind-mount: `mount --bind` for chroot only (proot handles it natively)
- Termux:API permission: install `termux-api` from F-Droid or GitHub releases
- Storage: `termux-setup-storage` once; guest sees `/sdcard` through proot binds
