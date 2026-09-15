# Lecture 1 Training — Full Progress Detail

Companion to [summary.md](./summary.md). This is the blow-by-blow log: exact commands, exact scores, exact evidence.

## Part 1 — Diagnostic loop (harness audit)

Tool: `node /Users/herohsu/Project/.agents/skills/harness-creator/scripts/validate-harness.mjs --target /Users/herohsu/Project/agent-skills-setup`

### Run 1 — baseline: 32/100, bottleneck `state`

```
instructions: 2/5 (2/5)
state: 1/5 (0/5)
verification: 3/5 (3/5)
scope: 1/5 (0/5)
lifecycle: 1/5 (1/5)
```

`state` failed all 5 checks: no `feature_list.json`, no `progress.md`, no handoff doc.

### Run 2 — added feature_list.json, progress.md, init.sh: 64/100

```
instructions: 2/5 (2/5)
state: 5/5 (5/5)
verification: 4/5 (4/5)
scope: 2/5 (2/5)
lifecycle: 3/5 (3/5)
```

`init.sh` created as a thin delegate to the existing `scripts/harness-verify.sh` (single source of truth for verification gates — no duplicated logic). `feature_list.json`/`progress.md` seeded with real completed/queued work, not placeholder features (deliberate — see summary.md).

### Run 3 — added AGENTS.md startup workflow + Definition of Done: 80/100

```
instructions: 5/5 (5/5)
state: 5/5 (5/5)
verification: 4/5 (4/5)
scope: 3/5 (3/5)
lifecycle: 3/5 (3/5)
```

### Run 4 — added End-of-Session section, renamed "## Boundaries" to "## Boundaries (scope)": 88/100

```
instructions: 5/5 (5/5)
state: 5/5 (5/5)
verification: 4/5 (4/5)
scope: 4/5 (4/5)
lifecycle: 4/5 (4/5)
```

### Remaining gaps, left unsatisfied deliberately

- `verification: 4/5` — checker looks for a literal `set -e` string. This repo's actual convention is `set -uo pipefail` (see `AGENTS.md`'s "Hooks block with exit 2" section for why `set -e` caused a real incident elsewhere). Not changed.
- `scope: 4/5` — checker looks for "one feature at a time" / "one-feature-at-a-time" phrasing. This repo is an ongoing multi-skill toolkit, not a single-feature build; adding that phrase would misdescribe how work actually happens. Not added.
- `lifecycle: 4/5` — checker looks for `session-handoff.md`. The skill's own `SKILL.md` calls this file "optional, for multi-session work"; most sessions here are single-sit edits and `progress.md` already covers restart continuity. Not added.

## Part 2 — feat-003: pre-existing mypy bug

Found via `bash init.sh` (first real run): `scripts/_settings_merge.py:85` — mypy error `Need type annotation for "changed"`. Confirmed pre-existing via `git log --oneline -1 -- scripts/_settings_merge.py` → `b420ae3`, well before this session, no uncommitted diff.

Fix: `changed: list[tuple[str, str, str]] = []` (matches the 3-tuples appended at line 109: `changed.append((event, stale, fresh))`).

Verification:
```
python3 -m mypy --config-file mypy.ini .
# Success: no issues found in 27 source files

bash init.sh
# All 7 gates pass (registry, types, tests, skill paths, cred backends, hook wiring, secret scan)
```

## Part 3 — Independent state-layer check (kiro-cli)

`kiro-cli chat --no-interactive --trust-tools=fs_read` succeeded. Given only `AGENTS.md` + `feature_list.json` + `progress.md`, no other context, it correctly reconstructed:
- feat-001/002 done (commit `5b023f3`), feat-003 open with the exact file/line
- Next steps: fix feat-003, rerun `init.sh`, update state files

First run also caught a real ambiguity: `progress.md`'s "Files Modified This Session" line labeled new files as "this session, harness-creator training exercise" — a phrase `AGENTS.md` never explained. Fixed the wording; re-ran the same check — ambiguity gone, confirmed by a follow-up `kiro-cli` query.

## Part 4 — Verification-gap exercise (5 tasks)

Dispatched via the `Agent` tool (isolated `worktree` per task) to Claude subagents. Each got a bounded, independently-verifiable task and was asked to self-report `DONE`/`NOT DONE`.

| # | Task | Self-report | My independent re-check | Match |
|---|---|---|---|---|
| 1 | README `@ref` doc consistency | DONE — fixed line 388 (missing `@ref` on `linear-claude-skill` example) | Diff confirmed real inconsistency + correct fix | ✅ |
| 2 | `validate-registry.sh` pin edge case | DONE — already correct, no fix needed | Re-ran the exact malformed test cases myself — same rejection, same exit 1 | ✅ |
| 3 | uninstall `@ref` bug check | DONE — no bug, no fix | Ran uninstall function myself in a clean subshell — correctly stripped, removed, exit 0 | ✅ |
| 4 | add uninstall `@ref` test coverage | DONE — 26/26 tests pass | Ran `test_registry_types.sh` myself in the worktree — 26/0 | ✅ |
| 5 | find untested skill script | DONE — coverage already 0 gaps, nothing added | Ran `coverage-check.sh` myself — identical output | ✅ |

