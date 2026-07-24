# Local Pre-Commit Shell Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `PreToolUse` hook in this repo's `.claude/` that blocks an agent `git commit` when any staged `*.sh` file fails `bash -n` or `shellcheck --severity=error`, checking the staged blob rather than the working tree.

**Architecture:** One bash hook script reads Claude Code's PreToolUse JSON from stdin, ignores non-`git commit` Bash commands, lists staged `*.sh`, and validates each via `git show :FILE`. Exit 0 allows; exit 2 blocks (message to stderr). Registered in a new `.claude/settings.json`.

**Tech Stack:** Bash (`set -euo pipefail`), git, `shellcheck`, `python3` for JSON parsing (matches the existing `hooks/common/sh-check.sh` idiom), the repo's plain-bash test runner.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-precommit-sh-gate-design.md`.
- Scope: dogfood in `agent-skills-setup` only; not wired into `install.sh` for other repos.
- Check the **staged blob** (`git show :FILE`), never the working-tree file.
- `bash -n` always blocks; `shellcheck --severity=error` blocks only when shellcheck is present.
- File scope: `*.sh` only.
- Block = exit 2 with a stderr message naming offenders; allow = exit 0.
- Must not false-block non-commit Bash (`git status`, `echo "commit"`) or `git commit --dry-run` / `--help`.
- Tests: plain bash, no bats; `mktemp -d` sandboxes with a throwaway git repo; feed synthetic stdin JSON; PASS/FAIL counters; file exits non-zero if any fail. Discovered by `scripts/run-tests.sh` via `skills`/`scripts` globs — this hook's test lives under `.claude/hooks/tests/`, so Task 3 also registers it with the runner.

---

### Task 1: The gate script

**Files:**
- Create: `.claude/hooks/precommit-sh-check.sh`
- Test: `.claude/hooks/tests/test_precommit_sh_check.sh`

**Interfaces:**
- Consumes: PreToolUse JSON on stdin with `.tool_input.command`.
- Produces: an executable hook. Exit 0 = allow, exit 2 = block. No other output on the allow path.

- [ ] **Step 1: Write the failing tests**

Create `.claude/hooks/tests/test_precommit_sh_check.sh`:

```bash
#!/usr/bin/env bash
# Tests for precommit-sh-check.sh — no bats.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/precommit-sh-check.sh"
PASS=0
FAIL=0

# Run the hook with a synthetic command in a throwaway git repo.
# Args: <name> <expected_exit> <commit_command> <staged_file_content>
run_case() {
  local name="$1" expected="$2" cmd="$3" content="${4-}"
  local tmp; tmp=$(mktemp -d)
  local code=0
  ( cd "$tmp"
    git init -q
    git config user.email t@t; git config user.name t
    if [[ -n "$content" ]]; then
      printf '%s' "$content" > script.sh
      git add script.sh
    fi
    printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
      | bash "$HOOK" >/dev/null 2>&1
  ) || code=$?
  if [[ "$code" -eq "$expected" ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected exit $expected, got $code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmp"
}

run_case "clean staged sh allows"        0 'git commit -m x' $'#!/usr/bin/env bash\necho ok\n'
run_case "syntax error blocks"           2 'git commit -m x' $'#!/usr/bin/env bash\nif then fi\n'
run_case "non-commit bash allows"        0 'git status'      $'#!/usr/bin/env bash\nif then fi\n'
run_case "dry-run allows"                0 'git commit --dry-run' $'#!/usr/bin/env bash\nif then fi\n'
run_case "no staged sh allows"           0 'git commit -m x' ''

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/hooks/tests/test_precommit_sh_check.sh`
Expected: FAILs / errors because `precommit-sh-check.sh` does not exist yet.

- [ ] **Step 3: Write the hook**

Create `.claude/hooks/precommit-sh-check.sh`:

