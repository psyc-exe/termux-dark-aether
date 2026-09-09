#!/usr/bin/env bash
# app/update.sh — CLI entry for update.sh
# Usage: aether-update [--force] [--check-only]

set -Eeuo pipefail
installer_dir="${installer_dir:-$HOME/.aether}"

force=""
check_only=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) force="yes"; shift ;;
    --check-only) check_only=true; shift ;;
    *) echo "unknown: $1"; shift ;;
  esac
done

exec "$installer_dir/lib/update.sh" "$installer_dir" "$force" "$check_only"
