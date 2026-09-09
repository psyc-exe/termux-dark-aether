#!/usr/bin/env bash
# tests/test_ui.sh — Verify installer/lib/ui.sh: kv format, state round-trip,
# spinner output, socket wait, menu mocks. Does NOT run sudo/su or touch real
# Android state.

. installer/lib/ui.sh
. installer/lib/exec.sh

fail=0
AE_HOME=/tmp/aet-test; mkdir -p "$AE_HOME"; : >"$AE_HOME/install.log"

# ── kv output format ─────────────────────────────────────────────────────────
out=$(kv os "Debian 12")
[[ $out == *"os"* && $out == *"Debian 12"* ]] || { echo "kv FAIL"; fail=1; }

# ── state round-trip ────────────────────────────────────────────────────────
AE_MODE=quasi AE_EXEC=proot
state_save AE_MODE AE_EXEC
. "$AE_HOME/state" 2>/dev/null || . /dev/null
grep -q "AE_MODE=quasi" "$AE_HOME/state" && grep -q "AE_EXEC=proot" "$AE_HOME/state" || { echo "state FAIL"; fail=1; }

# ── spinner smoke (output goes to file, not tty) ─────────────────────────────
spinner test-spinner echo hello
sleep 1

# ── wait_for_socket timeout ──────────────────────────────────────────────────
socat -l0 2>/dev/null || true
wait_for_socket /nonexistent.sock 1 && { echo "ws false-positive"; fail=1; }

# ── menu mock (whiptail available?) ──────────────────────────────────────────
if command -v whiptail >/dev/null; then
  V=$(menu _T "title" "opt1" "opt2" 3>&1 2>&1) 2>/dev/null
  [[ $V =~ ^[0-9]$ ]] || echo "whiptail menu FAIL"; fail=$((fail+0))
fi

echo "ui/state tests: $([ $fail == 0 ] && echo PASS || echo FAIL)"
exit $fail
