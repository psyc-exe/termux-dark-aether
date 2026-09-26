#!/usr/bin/env bash
# Run as the Jules Initial Setup command in its Ubuntu VM.
set -Eeuo pipefail

cd "$(dirname "$0")/.."
bash scripts/qa.sh
bash installer/tests/test_ui.sh
node --test scripts/jules-ci-triage.test.cjs
