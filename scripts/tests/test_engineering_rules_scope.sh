#!/usr/bin/env bash
# Tests that agents/engineering-rules.md stays host-general.
#
# The file is installed into Claude Code, Antigravity, Codex, and Kiro, and loaded
# on every task. Host-specific paths and slash commands are dead text on three of
# those hosts, and task-specific procedure belongs in a skill that loads on demand.
# The global file keeps only a trigger, so the trigger must name a skill that is
# installed by default -- a local-optional one may be absent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RULES="$REPO_DIR/agents/engineering-rules.md"
REGISTRY="$REPO_DIR/registry.txt"

pass=0
fail=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

hits=$(grep -nE '(~|<repo>)?/?\.claude/' "$RULES" || true)
[[ -z "$hits" ]] \
  && ok "no Claude-only paths" \
  || bad "no Claude-only paths" "$hits"

hits=$(grep -nE '`/[a-z][a-z:-]*' "$RULES" || true)
[[ -z "$hits" ]] \
  && ok "no slash commands (they exist only on some hosts)" \
  || bad "no slash commands (they exist only on some hosts)" "$hits"

grep -qF 'spec-workflow' "$RULES" \
  && ok "production work is routed to the spec-workflow skill" \
  || bad "production work is routed to the spec-workflow skill" "no trigger in $RULES"

grep -qE '^local[[:space:]]+spec-workflow[[:space:]]*$' "$REGISTRY" \
  && ok "spec-workflow is a required (local) skill" \
  || bad "spec-workflow is a required (local) skill" "missing or optional in registry.txt"

[[ -f "$REPO_DIR/skills/spec-workflow/SKILL.md" ]] \
  && ok "spec-workflow SKILL.md exists" \
  || bad "spec-workflow SKILL.md exists" "absent"

grep -q 'Production Spec-Gated Workflow' "$RULES" \
  && bad "gate procedure lives in the skill, not the global file" "still in $RULES" \
  || ok "gate procedure lives in the skill, not the global file"

grep -q 'Prompt polish' "$RULES" \
  && bad "prompt polish is host-specific (AGY only), must not be in global engineering-rules.md" "found in $RULES" \
  || ok "prompt polish absent from global engineering-rules.md (Claude/Codex/others clean)"

[[ -f "$REPO_DIR/agents/antigravity-rules.md" ]] && grep -q 'Prompt polish' "$REPO_DIR/agents/antigravity-rules.md" \
  && ok "antigravity-rules.md exists and contains AGY prompt polish rule" \
  || bad "antigravity-rules.md exists and contains AGY prompt polish rule" "missing or incomplete"

grep -q 'outside-agent.sh run --purpose review' "$RULES" \
  && ok "outside-agent rule present" || bad "outside-agent rule present" "missing"
grep -q 'not independent' "$RULES" \
  && ok "outside-agent rule names exit 3" || bad "outside-agent rule names exit 3" "missing"

echo ""
echo "test_engineering_rules_scope: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
