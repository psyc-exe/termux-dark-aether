# Aether Update System — GitHub-based, branch-triggered
#
# Workflow (build machine, triggered by push to main):
#   1. .github/workflows/update.yml
#   2. Builds aether-install.sh + all lib/*.sh scripts
#   3. Packs distro tars (Kali/Parrot rootfs) into installer/distro/
#   4. Patches agent native/glibc binaries into installer/agent/
#   5. Uploads assets → release tag aether-vN.M.P
#
# On Android:
#   aether-install.sh --resume calls repo.sh::dl_refresh to fetch latest GH_REPO HEAD.
#   If the version tag in ~/.aether/version differs from GH, runs self-update
#   (backups current bin/lib/, installs fresh ones, preserves state/agent.env).
#
# GitHub repo mirror shape:
#   installer/
#     aether-install.sh          ← built from aether-install.sh
#     lib/ui.sh lib/exec.sh ...  ← built from installer/lib/*.sh
#     bin/                       ← fully built scripts (gitignored dev-only)
#     distro/kali-nethunter-*.tar.xz  ← rootfs archives
#     distro/parrot-rootfs-*.tar.xz
#     agent/native/codex
#     agent/native/claude
#     agent/glibc/cline @cline/cli
#     agent/glibc/kilocode @kilocode/cli
#     launcher/aether-desktop.patch
#
# GitHub branch state:
#   HEAD                      ← always: latest stable + zip of all assets
#   aether-v1.0.0  (release)  ← tagged by update.yml
#   aether-v1.0.1  etc.

set -Eeuo pipefail

_AE_CHECKOUT="${_AE_CHECKOUT:-installer}"
GH="${GH_REPO:-$(cd "$(dirname -- "${BASH_SOURCE[0]}")/../.." && git -C . remote get-url origin 2>/dev/null || echo https://github.com/aether-org/termux-distro.git)}"
BRANCH="${GH_BRANCH:-HEAD}"

_VERSION_FILE="$AE_HOME/version"
_SOURCES_FILE="$AE_HOME/.gh-sources"

# ── git helpers ─────────────────────────────────────────────────────────────

gh_fetch() { curl -sSLo "$1" "$(_resolve "$2")"; }
gh_fetch_cached() {
  local url _c; url=$1; _c="${GH_CACHE:-$TMPDIR/aether-gh-cache}"
  mkdir -p "$_c"; local hash; hash=$(echo "$url" | sha256sum | cut -c1-16)
  [[ -f "$_c/$hash" && ! $url =~ "refresh" ]] && { cat "$_c/$hash"; return; }
  gh_fetch "$_c/$hash" "$url"; cat "$_c/$hash"
}

_resolve() { printf "%s/raw/%s/%s" "$GH" "$BRANCH" "$1"; }

dl_refresh() {  # fetch latest from HEAD; return timestamp
  BRANCH="$(git -C "$(dirname -- "$GH")" rev-parse HEAD 2>/dev/null || echo HEAD)"
  echo "refreshed $(date -u '+%Y-%m-%dT%H:%M:%SZ') at $BRANCH"
}

# ── version tracking ────────────────────────────────────────────────────────

check_updates() {
  local rem local; local rem HEAD; rem=$(gh_fetch_cached "HEAD/ref-$(date +%s)" 2>/dev/null | grep -m1 version 2>/dev/null || echo "")
  local rem_time rem_commit; rem_time=$(echo "$rem" | grep -oP 'refreshed \S+' | cut -d" " -f2)
  local local_time local_commit; local_time=$(cat "$_VERSION_FILE" 2>/dev/null || echo "")
  local local_commit; local_commit=$(head -3 "$_SOURCES_FILE" 2>/dev/null | tail -1 | cut -d" " -f1 || echo "")

  if [[ -z "$rem_time" ]]; then return 0; fi  # no network
  if [[ "$rem_commit" == "$local_commit" ]]; then return 0; fi
  return 1  # update needed
}

apply_update() {  # 1. backup current 2. install fresh scripts 3. restart
  local backup_dir="$AE_HOME/.update-$(date +%s)"; mkdir -p "$backup_dir"
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$backup_dir/applied"
  # backup old scripts
  cp -a "$installer_dir/bin"* "$backup_dir/" 2>/dev/null || true
  cp -a "$installer_dir/lib"* "$backup_dir/" 2>/dev/null || true
  cp -a "$_VERSION_FILE" "$backup_dir/" 2>/dev/null || true

  # install fresh from HEAD
  echo "$_TUPLE_VERSION" > "$_VERSION_FILE"
  echo "$_TUPLE_SOURCES" > "$_SOURCES_FILE"
  curl -sSLo "$installer_dir/bin/aether-install.sh" "$(_resolve "${_AE_CHECKOUT}/aether-install.sh")"
  chmod +x "$installer_dir/bin/aether-install.sh"

  # libs: list them explicitly so we don't risk copying the whole GH_REPO
  local libs; libs="ui.sh exec.sh toolchain.sh gpu.sh desktop.sh"
  for l in $libs; do
    curl -sSLo "$installer_dir/lib/$l" "$(_resolve "${_AE_CHECKOUT}/lib/$l")"
    chmod +x "$installer_dir/lib/$l"
  done

  ok "updated to $_TUPLE_VERSION at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  ok "bin/lib backed up in $backup_dir"
  exec "$installer_dir/bin/aether-install.sh" --resume
}
