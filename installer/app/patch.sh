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

case $STEP in
  all)
    # Package only artifacts that this repository can actually build.
    # If only the tracked installer source is ready, publish that as an honestly named installer archive with a checksum.

    mkdir -p dist

    # 1. Package the installer/ directory
    tar -czf dist/aether-installer.tar.gz installer/
    echo "packaged dist/aether-installer.tar.gz"

    # 2. Generate SHA256 checksum
    cd dist
    sha256sum aether-installer.tar.gz > aether-installer.tar.gz.sha256
    echo "generated checksum"
    ;;
esac
