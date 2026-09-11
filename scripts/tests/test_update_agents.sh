#!/usr/bin/env bash
# Tests for update-agents.sh and its wiring into install.sh / update.sh.
#
# Every case runs in REPORT mode against stub executables on a synthetic PATH.
# Two reasons: --apply would really upgrade the caller's CLIs, and asserting
# against whatever happens to be installed makes the result machine-dependent.
# The stubs also let the "not installed" branch be tested at all.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/update-agents.sh"
[[ -f "$SCRIPT" ]] || { echo "FAIL: missing $SCRIPT"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: $label"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    fails=$((fails + 1))
  fi
}
contains() {
  local label="$1" needle="$2" file="$3"
  if grep -q -- "$needle" "$file"; then
    echo "OK: $label"
  else
    echo "FAIL: $label (no match for '$needle')"
    sed 's/^/      /' "$file"
    fails=$((fails + 1))
  fi
}
absent() {
  local label="$1" needle="$2" file="$3"
  if grep -q -- "$needle" "$file"; then
    echo "FAIL: $label (unexpected '$needle')"
    sed 's/^/      /' "$file"
    fails=$((fails + 1))
  else
    echo "OK: $label"
  fi
}

# A PATH holding only the stubs named, so absence is testable.
BIN="$TMP/bin"
mkdir -p "$BIN"
stub() {
  printf '#!/usr/bin/env bash\necho "%s %s"\n' "$1" "$2" > "$BIN/$1"
  chmod +x "$BIN/$1"
}
stub claude   "9.9.9 (Claude Code)"
stub codex    "codex-cli 9.9.9"
stub hermes   "Hermes Agent v9.9.9"
stub agy      "9.9.9"
stub kiro-cli "kiro-cli 9.9.9"

# CLAUDECODE is set in the environment this suite normally runs in, so it is
# cleared explicitly. Left ambient, the not-skipped case would pass for the
# wrong reason on one machine and fail on another.
run() { env -u CLAUDECODE -u CLAUDE_CODE PATH="$BIN:/usr/bin:/bin" bash "$SCRIPT" "$@"; }
run_as_claude() { env CLAUDECODE=1 PATH="$BIN:/usr/bin:/bin" bash "$SCRIPT" "$@"; }

# --- report mode is the default and mutates nothing -------------------------
set +e
run > "$TMP/report.out" 2>&1; rc=$?
set -e
check "report mode exits 0" 0 "$rc"
contains "report mode says it is report only" "report only" "$TMP/report.out"
contains "report mode shows the command it would run" "would run: codex update" "$TMP/report.out"
absent  "report mode does not claim to have run anything" "running:" "$TMP/report.out"
contains "reports the resolved version" "9.9.9" "$TMP/report.out"

# --- kiro-cli is reported, never acted on ----------------------------------
contains "kiro-cli is flagged as not scriptable" "no scriptable update path" "$TMP/report.out"
absent  "kiro-cli gets no would-run line" "would run: kiro" "$TMP/report.out"

# --- the running agent is skipped unless asked -----------------------------
set +e
run_as_claude > "$TMP/self.out" 2>&1
set -e
contains "the running agent is skipped" "this agent is running this script" "$TMP/self.out"
absent  "and gets no would-run line" "would run: claude update" "$TMP/self.out"

set +e
run_as_claude --include-self > "$TMP/self2.out" 2>&1
set -e
contains "--include-self overrides the skip" "would run: claude update" "$TMP/self2.out"

# --- an absent agent is reported, not an error -----------------------------
rm "$BIN/hermes"
set +e
run > "$TMP/missing.out" 2>&1; rc=$?
set -e
check "an absent agent does not fail the run" 0 "$rc"
contains "an absent agent is reported" "hermes    not installed" "$TMP/missing.out"
stub hermes "Hermes Agent v9.9.9"

# --- filtering and argument handling ---------------------------------------
set +e
run --agent codex > "$TMP/one.out" 2>&1
set -e
contains "--agent selects that agent" "codex" "$TMP/one.out"
absent  "--agent excludes the others" "agy" "$TMP/one.out"

