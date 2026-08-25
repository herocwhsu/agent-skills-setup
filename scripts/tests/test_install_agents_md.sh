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

# --- Test 8b: --antigravity is the current name for the ~/.gemini/GEMINI.md target ---
# The flag was renamed when Gemini CLI became Antigravity; --gemini stays as an
# alias because older notes and the tests above still use it. The PATH is
# deliberately unchanged: Antigravity reads ~/.gemini/GEMINI.md.
TARGET_AGY="$TMPDIR/.gemini/GEMINI.md"
rm -f "$TARGET_AGY"
# `|| true`: on a regression the flag is unknown and the script exits 1,
# which would abort this runner under set -e and hide every later test.
# The real assertion is the file check below.
run_script --antigravity >/dev/null || true
if [[ -f "$TARGET_AGY" ]] && grep -qF "$BEGIN" "$TARGET_AGY" && grep -qF "Rule 1" "$TARGET_AGY"; then
  ok "--antigravity writes ~/.gemini/GEMINI.md"
else
  fail "--antigravity writes ~/.gemini/GEMINI.md" "$TARGET_AGY missing or wrong content"
fi

# --- Test 8c: --gemini alias still resolves to the same target ---
rm -f "$TARGET_AGY"
# `|| true`: on a regression the flag is unknown and the script exits 1,
# which would abort this runner under set -e and hide every later test.
# The real assertion is the file check below.
run_script --gemini >/dev/null || true
if [[ -f "$TARGET_AGY" ]] && grep -qF "$BEGIN" "$TARGET_AGY"; then
  ok "--gemini alias still works"
else
  fail "--gemini alias still works" "alias stopped writing $TARGET_AGY"
fi

# --- Test 9: Codex global AGENTS.md written ---
# Codex reads a global AGENTS.md from its config home ($CODEX_HOME, default
# ~/.codex). Confirmed from the 0.145.0 binary's own strings ("Failed to read
# global AGENTS.md instructions from") and the published AGENTS.md docs.
CODEX_TARGET="$TMPDIR/.codex/AGENTS.md"
rm -f "$CODEX_TARGET"
run_script --codex >/dev/null
if [[ -f "$CODEX_TARGET" ]] && grep -qF "$BEGIN" "$CODEX_TARGET" && grep -qF "Rule 1" "$CODEX_TARGET"; then
  ok "codex global AGENTS.md written"
else
  fail "codex global AGENTS.md written" "$CODEX_TARGET missing or wrong content"
fi

# --- Test 10: Codex block stripped on uninstall ---
run_script --uninstall --codex >/dev/null
if [[ ! -f "$CODEX_TARGET" ]] || ! grep -qF "$BEGIN" "$CODEX_TARGET" 2>/dev/null; then
  ok "codex block removed on uninstall"
else
  fail "codex block removed on uninstall" "block still present"
fi

# --- Test 11: AGENTS.override.md is never written ---
# At the global level Codex prefers AGENTS.override.md over AGENTS.md, so
# writing the override would shadow whatever the user put there.
run_script --codex >/dev/null
if [[ ! -e "$TMPDIR/.codex/AGENTS.override.md" ]]; then
  ok "codex override file left untouched"
else
  fail "codex override file left untouched" "installer wrote AGENTS.override.md"
fi

# --- Test 12: CODEX_HOME is honoured ---
ALT="$TMPDIR/alt-codex-home"
CODEX_HOME="$ALT" run_script --codex >/dev/null
if [[ -f "$ALT/AGENTS.md" ]] && grep -qF "$BEGIN" "$ALT/AGENTS.md"; then
  ok "CODEX_HOME redirects the codex target"
else
  fail "CODEX_HOME redirects the codex target" "$ALT/AGENTS.md not written"
fi

# --- Test 13: an agent-specific flag selects ONLY that agent ---
# The flags used to zero their two siblings by name, so each newly added agent
# was silently still enabled by every other flag.
rm -f "$TMPDIR/.claude/CLAUDE.md" "$TMPDIR/.gemini/GEMINI.md" "$CODEX_TARGET"
rm -f "$TMPDIR/.kiro/steering/engineering-rules.md"
run_script --claude >/dev/null
others=""
[[ -f "$TMPDIR/.gemini/GEMINI.md" ]] && others="$others gemini"
[[ -f "$CODEX_TARGET" ]] && others="$others codex"
[[ -f "$TMPDIR/.kiro/steering/engineering-rules.md" ]] && others="$others kiro"
if [[ -f "$TMPDIR/.claude/CLAUDE.md" && -z "$others" ]]; then
  ok "--claude writes claude only"
else
  fail "--claude writes claude only" "also wrote:$others"
fi

# --- Test 14: every agent in _lib.sh's AGENTS list has a target here ---
# The ratchet: codex was declared first-class in the installer (AGENTS list,
# ~/.codex/skills) while this script wrote only three files, so codex ran with
# no engineering rules at all. Derive the expectation from _lib.sh so the next
# agent added cannot repeat it.
LIB="$SCRIPT_DIR/_lib.sh"
INSTALLER="$SCRIPT_DIR/install-agents-md.sh"
missing=""
for agent in $(grep -oE '^AGENTS=\(.*\)' "$LIB" | tr -d '"' | sed 's/^AGENTS=(//; s/)$//'); do
  upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
  # Alternation-tolerant: an arm may list aliases (`--antigravity|--gemini)`) after
  # a rename. Still anchored at line start so a usage line in the header comment
  # cannot satisfy the ratchet.
  grep -qE "^[[:space:]]*(--[a-z-]+\|)*--$agent[|)]" "$INSTALLER" \
    || missing="$missing --$agent"
  # Whitespace-tolerant: the run() calls are column-aligned, so the guard
  # reads `$WANT_CODEX  -eq 1` with two spaces.
  grep -qE "WANT_${upper}[[:space:]]+-eq[[:space:]]+1" "$INSTALLER" \
    || missing="$missing WANT_$upper"
done
if [[ -z "$missing" ]]; then
  ok "every agent in AGENTS has a rules target"
else
  fail "every agent in AGENTS has a rules target" "absent:$missing"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
