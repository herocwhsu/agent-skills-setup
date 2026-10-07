# Harness Creator Training — Lecture 6: Why Initialization Needs Its Own Phase

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-06-why-initialization-needs-its-own-phase/
Target repo: `agent-skills-setup`, plus throwaway repos in `/tmp/l6`
Date: 2026-10-06. Full log: [progress-detail.md](./progress-detail.md). Raw agent reports: [raw/](./raw/).

## What the lecture claims

Initialization and implementation are different work. A session that mixes them builds
visible features and leaves the infrastructure unverified. The output of initialization is:
an environment that runs, at least one passing test, a startup readiness doc (run, test,
state), an ordered task list with acceptance criteria, and a clean commit. The metrics are
time to first passing test and how often later sessions succeed without unwritten
knowledge.

## What we measured

| Exercise | Setup | Result |
|---|---|---|
| 1. Readiness cold start | Fresh clone, a Claude subagent and agy, repo files only | Both reached green, neither found the dev setup in the docs |
| 3. Acceptance checklist | The lecture's 5 items, run against this repo | 2 pass, 2 partial, 1 fail |
| Template check | `init-repo.sh python-api` on an empty repo | 0 of 5 initialization outputs |
| 2. Comparison (reduced) | wordstat CLI, mixed vs init-first, 2 sessions each, 20-call budget | Null: both 8/8 on a hidden test |

### Exercise 1: readiness cold start

| | Claude subagent | agy |
|---|---|---|
| Tool calls | 11 | 36 (inflated, see confound) |
| First passing test | call 5, full green call 7 | call 33 |
| Wall time | ~25 min | ~25 min |

Both models found:

1. **No dev-setup step.** `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`
   exists only in error strings (`scripts/run-tests.sh:23,30`, `.claude/hooks/types-guard.sh`).
   On a fresh clone, the first `./init.sh` fails the types gate (`anthropic` missing). Both
   agents reconstructed the command from the error text.
2. **README Quick Start is end-user install** (`install.sh`, `setup-credentials.sh`,
   `setup-host.sh`), with no contributor path.
3. **The next task is an unordered list** (`PROGRESS.md` "What's Next", 5 items).

Claude also found:

4. `PROGRESS.md:6` says "passes all 9 gates". There are 10, and they fail on a fresh clone.
   (Stale by 2026-10-07: `8fbe558` had already reworded that line to "all gates".)
5. `./init.sh` takes about 5 minutes and `run-tests.sh --fast` 4–5. No doc says so, so a
   newcomer can't tell a slow run from a hang.
6. Without `.venv`, the tests gate silently falls back to ambient `python3`, which
   `docs/architecture.md:118` prohibits. Tests passed while types failed on the same run.
7. Runtime drift SKIPs until `install.sh` has run. The Definition of Done doesn't say whether a
   SKIP counts as done.

Confound: agy's "`.agents/hooks.json` deleted" finding was ours. We removed that file in the
agy clone so its 900 s Stop hook would not hang the headless run. That broke 4 hook tests and
accounts for most of agy's 36 calls.

### Exercise 3: initialization acceptance checklist

| Item | Result |
|---|---|
| Setup works from scratch | Partial: only after the undocumented venv step |
| At least one passing test | Pass: 62/62 |
| Fresh session answers "how to run" and "how to test" | Test yes, dev setup no (both models) |
| Task list with ≥3 tasks and acceptance criteria | Fail: `feature_list.json` is 36/36 done, has no criteria field, and future work is prose |
| Everything committed | Pass |

Template check: `init-repo.sh` copied 10 hook scripts and wrote a `settings.json` with deny
rules only. It wired no hooks (that is a manual "step 2"), and produced no `AGENTS.md`,
`PROGRESS.md`, task list, `init.sh` or test. harness-creator's `create-harness.mjs` generates
those files, so this repo's template currently splits initialization across two tools and a
doc (`docs/harness-adoption.md`).