set +e
run --nonsense >/dev/null 2>&1; rc=$?
set -e
check "an unknown argument is rejected" 1 "$rc"

# --- the retired npm CLI must not come back -------------------------------
# @google/gemini-cli was removed in favour of agy. npm is deliberately unused:
# it resolves its global prefix from whichever version manager wins on PATH,
# which need not be the one holding the package, so `npm uninstall -g` once
# reported success having removed nothing.
# Comments are stripped first, the same way test_harness_verify.sh does it: the
# script's own header explains why npm is avoided and names the retired package,
# so grepping the raw file makes the prohibition fail on its own rationale.
code_only() { sed 's/[[:space:]]*#.*$//' "$1"; }
check "no npm dependency in update-agents.sh" "yes" \
  "$(code_only "$SCRIPT" | grep -qE '(^|[^[:alnum:]])npm ' && echo no || echo yes)"
check "the retired gemini-cli package is not referenced" "yes" \
  "$(code_only "$SCRIPT" | grep -q '@google/gemini-cli' && echo no || echo yes)"

# --- wiring: install.sh reports, update.sh applies ------------------------
check "install.sh does not apply by default" "yes" \
  "$(grep -qE 'update-agents\.sh" --apply \|\| true$' "$REPO_DIR/scripts/install.sh" \
     && grep -qE 'UPDATE_AGENTS -eq 1' "$REPO_DIR/scripts/install.sh" && echo yes || echo no)"
check "install.sh offers --update-agents" "yes" \
  "$(grep -q -- '--update-agents)' "$REPO_DIR/scripts/install.sh" && echo yes || echo no)"
# update.sh no longer calls update-agents.sh itself: it passes --update-agents
# through to install.sh, which owns the single agent step. Asserting the old
# direct call would test which script invokes which -- an implementation detail --
# rather than the contract, which is that update.sh applies by default.
check "update.sh defaults to applying agent updates" "yes" \
  "$(grep -qE '^UPDATE_AGENTS=1' "$REPO_DIR/scripts/update.sh" && echo yes || echo no)"
check "update.sh passes the flag through to install.sh" "yes" \
  "$(grep -q 'INSTALL_ARGS+=(--update-agents)' "$REPO_DIR/scripts/update.sh" && echo yes || echo no)"
check "update.sh has no second agent pass" 0 \
  "$(sed 's/[[:space:]]*#.*$//' "$REPO_DIR/scripts/update.sh" | grep -c 'update-agents.sh')"
check "update.sh offers --no-update-agents" "yes" \
  "$(grep -q -- '--no-update-agents)' "$REPO_DIR/scripts/update.sh" && echo yes || echo no)"
# A failed CLI update must not abort the skills install: set -e is on in both, so
# every invocation of the agent step needs the guard, not just the apply branch.
check "both agent-step branches tolerate failure" 2 \
  "$(grep -c 'update-agents.sh" \(--apply \)\?|| true' "$REPO_DIR/scripts/install.sh")"

# The flag is built into an array, not ${VAR:+...}: UPDATE_AGENTS holds 0 or 1 and
# 0 is non-empty, so :+ would expand the flag while it is switched off. Under
# set -u an empty array also needs the ${arr[@]+"${arr[@]}"} form or it aborts.
probe="$TMP/probe.sh"
cat > "$probe" <<'PROBE'
set -euo pipefail
UPDATE_AGENTS="$1"
INSTALL_ARGS=()
[[ -n "${AGENT_ARG:-}" ]] && INSTALL_ARGS+=(--agent "$AGENT_ARG")
[[ $UPDATE_AGENTS -eq 1 ]] && INSTALL_ARGS+=(--update-agents)
echo "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
PROBE
set +e
off=$(bash "$probe" 0 2>&1); off_rc=$?
on=$(bash "$probe" 1 2>&1); on_rc=$?
set -e
check "empty arg array survives set -u" 0 "$off_rc"
check "flag absent when disabled" "" "$off"
check "flag present when enabled" 0 "$on_rc"
check "flag is exactly the expected token" "--update-agents" "$on"

if [[ $fails -gt 0 ]]; then
  echo ""
  echo "$fails check(s) failed"
  exit 1
fi
echo ""
echo "all checks passed"