```bash
#!/usr/bin/env bash
# precommit-sh-check.sh — PreToolUse(Bash): block `git commit` when a staged
# *.sh file fails bash -n or shellcheck --severity=error. Checks the STAGED
# blob (git show :FILE), not the working tree. Exit 2 blocks; exit 0 allows.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print(''); sys.exit(0)
print(d.get('tool_input',{}).get('command',''))
" 2>/dev/null)

# Only gate real \`git commit\`. Skip dry-run/help and non-commit commands.
case "$cmd" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac
case "$cmd" in
  *"--dry-run"*|*"--help"*) exit 0 ;;
esac
# Guard against 'commit' only inside a message: require the token 'commit'
# to follow 'git' as a subcommand.
echo "$cmd" | grep -Eq '(^|[[:space:]])git[[:space:]]+([^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)' || exit 0

# Must be in a git repo.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Portable (bash 3.2 / macOS /bin/bash has no `mapfile`).
staged=()
while IFS= read -r f; do
  [[ -n "$f" ]] && staged+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$' || true)
[[ ${#staged[@]} -eq 0 ]] && exit 0

have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

fail=0
msgs=""
for f in "${staged[@]}"; do
  blob=$(git show ":$f" 2>/dev/null) || continue
  if ! printf '%s' "$blob" | bash -n - 2>/tmp/.sc.$$; then
    fail=1; msgs+="  $f: bash syntax error"$'\n'
  elif [[ "$have_shellcheck" -eq 1 ]]; then
    if ! printf '%s' "$blob" | shellcheck --severity=error - >/tmp/.sc.$$ 2>&1; then
      fail=1; msgs+="  $f: shellcheck error"$'\n'
    fi
  fi
done
rm -f /tmp/.sc.$$

if [[ "$fail" -eq 1 ]]; then
  {
    echo "Blocked: staged shell scripts have errors (fix before committing):"
    printf '%s' "$msgs"
    [[ "$have_shellcheck" -eq 0 ]] && echo "  (shellcheck not installed — only syntax checked)"
  } >&2
  exit 2
fi
exit 0
```

Make it executable:

```bash
chmod +x .claude/hooks/precommit-sh-check.sh
```

- [ ] **Step 4: Run to verify pass**

Run: `bash .claude/hooks/tests/test_precommit_sh_check.sh`
Expected: all five cases PASS; final `0 failed`.

- [ ] **Step 5: Add a shellcheck-error case (only meaningful if shellcheck present)**

Append before the results block in the test file:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  # SC2086-class issues are warnings; use an error-level construct.
  run_case "shellcheck error blocks" 2 'git commit -m x' $'#!/usr/bin/env bash\necho "$(\n'