### Exercise 2: comparison (reduced)

A small Python CLI with 5 planned features. Session 2 got a feature that was not on the plan
(`--min-len`). A hidden 8-check acceptance script graded both repos.

| | A: mixed | B: init-only session 1 |
|---|---|---|
| Session 1 calls / first test | 9 / call 6 | 5 / call 2 |
| Session 2 orientation calls | 1 | 2 |
| Total calls | 13 | 15 |
| Hidden acceptance | 8/8 | 8/8 |

Null result. The project fit in one context, so the budget never bit and the init phase cost
about 15% more calls for no measurable gain. Both session-2 agents guessed the same
semantics for the new feature. B also found its harness had no rule for adding a feature
that was not on the list.

## Why dev setup belongs in `AGENTS.md`

`AGENTS.md` is the only file every agent is guaranteed to load, and its Startup Workflow
already tells the agent to run `./init.sh` at step 4. That step fails on a fresh clone
because the venv it needs is created nowhere in the docs. The routed instruction leads
straight to a failure, and the only fix is in an error string. Both models paid for that
by reverse-engineering the command. The lecture's readiness criterion is "the project can
start", and the router is where that has to be true. A README section helps humans, but
agents follow `AGENTS.md`.

The cheaper alternative is to make `init.sh` build the venv itself when it is missing, so the
step needs no doc. That keeps `AGENTS.md` short (97 of 100 lines) and removes the gap
instead of documenting it. Either fix closes finding 1. Self-healing also closes finding 6
(silent ambient fallback) if the gates then refuse to run without `.venv`.

## Follow-up fixes (2026-10-07, feat-038)

Each finding was re-checked against the repo before fixing. On a clean clone, `types-guard.sh`
still failed with `Cannot find implementation or library stub for module named "anthropic"`.

- **Finding 1 and 6 (no venv step, silent ambient fallback):** `init.sh` now builds `.venv` from
  `requirements-dev.txt` when the directory is missing, and removes it again if the build
  fails. The fallback in `run-tests.sh` and `types-guard.sh` stays, because CI runs without a
  venv; `docs/architecture.md` now says so. Test: `scripts/tests/test_init_sh.sh` (failed first).
- **Finding 2 (README is end-user only):** README Quick Start points contributors at
  `AGENTS.md` and `./init.sh`.
- **Finding 5 and 7 (runtime, SKIP):** `AGENTS.md` states the ~5 minute run and that a SKIP is
  not a pass.
- **Finding 3 (unordered next task):** Left as is. An order would be invented, not derived.
- **Acceptance item 4 (no criteria field):** Left as is. Adding a field to 37 finished entries
  would be made-up content.
- **Port flake:** Confirmed, not just read: `limactl` (49906) and `wsagent` (49706) were
  listening inside the test's 49000-49999 range and a bind on them fails. All 11 port
  picks in the four confluence-tree mock-server tests now take a kernel-assigned port
  (`tests/free_port.sh`).

## What this does not show

- The findings not listed under "Follow-up fixes" stand.
- Exercise 2 ran 2 sessions, not 4, on a toy project. It cannot confirm or refute the
  lecture's claim for multi-session work.
- Wall times are rough: they include tool overhead and the parallel load of 4 agents.
- The confluence-tree port-collision explanation (test 5 picks `49000 + RANDOM % 1000`,
  inside macOS's dynamic range) came from a subagent's reading of the code. It was not
  reproduced.

## Lessons

1. A startup instruction that fails on a fresh clone is worse than no instruction: it spends
   the agent's first minutes on recovery. Test the router's steps from a clean clone.
2. Error strings are not documentation. If the only place a setup command lives is a failure
   message, a fresh session finds it only by failing first.
3. "Every feature done" is not a task list. With nothing pending and no acceptance criteria,
   the next session works from prose.
4. The value of init-first scales with project size. On work that fits in one context it is
   overhead, so judge it on multi-session work only.
