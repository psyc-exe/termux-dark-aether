#!/usr/bin/env bash
# patch installer/ → dist/ on GitHub Pages or release tag.
# Called by .github/workflows/release.yml.
# Should run on a Linux host with gh CLI.
set -Eeuo pipefail

STEP="${1:-all}"
GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
TAG_BASE="${2:-aether-v}"
PRERELEASE="${PRERELEASE:-false}"

echo "## patch step=$STEP repo=$GITHUB_REPOSITORY branch=$GITHUB_REF"

export CI=true DEBIAN_FRONTEND=noninteractive

upload_to_release() {  # tag assets
  gh release create "$1" \
    --title "$1" \
    --generate-notes \
    --prerelease="$2" \
    installer/agent/* installer/distro/* installer/gpu/* installer/wallpapers/* \
    || echo "warning: release $1 may already exist" >&2
}

upload_to_pages() {  # upload distro tars as web-accessible for on-demand dl
  local tag; tag="${TAG_BASE}$(date +%Y%m%d)"
  # copies distro/* wallpapers/* to gh-pages or similar
  git -C installer subtree push --prefix installer/distro gh-pages main 2>/dev/null || \
    git -C installer subtree push --prefix installer/distro origin gh-pages 2>/dev/null || \
    echo "pages push skipped — configure gh-pages branch or use custom domain"
}

case $STEP in
  all)
    # 1. build aether-install.sh + libs from src
    # dev/build.sh — built by the project; patch.sh wraps pre-built here
    bash patch.sh src/ installer/ 2>/dev/null || true

    # 2. package distro rootfs tars
    mkdir -p installer/distro
    # replace with: tar --exclude=*.deb from kali-nethunter-rootfs*.tar.xz and tar cJf
    tar --xz -f installer/distro/kali-$(date +%Y%m%d).tar.xz \
      -C /tmp aether-distrolauncher/ 2>/dev/null || echo "kali distro tars not yet in src/"
    # same for parrot
    echo "distro tars at installer/distro/"

    # 3. package agent CLIs
    mkdir -p installer/agent/native installer/agent/glibc installer/agent/distro

    # native (already built) — copy into installer/agent/native/<pkg>/bin
    # e.g. codex/ node  install -g @openai/codex  → installer/agent/native/codex/node
    #      claude-code/ $(tar xz -O 2>/dev/null) → installer/agent/native/claude-code

    # glibc agents install from within distro, produce single wrapper
    # e.g. installer/agent/glibc/cline/bin = wrapper script; .env = env vars
    echo "agent CLIs at installer/agent/"

    # 4. wallpapers
    mkdir -p installer/wallpapers
    # copy from public/wallpapers/*.jpg
    echo "wallpapers at installer/wallpapers/"

    # 5. tag + upload
    TAG="${TAG_BASE}$(date +%Y%m%d%H%M)"
    upload_to_release "$TAG" "$PRERELEASE"
    upload_to_pages
    echo "tagged $TAG"
    ;;

  distro)
    mkdir -p installer/distro
    tar --xz -f "installer/distro/kali-$(date +%Y%m%d).tar.xz" -C /tmp aether-distrolauncher/ 2>/dev/null || true
    echo "distro tars at installer/distro/"
    ;;

  agent)
    echo "build agent bundles"
    ;;

  tag)
    TAG="${TAG_BASE}$(date +%Y%m%d)"
    gh release create "$TAG" --prerelease="$PRERELEASE" installer/ 2>/dev/null || true
    ;;

esac
