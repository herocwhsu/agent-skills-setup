# Harness benchmark: definition

Purpose: answer whether a harness change made the next task of the same difficulty faster, cheaper or more reliable. This file defines the benchmark. It is not run yet; running it needs agent sessions, which cost tokens and time. The telemetry collector (`scripts/run_telemetry.py`) supplies the numbers.

`scripts/harness_benchmark.py` is a different tool: it times shell commands (gates) in milliseconds. It is not reused here.

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

Report medians with the min and max, never a single run. Call a difference real only if the ranges of the two versions do not overlap. With fewer than 5 runs per cell, the report says "insufficient runs" and shows no verdict. A cell with any `missing` metric shows `n/a` for it, not a number computed from the remaining runs.

## Known limits

- Model and gateway behavior can change between days. Every run records the model name (from the transcript), and runs with different models are never compared.
- Token usage is only measurable for Claude Code sessions. Tasks run through Codex, Kiro or agy have no usable token source today.
- Human intervention is a proxy and is marked `estimated`.
- Cost in USD is not reported (see the spec).

## Not done yet

The fixture repo, the five prompts, the hidden acceptance tests and the runner that executes a task and collects its run record. Building them is the next piece of work, after the telemetry in this story has been in use long enough to show whether its numbers are stable.
