#!/usr/bin/env bash
# lib/repo.sh — Aether remote resource accessor. All on-demand downloads
# (base rootfs, Kali/Parrot tars, agent CLI binaries, GPU stack, wallpapers)
# are served from the GitHub repo at GH_REPO. Local cache in ~/.aether/dl/
# Layout: mirror / on-disk tree mirrors GH tree, so the same repo serves both
# APK embed + standalone Termux install.
#
# GH_REPO shape (mirror of installer/ on disk):
#   installer/
#     bin/          ← fully built scripts (gitignored in dev; built by .github/workflows/)
#     distro/       ← proot-distro rootfs tars
#     agent/        ← native agent CLI binaries + glibc loader stubs
#     gpu/          ← mesa-vulkan-icd-freedreno, virglrenderer-android
#     wallpapers/   ← forge*.jpg, dark-*.jpg
#     launcher/     ← aether-desktop patch + icon
#     patches/      ← cline/kilocode/runner scripts if any
#
# Update: pushing a new commit triggers .github/workflows/release.yml which
# patches bin/ + distro/ + agent/ tars and publishes a release with
# assets — the same GH_REPO serve path for both Termux script and standalone.

set -Eeuo pipefail

GH_REPO="${GH_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && git -C . remote get-url origin 2>/dev/null || echo https://github.com/aether-org/termux-distro.git)}"
GH_BRANCH="${GH_BRANCH:-HEAD}"

# cache helpers
DL_DIR="$AE_HOME/dl"
mkdir -p "$DL_DIR" || install -d -m700 "$DL_DIR" 2>/dev/null || true

_resolve_gh_url() {  # $1: relative path → https://raw.githubusercontent.com/...
  printf "%s/raw/%s/%s" "$GH_REPO" "$GH_BRANCH" "$1"
}

_gh_fetch() {  # $1: local file $2: remote URL  →  curl -sSLo "$1" "$2"
  curl -sSLo "$1" "$2"
}

# ── public API ──────────────────────────────────────────────────────────────
# Signature: getter "subdir/item" "$AE_HOME/dest"

dl_gh() {  # item rel-path   local-dest
  _gh_fetch "$2" "$(_resolve_gh_url "$1")"
}

dl_gh_tree() {  # items...   ← pairs of "item rel-path" "$AE_HOME/dest" spread
  local pairs=("$@"); local i=0
  while [[ $i -lt ${#pairs[@]} ]]; do
    _gh_fetch "${pairs[i+1]}" "$(_resolve_gh_url "${pairs[i]}")"; ((i+=2)) || true
done
}

dl_refresh() {  # fetch latest from GH; returns date stamp in stdout
  GH_BRANCH=$(git -C "$(dirname -- "$GH_REPO")" rev-parse HEAD 2>/dev/null || echo HEAD)
  echo "refreshed $(date -u '+%Y-%m-%dT%H:%M:%SZ') at $GH_BRANCH"
}

# ── extraction / application ─────────────────────────────────────────────────
# tar / deb / bz / pdf etc. are extracted; scripts go to AE_HOME/bin/
# pprof the closest installed package, never shell-string the package name.

extract_tar() {  # local-file /dest/subdir
  local src="$1"; local dest="$2"; local base
  base=$(basename "$src" .tar.*); [[ "$base" == *.tar ]] && base=$(basename "$base" .tar)
  mkdir -p "$dest"; tar xf "$src" -C "$dest" --strip-components=1 "$base"/ 2>/dev/null
}

extract_bootstrap() {  # rootfs-tar → proot-distro install target
  local src="$1"; local tgt="$2"
  # proot-distro install --from-raw-tar automatically creates
  # $TMPDIR/.proot-distro-$$/  and unpacks there; we mirror that tree then
  # mv into $PRoot/. These scripts are leaf-only — we just pipe the tar
  # through proot-distro's own tar extraction, no intermediate store.
  if command -v proot-distro >/dev/null; then
    proot-distro install -y --from-raw-tar "$src" 2>/dev/null && echo "installed $tgt via proot-distro"
  else
    mkdir -p "$tgt"; extract_tar "$src" "$tgt"; echo "installed $tgt (raw)"
  fi
}

# ── agent CLI on-demand ─────────────────────────────────────────────────────
# These get cached in ~/.aether/agent/{native,distro}/ — only fetched once.

dl_agent_native() {  # name package-name npm/global-install-flag
  local name="$1" pkg="$2" npm_global="$3"
  local dir="$AE_HOME/agent/native/$name"; mkdir -p "$dir"
  if [[ -f "$dir/done" ]]; then ok "agent:$name cached ($(cat "$dir/done"))"; return; fi
  header "agent:$name"
  kv package "$pkg"; kv from "GH_REPO"
  case $npm_global in
    npm)    spinner "npm install -g $pkg" npm i -g "$pkg" && printf '%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ') by npm" > "$dir/done" ;;
    node)   spinner "install $pkg" npm i "$pkg"   && printf '%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ') by npm" > "$dir/done" ;;
    apt)    spinner "apt install $pkg" pkg install -y "$pkg" && printf '%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ') by pkg" > "$dir/done" ;;
    *)      _gh_fetch "$dir/$pkg" "$(_resolve_gh_url "installer/agent/$name/$pkg")" && printf '%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ') raw" > "$dir/done" ;;
  esac
  ok "agent:$name $(cat "$dir/done")"
}

dl_agent_glibc() {  # name pkg-dir   global-name (e.g. cline → @cline/cli, distro=debian)
  local name="$1" pkg_dir="$2" global="$3"; shift 3
  local dir="$AE_HOME/agent/glibc/$name"; mkdir -p "$dir"
  if [[ -f "$dir/done" ]]; then ok "agent:$name cached ($(cat "$dir/done"))"; return; fi
  header "agent:$name (glibc)"
  kv package_dir "$pkg_dir"; kv as "$global"
  run_in_distro "
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &&
    $APT update && $APT install -y nodejs build-essential &&
    su - aether -c 'npm config set prefix ~/.npm-global'
  "
  spinner "npm install" su - aether -c "cd $pkg_dir && npm install -g $global"
  mkdir -p "$AE_HOME/bin"
  grep -q ".aether/bin" ~/.bashrc || echo "export PATH=\"$AE_HOME/bin:\$PATH\"" >> ~/.bashrc
  printf '%s\n' "$name:glibc:$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$dir/done"
}
