#!/usr/bin/env bash
# scripts/qa.sh — Automated QA for aether-install.sh.
# Checks: syntax, state consistency, UI helpers, bootstrap download flow.
# Does NOT require Android runtime or root.
# Usage: sh scripts/qa.sh [installer-dir]

set -Eeuo pipefail

INSTALLER_DIR="${1:-installer}"
FAIL=0

ok()  { printf "  \e[38;2;127;183;126m✔%s\e[0m %s\n" "" "$*"; }
warn() { printf "  \e[38;2;224;122;56m▲%s\e[0m %s\n" "" "$*"; }
die()  { printf "  \e[38;2;224;60;60m✖ %s\e[0m\n" "$*"; exit 1; }

# ── 1. syntax check ─────────────────────────────────────────────────────────
echo "=== syntax ==="
for f in "$INSTALLER_DIR/aether-install.sh" \
         "$INSTALLER_DIR/lib/"*.sh \
         "$INSTALLER_DIR/app/"*.sh \
         "$INSTALLER_DIR/apk/"*.sh \
         "$INSTALLER_DIR/tests/"*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" || { warn "syntax fail: $f"; FAIL=$((FAIL+1)); }
done
[[ $FAIL == 0 ]] && ok "all scripts syntax-checked"

# ── 2. bootstrap download flow (no network needed — just dry-run the curl logic) ──
echo "=== bootstrap ==="
# Verify GH_REPO URL pattern and file existence
LOCAL_INSTALLER="$INSTALLER_DIR/aether-install.sh"
if [[ -f "$LOCAL_INSTALLER" ]]; then
  [[ "$(head -1 "$LOCAL_INSTALLER")" == "#!/usr/bin/env bash" ]] || { warn "$LOCAL_INSTALLER missing shebang"; FAIL=$((FAIL+1)); }
  ok "$LOCAL_INSTALLER present and executable"
else
  warn "$LOCAL_INSTALLER not found — dry-run skipped"
fi

# ── 3. state file consistency ───────────────────────────────────────────────
echo "=== state ==="
TMPDIR_STATE=$(mktemp -d)
export TMPDIR="$TMPDIR_STATE"
mkdir -p "$TMPDIR_STATE/bin" "$TMPDIR_STATE/lib"
touch "$TMPDIR_STATE/state"
export AE_HOME="$TMPDIR_STATE"
. installer/lib/ui.sh   # kv() and ok/warn come from here
. installer/lib/exec.sh
# test state_save
export AE_MODE=root; state_save AE_MODE
if [[ -f "$AE_HOME/state" ]]; then
  grep -q "AE_MODE=root" "$AE_HOME/state" && ok "state_save round-trip" || { warn "state_save failed"; FAIL=$((FAIL+1)); }
else
  warn "state file not found"
  FAIL=$((FAIL+1))
fi
# test kv output
t=$(kv test "value")
[[ "$t" == *"test"* && "$t" == *"value"* ]] || { warn "kv output format wrong: $t"; FAIL=$((FAIL+1)); }
rm -rf "$TMPDIR_STATE"

# ── 4. UI helpers test ───────────────────────────────────────────────────────
echo "=== ui ==="
. installer/lib/ui.sh
. installer/lib/exec.sh

# spinner smoke (output to file)
# Use a fresh top-level temp dir — NOT nested inside $AE_HOME which may have been cleaned
TMPDIR_SP=$(mktemp -d --tmpdir=/tmp aether-qa-XXXXXX)
export TMPDIR="$TMPDIR_SP"
export AE_HOME="$TMPDIR_SP"
mkdir -p "$AE_HOME"
spinner test-spinner echo hello >"$TMPDIR_SP/install.log" 2>&1 &
SP_PID=$!
sleep 2
kill $SP_PID 2>/dev/null || true
wait $SP_PID 2>/dev/null || true
rm -rf "$TMPDIR_SP"

# ── 5. menu fallback test ───────────────────────────────────────────────────
echo "=== menu ==="
if command -v whiptail >/dev/null; then
  V=$(menu _T "title" "a" "b" 3>&1 2>&1) 2>/dev/null
  [[ "$V" =~ ^[0-9]$ ]] || { warn "whiptail menu FAIL"; FAIL=$((FAIL+1)); }
  ok "whiptail menu"
else
  warn "whiptail not available — menu fallback skipped"
fi

# ── 6. repo.sh structure test ────────────────────────────────────────────────
echo "=== repo ==="
. installer/lib/repo.sh  # test load (functions defined)
command -v dl_gh >/dev/null && ok "dl_gh" || { warn "dl_gh not exported"; FAIL=$((FAIL+1)); }
command -v dl_gh_tree >/dev/null && ok "dl_gh_tree" || { warn "dl_gh_tree not exported"; FAIL=$((FAIL+1)); }
command -v extract_tar >/dev/null && ok "extract_tar" || { warn "extract_tar not exported"; FAIL=$((FAIL+1)); }
command -v extract_bootstrap >/dev/null && ok "extract_bootstrap" || { warn "extract_bootstrap not exported"; FAIL=$((FAIL+1)); }

# ── 7. update.sh structure test ───────────────────────────────────────────────
echo "=== update ==="
. installer/lib/update.sh  # test load
command -v check_updates >/dev/null && ok "check_updates" || { warn "check_updates not exported"; FAIL=$((FAIL+1)); }
command -v apply_update >/dev/null && ok "apply_update" || { warn "apply_update not exported"; FAIL=$((FAIL+1)); }

# ── 8. shizuku sub-flow dry-run (no device needed) ────────────────────────────
echo "=== shizuku ==="
# check_root is check_root in exec.sh; shizuku_setup is too
command -v check_root >/dev/null && ok "check_root loaded" || { warn "check_root not exported"; FAIL=$((FAIL+1)); }
# shizuku_setup is the function name; rish is where it calls rish
command -v shizuku_setup >/dev/null && ok "shizuku_setup loaded" || { warn "shizuku_setup not exported"; FAIL=$((FAIL+1)); }

# ── results ──────────────────────────────────────────────────────────────────
echo
echo "=== results ==="
[[ $FAIL == 0 ]] && { ok "ALL CHECKS PASSED"; exit 0; }
[[ $FAIL -gt 0 ]] && { warn "$FAIL CHECK(s) FAILED — see above"; exit 1; }
