#!/usr/bin/env bash
# test_install_agents_md.sh — tests for scripts/install-agents-md.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/install-agents-md.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

ok()   { echo "  PASS  $1"; pass=$((pass + 1)); }
fail() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

BEGIN="<!-- BEGIN agent-skills-setup:engineering-rules -->"
END="<!-- END agent-skills-setup:engineering-rules -->"

# Create a fake source file
SOURCE="$TMPDIR/engineering-rules.md"
echo "# Rules" > "$SOURCE"
echo "Rule 1" >> "$SOURCE"

# Override paths by patching env — we redirect HOME to TMPDIR
export HOME="$TMPDIR"
mkdir -p "$TMPDIR/.claude" "$TMPDIR/.gemini" "$TMPDIR/.kiro/steering"

# Helper: run the script with our fake source
run_script() {
  REPO_DIR="$TMPDIR" bash "$SCRIPT" "$@" 2>&1
}

# Patch the script to use our fake source by creating a fake agents/engineering-rules.md
mkdir -p "$TMPDIR/agents"
cp "$SOURCE" "$TMPDIR/agents/engineering-rules.md"

# --- Test 1: write block to new file (claude) ---
TARGET="$TMPDIR/.claude/CLAUDE.md"
rm -f "$TARGET"
run_script --claude >/dev/null
if grep -qF "$BEGIN" "$TARGET" && grep -qF "$END" "$TARGET" && grep -qF "Rule 1" "$TARGET"; then
  ok "write block to new file"
else
  fail "write block to new file" "expected block in $TARGET"
fi

# --- Test 2: idempotent refresh (claude) ---
before=$(cat "$TARGET")
run_script --claude >/dev/null
after=$(cat "$TARGET")
count=$(grep -c "$BEGIN" "$TARGET")
if [[ "$count" -eq 1 ]]; then
  ok "idempotent refresh — block not duplicated"
else
  fail "idempotent refresh" "found $count BEGIN markers, expected 1"
fi

# --- Test 3: updated content is written on refresh ---
echo "Rule 2" >> "$TMPDIR/agents/engineering-rules.md"
run_script --claude >/dev/null
if grep -qF "Rule 2" "$TARGET"; then
  ok "refresh writes updated content"
else
  fail "refresh writes updated content" "Rule 2 not found after refresh"
fi

# --- Test 4: write block appended to existing file with content ---
TARGET_GEMINI="$TMPDIR/.gemini/GEMINI.md"
echo "# Existing content" > "$TARGET_GEMINI"
run_script --gemini >/dev/null
if grep -qF "# Existing content" "$TARGET_GEMINI" && grep -qF "$BEGIN" "$TARGET_GEMINI"; then
  ok "block appended to existing file without overwriting"
else
  fail "block appended to existing file" "existing content missing or block absent"
fi

# --- Test 5: strip block from file ---
run_script --uninstall --claude >/dev/null
if [[ ! -f "$TARGET" ]] || ! grep -qF "$BEGIN" "$TARGET" 2>/dev/null; then
  ok "strip block removes block from file"
else
  fail "strip block" "block still present after uninstall"
fi

# --- Test 6: strip block from file that has other content ---
TARGET_GEMINI2="$TMPDIR/.gemini/GEMINI.md"
# Re-install then uninstall
run_script --gemini >/dev/null
run_script --uninstall --gemini >/dev/null
if [[ -f "$TARGET_GEMINI2" ]] && grep -qF "# Existing content" "$TARGET_GEMINI2" && ! grep -qF "$BEGIN" "$TARGET_GEMINI2"; then
  ok "strip block preserves surrounding content"
else
  fail "strip block preserves surrounding content" "file missing, existing content gone, or block still present"
fi

# --- Test 7: Kiro steering file written ---
KIRO_TARGET="$TMPDIR/.kiro/steering/engineering-rules.md"
run_script --kiro >/dev/null
if [[ -f "$KIRO_TARGET" ]] && grep -qF "Rule 1" "$KIRO_TARGET"; then
  ok "kiro steering file written"
else
  fail "kiro steering file written" "$KIRO_TARGET missing or wrong content"
fi

# --- Test 8: Kiro steering file removed on uninstall ---
run_script --uninstall --kiro >/dev/null
if [[ ! -f "$KIRO_TARGET" ]]; then
  ok "kiro steering file removed on uninstall"
else
  fail "kiro steering file removed on uninstall" "file still present"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
