#!/usr/bin/env bash
# test_coverage_check.sh — tests for scripts/coverage-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/coverage-check.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

SKILLS="$TMPDIR/skills"

# --- fixture tree ------------------------------------------------------------
# A subcommand that ships executable code but nothing exercises it: a real gap.
mkdir -p "$SKILLS/grp/coded/lib"
echo "# impl" > "$SKILLS/grp/coded/IMPL.md"
echo "echo hi" > "$SKILLS/grp/coded/lib/run.sh"

# Ships code and owns a test: covered.
mkdir -p "$SKILLS/grp/coded-ok/lib" "$SKILLS/grp/coded-ok/tests"
echo "# impl" > "$SKILLS/grp/coded-ok/IMPL.md"
echo "echo hi" > "$SKILLS/grp/coded-ok/lib/run.sh"
echo "true" > "$SKILLS/grp/coded-ok/tests/test_coded_ok.sh"

# Prompt-only, but a group-level test asserts against its IMPL.md: covered.
mkdir -p "$SKILLS/grp/prompt-ref" "$SKILLS/grp/tests"
echo "# impl" > "$SKILLS/grp/prompt-ref/IMPL.md"
cat > "$SKILLS/grp/tests/test_grp.sh" <<'EOF'
grep -q something "$REPO_DIR/skills/grp/prompt-ref/IMPL.md"
EOF

# Prompt-only with nothing asserting it. Not a test gap — there is no code to run.
mkdir -p "$SKILLS/grp/prompt-bare"
echo "# impl" > "$SKILLS/grp/prompt-bare/IMPL.md"

# A group root's own SKILL.md must never be mistaken for a subcommand.
echo "# group" > "$SKILLS/grp/SKILL.md"

out=$(bash "$SCRIPT" "$SKILLS" 2>&1) || true

# An absence assertion is vacuously true when the script fails to run at all,
# so every one of them is gated on the summary line actually being produced.
ran=0
grep -q "^Coverage:" <<<"$out" && ran=1

absent() {
  local name="$1" pattern="$2"
  if [[ $ran -eq 0 ]]; then
    bad "$name" "script produced no summary line:
$out"
  elif grep -q "$pattern" <<<"$out"; then
    bad "$name" "appeared in output:
$out"
  else
    ok "$name"
  fi
}

# --- tests -------------------------------------------------------------------
if grep -q "UNTESTED.*grp/coded/IMPL.md" <<<"$out"; then
  ok "code-bearing subcommand with no test is reported"
else
  bad "code-bearing subcommand with no test is reported" "missing from output:
$out"
fi

absent "code-bearing subcommand owning a test is not reported" "coded-ok"
absent "prompt-only subcommand asserted by a group test is not reported" "prompt-ref"
absent "prompt-only subcommand is not reported as UNTESTED" "UNTESTED.*prompt-bare"

if grep -qE "^Coverage: 1 code-bearing" <<<"$out"; then
  ok "summary counts only code-bearing gaps"
else
  bad "summary counts only code-bearing gaps" "got:
$out"
fi

# Prompt-only subcommands are still surfaced, just not as test gaps.
if grep -qE "2 prompt-only" <<<"$out"; then
  ok "summary reports prompt-only subcommands separately"
else
  bad "summary reports prompt-only subcommands separately" "got:
$out"
fi

echo ""
echo "test_coverage_check: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