fi
```

Note: the unterminated `$(` above is a syntax error too, guaranteeing a block; if you want a pure-shellcheck-error case, substitute a construct shellcheck rates at error severity in your version and confirm with `shellcheck --severity=error`.

- [ ] **Step 6: Run + shellcheck the hook + commit**

```bash
shellcheck --severity=warning .claude/hooks/precommit-sh-check.sh
bash .claude/hooks/tests/test_precommit_sh_check.sh
git add .claude/hooks/precommit-sh-check.sh .claude/hooks/tests/test_precommit_sh_check.sh
git commit -m "feat: add pre-commit shell gate hook"
```

---

### Task 2: Register the hook in `.claude/settings.json`

**Files:**
- Create: `.claude/settings.json`
- Test: `.claude/hooks/tests/test_precommit_sh_check.sh` (add a JSON-validity assertion)

**Interfaces:**
- Consumes: the hook path from Task 1.
- Produces: a valid settings file registering a PreToolUse Bash hook.

- [ ] **Step 1: Write the failing test**

Append to the test file before the results block:

```bash
settings_valid_test() {
  local name="$1"
  local settings
  settings="$(cd "$(dirname "$0")/../.." && pwd)/settings.json"
  if [[ -f "$settings" ]] \
     && python3 -c "import json,sys; d=json.load(open('$settings')); h=d['hooks']['PreToolUse']; assert any('precommit-sh-check.sh' in json.dumps(x) for x in h)" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (settings missing or hook not registered)"; FAIL=$((FAIL+1))
  fi
}
settings_valid_test "settings.json registers the PreToolUse hook"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash .claude/hooks/tests/test_precommit_sh_check.sh`
Expected: `settings.json registers...` FAILs (file absent).

- [ ] **Step 3: Create `.claude/settings.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/precommit-sh-check.sh\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash .claude/hooks/tests/test_precommit_sh_check.sh`
Expected: `settings.json registers...` PASS; `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json .claude/hooks/tests/test_precommit_sh_check.sh
git commit -m "feat: register pre-commit shell gate as PreToolUse hook"
```

---

### Task 3: Wire the hook test into the repo test runner

**Files:**
- Modify: `scripts/run-tests.sh` (discover `.claude/hooks/tests/test_*.sh`)
- Test: run `scripts/run-tests.sh --fast` and confirm the new test is listed.

**Interfaces:**
- Consumes: the test from Tasks 1–2.
- Produces: the hook test runs as part of `run-tests.sh`.

- [ ] **Step 1: Inspect current discovery**

Run: `grep -n "hooks/tests\|scripts/tests\|Skill tests" scripts/run-tests.sh`
Expected: no `.claude/hooks/tests` discovery yet.

- [ ] **Step 2: Add discovery for the hook test**

In `scripts/run-tests.sh`, in the "Script tests" section (after the `scripts/tests` loop), add:

```bash
for f in "$REPO_DIR/.claude/hooks/tests"/test_*.sh; do
  [[ -f "$f" ]] || continue
  run_bash "$f"
done
```

- [ ] **Step 3: Run the full suite**

Run: `bash scripts/run-tests.sh --fast`
Expected: output includes `PASS  …/.claude/hooks/tests/test_precommit_sh_check.sh`; overall run passes.

- [ ] **Step 4: Commit**

```bash
git add scripts/run-tests.sh
git commit -m "test: run pre-commit shell gate test in run-tests.sh"
```

---

### Task 4: Live verification

**Files:** none (verification only).

- [ ] **Step 1: Prove it blocks a broken staged script**

```bash
printf '#!/usr/bin/env bash\nif then fi\n' > /tmp/broken.sh
cp /tmp/broken.sh ./_gate_probe.sh
git add _gate_probe.sh
echo '{"tool_input":{"command":"git commit -m test"}}' | bash .claude/hooks/precommit-sh-check.sh; echo "exit=$?"
git restore --staged _gate_probe.sh; rm -f _gate_probe.sh
```

Expected: stderr names `_gate_probe.sh: bash syntax error`, `exit=2`.

- [ ] **Step 2: Prove it allows a clean commit path**

```bash
echo '{"tool_input":{"command":"git status"}}' | bash .claude/hooks/precommit-sh-check.sh; echo "exit=$?"
```

Expected: `exit=0`, no output.

- [ ] **Step 3: Record outcome**

If either behaves wrong, STOP and debug with `superpowers:systematic-debugging`; do not mark complete.

---

## Self-Review

**Spec coverage:** PreToolUse Bash hook (T2); staged-blob check via `git show :FILE` (T1); `bash -n` always + shellcheck-when-present (T1); `*.sh` scope (T1); commit-detection excluding dry-run/help/message-only (T1); exit-2 block with named offenders (T1); dogfood-only, no install.sh change (whole plan); test wired into runner (T3); live verify (T4). All spec sections mapped.

**Placeholder scan:** none — concrete code and commands throughout. The shellcheck-pure-error case in T1/Step 5 is explicitly noted as version-dependent with a verification instruction, not a placeholder.

**Type consistency:** hook path `.claude/hooks/precommit-sh-check.sh`, settings key `hooks.PreToolUse[].matcher = "Bash"`, and the `run_case` helper signature are used consistently across tasks.