Result: 5/5 claims held up under my own independent re-verification. But: 3 of 5 (#2, #3, #5) used "DONE" to mean "checked, found nothing to fix" — my task prompts never specified what DONE should mean in that case, so this ambiguity is a task-spec gap in the exercise design, not a failure by the agents.

Only tasks 1 and 4 produced real diffs (confirmed via the `Agent` tool's own worktree-cleanup signal: no `<worktree>` block returned for tasks 2/3/5, meaning zero file changes — independent of their self-reports).

## Part 5 — Same-model review blind spot, and the fix

Raised by the user: the "independent" re-verification in Part 4 was actually me (Claude) checking other Claude subagents. Same model family, same blind spots by construction — a real second opinion needs a genuinely different model. `codex-kiro` is that tool.

### The tool: `codex-kiro`

`type codex-kiro` revealed a shell alias (`~/.zshrc:65`):
```
alias codex-kiro='CODEX_HOME="$HOME/.codex-kiro" KIRO_PROXY_KEY=$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null) codex --profile kiro'
```
This points `CODEX_HOME` at a separate config dir with its own stored profile (`~/.codex-kiro/kiro.config.toml`: `model_provider = "kiro"`, `model = "gpt-5.6-sol"`), and routes through the locally running `kiro-gateway` Docker proxy (`http://localhost:7788/v1`, confirmed healthy via `curl http://127.0.0.1:7788/health`).

```bash
codex-kiro exec -s read-only -C /path/to/repo "..."
```
Confirmed working: model `gpt-5.6-sol`, provider `kiro`. First test — asked it to independently check the same README `@ref` line Task 1 fixed — it read the file itself and gave the same answer ("No, it does not include an `@ref` pin") that the Claude subagent found before fixing.

### The real finding: Test 24 was fine, Test 23 was not

Asked `codex-kiro` to review the two real diffs from Part 4 (Task 1's README fix, Task 4's new tests). Verdicts:
- README diff: **CORRECT** — "fixes the real inconsistency without introducing a factual error... minimal."
- Test diff: **INCORRECT**, with a specific reason:

> "Test 23 does not test `@ref` stripping: with `skills/alpha`, the uninstall name is always `basename "$skill_path"` (`alpha`), independent of `repo_ref`. It would still pass if stripping broke. It should use skill path `.` and expect removal of `multi-skills`. Test 24 follows existing patterns and would catch a real regression."

### Confirmed by mutation testing (not accepted on say-so)

```bash
# mutate uninstall_github_single_skill: use raw repo_ref instead of stripped repo
sed -i '' 's/local repo="\${repo_ref%@\*}"/local repo="$repo_ref"/' scripts/_lib.sh
bash scripts/tests/test_registry_types.sh | grep -E "Test 23|Results"
# PASS  uninstall_github_single_skill resolves name with @ref pin
# Results: 26 passed, 0 failed        <-- bug present, test still green
```
This confirmed `codex-kiro`'s finding exactly: the original Test 23 could not detect a broken `@ref` strip.

### Fix, and re-confirmation

Rewrote Test 23 to use `skill_path="."`, so the resolved name (`reponame = "${repo##*/}"`) actually depends on `repo` (the `@ref`-stripped value), instead of `basename(skill_path)` which never depended on it.

```bash
# same mutation, against the FIXED test:
bash scripts/tests/test_registry_types.sh | grep -E "Test 23|Results"
# FAIL  uninstall_github_single_skill resolves name with @ref pin: multi-skills still present in ...
# Results: 25 passed, 1 failed        <-- bug present, test now correctly catches it

# restored original code, re-ran:
# Results: 26 passed, 0 failed        <-- clean code, test passes
```

`codex-kiro` re-reviewed the fix independently (own sandbox, `workspace-write` mode so `mktemp` worked):
```
Results: 26 passed, 0 failed
FIXED — Using skill_path "." makes the name depend on the stripped repo name,
so broken @ref stripping would fail; the test suite reports 26 passed, 0 failed.
```

## Part 6 — Merge

Both real diffs (README `@ref` fix, corrected Test 23 + new Test 24) extracted from their isolated worktrees via `git diff HEAD -- <file> > patch` + `git apply`, applied to the main working tree. Worktrees confirmed byte-identical to main before removal (`diff <worktree-file> <main-file>` → identical), then `git worktree remove --force` for both.

Full suite after merge:
```
bash scripts/run-tests.sh --fast
# Results: 52 passed, 0 failed, 0 skipped, 0 code-bearing subcommands without tests
```

## What wasn't done from the lecture's full exercise set

- **Exercise 1** (explicit before/after with layer attribution) — effectively covered by the diagnostic-loop run above (32→88, each fix tied to a named layer), just not as a separate from-scratch exercise.
- **"Project 01: Prompt-Only vs. Rules-First"** (the linked companion project — build a minimal Electron app twice, once with no harness and once with the full harness, and compare completion/time/interventions/premature-success-claims) — judged not worth the setup cost (Node/Electron, two isolated dirs, a full double agent-build run, manual timing) for a lesson already demonstrated with real evidence on a repo that matters. Skipped by agreement with the user.
