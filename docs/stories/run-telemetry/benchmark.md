# Harness benchmark: definition

Purpose: answer whether a harness change made the next task of the same difficulty faster, cheaper or more reliable. This file defines the benchmark and how to run it. Running it needs agent sessions, which cost tokens and time; only one smoke run per task has been done. The telemetry collector (`scripts/run_telemetry.py`) supplies the numbers.

The older `scripts/harness_benchmark.py`, which timed shell commands (gates) in milliseconds, was deleted by feat-103 (2026-10-23); `harness-verify.sh` records gate times itself.

## Five fixed tasks

Each task is a frozen starting commit plus a prompt and acceptance checks that a script can evaluate. A task counts as passed only if every check passes.

| ID | Kind | Prompt (frozen text) | Acceptance check |
|---|---|---|---|
| B1 | Simple bug fix | A function with a known one-line defect and a failing test already in the fixture repo. "Make the failing test pass." | The named test passes; no other file changed. |
| B2 | Multi-file feature | A small spec adding one option across a CLI, its config parser and docs. | A hidden acceptance test passes; the visible tests pass; `harness-verify.sh` passes in the fixture. |
| B3 | Review needing several reviewers | A diff with three planted defects of different kinds (logic, test gap, portability). | The review output names all three defects; scored by a fixed checklist, not by a model. |
| B4 | Outside-agent task | "Get an independent review of this diff from another model family." | `outside-agent-runs.jsonl` has an attempt row with `independent: true` and the review output is non-empty. |
| B5 | State layer / context | "Record the finished feature in the state files and keep the state layer within budget." | `state-layer-guard.sh` passes and `trace_evaluation.py --check-thresholds` is OK. |

The fixture repo is a small throwaway repository copied from the frozen commit for each run, so runs cannot see each other's results.

## What is compared

Per task, per harness version, with at least 5 runs each because the same model on the same task varies between runs:

| Metric | Source | Note |
|---|---|---|
| Output tokens (parent, and subagents separately) | run record | Deduplicated; context size is not a cost figure. |
| Wall time and active turn time | run record | Both reported; wall includes idle time. |
| First-pass success rate | acceptance check on the first attempt, before any retry | A run that needed a retry counts as a first-pass failure. |
| Gate failures before the final state | `harness-verify --report` per run | Missing if no report was produced. |
| Human interventions | count of user messages after the prompt | The only automatic proxy available; a corrected prompt and a plain "continue" both count, so it overstates. Labeled `estimated`. |
| Subagent count and unattributed subagents | run record | |

A harness version is a commit. The comparison is "commit A versus commit B, same task, same model".

## Comparison rule

Report medians with the min and max, never a single run. First-pass success is compared the same way, as a range of per-run 0 and 1 values, so with 5 runs per version it only counts as a real difference when every run of one version passed and every run of the other failed; a rate such as 5 of 5 against 4 of 5 is reported as no real difference. Call a difference real only if the ranges of the two versions do not overlap. With fewer than 5 runs per cell, the report says "insufficient runs" and shows no verdict. A cell with any `missing` metric shows `n/a` for it, not a number computed from the remaining runs.

## Known limits

- Model and gateway behavior can change between days. Every run records the model name (from the transcript), and runs with different models are never compared.
- Token usage is only measurable for Claude Code sessions. Tasks run through Codex, Kiro or agy have no usable token source today.
- Human intervention is a proxy and is marked `estimated`.
- Cost in USD is not reported (see the spec).

## How to run it

```
python3 scripts/telemetry_benchmark.py run --task B1 --runs 5 --model sonnet
python3 scripts/telemetry_benchmark.py compare
```

`run` copies the task's fixture into a fresh temporary git repo, runs `claude -p` there with the frozen prompt and a narrow `--allowedTools` list, scores the result with scripted checks, and writes `docs/telemetry/benchmark/<task>-<session>.json` with the run record from `run_telemetry.py` embedded. `compare` groups results by task, harness commit, model and suite hash, and prints a verdict per metric only between groups that share model and suite hash.

Files: `benchmarks/telemetry/suite.json` (prompts, fixture and tools per task), `fixtures/` (what the agent sees), `hidden/` (tests the agent never sees, copied in only after the run), `reference/` (a known-good solution per task, used by the tests to prove the checks accept a correct answer and reject the untouched fixture). `tests/test_telemetry_benchmark.py` covers the scoring and the comparison rule with a fake agent, so no tokens are spent.

## Scripted checks

| Task | Checks (all must pass) |
|---|---|
| B1 | the visible tests are unchanged; only `stats.py` changed; the hidden copy of the tests passes |
| B2 | the original tests, run from a pristine copy, still pass (the agent may add tests, but cannot weaken the old ones); the hidden `--shout` tests pass (flag, config in any letter case, false, existing behavior); the README mentions `--shout` and `shout =` |
| B3 | the review names the off-by-one in `paginate.py`, the missing last-page test, and the non-portable `mapfile`, each matched by keywords near the file or function name; no file changed |
| B4 | `outside-agent-runs.jsonl` has a row from this run with `independent: true` and `exit_code: 0`; the review text is non-empty; no file changed |
| B5 | `state_layer_check` accepts the files; `feature_list.json` is at most 250 lines and the state layer at most 6,000 tokens; `feat-900` is done with evidence; all 41 original features are still present (an archive reference counts); `PROGRESS.md` mentions `feat-900` and changed |

B3 keyword matching is a limit, and review found it cannot be made exact: it works per sentence and per clause (a hedge such as "works fine for full pages but drops the last item" still counts), ignores negated clauses ("did not find an off-by-one") and keyword lists, and does not let one subject's keywords pair with another's. It still can be fooled by a review that states a defect in unusual words, or phrases a non-finding in an unexpected way. It is deterministic and the same for every harness version, which is what a comparison needs; do not use it to judge one review in isolation. The reference review and 20 tests pin the vocabulary it accepts and the evasions it rejects.

## Known limits of this implementation

- Human interventions are recorded as measured 0 because `claude -p` takes no further input. The proxy in the table above does not apply to headless runs.
- Gate failures are missing: the fixture repos have no harness gates. Gate results for the harness repo itself come from `harness-verify.sh --report`.
- `first_pass` equals `passed`: a headless run has no retry, so there is no separate retry count.
- B4 is skipped when `~/.agent-skills-setup/outside-agent.sh` is not installed, and its outcome depends on another vendor's service being reachable. A B4 failure with a rate-limit attempt row is an environment failure, not a harness regression; read the attempt row before comparing.
- The run uses the user's own Claude settings and hooks, so a change to `~/.claude` also changes the result. The harness commit in the record is the repo's commit, marked `-dirty` when the tree has uncommitted changes; do not compare dirty runs.
- Running costs tokens: five tasks times five runs times two harness versions is 50 sessions.
