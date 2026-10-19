# Telemetry gaps and state overhead (2026-10-19)

Source: the owner asked, after the two-layer harness work, what got better or worse
and what to improve, judged from the logs. The analysis (this session, 2026-10-19)
found the logs could not answer "how did this task go?" and that state bookkeeping
took 61 of 131 commits in week 42. The owner approved every item below ("do all")
and reviews when all are done.

## What exists (kept)

Run records (`run_telemetry.py`, `feature_run_record.py`, spec in
`docs/stories/run-telemetry/spec.md`) already tie a feature to its session by commit
window, with tokens, subagents, outside-agent attempts and gate runs in that window.
Its rules stay: a missing value is never 0, and nothing is counted from message text.

## Changes

| # | Change | Where |
|---|---|---|
| T1 | Gate-run rows keep a failed gate's full name (`runtime drift` was split into `runtime` and `drift`), list the failing test files of the tests gate, and carry the session id when the caller has one. | `scripts/harness-verify.sh` |
| T2 | Verify-gate rows (hangar, atelier) carry the session id. | `templates/hooks/common/verify-gate.sh` |
| T3 | Outside-agent attempt rows carry `repo` and the session id. | `scripts/outside_agent.py` |
| T4 | Run records count failed tool calls (`is_error`) and permission denials (`toolDenialKind`), both structured fields; rows from another session are left out of a window when both sides name a session. | `scripts/run_telemetry.py` |
| T5 | The weekly trend shows, per repo, fix commits and how many changed code that another commit changed in the 48 h before (rework). | `scripts/repo_trend.py` |
| T6 | A second trace snapshot of the same commit and agent replaces the first instead of adding a row. | `scripts/trace_evaluation.py` |
| T7 | End of Session says the work and its completion go in one commit; PROGRESS archives finished history so the state layer is under its 6,000-token limit again; the stale "owner action left" note is corrected. | `AGENTS.md`, `PROGRESS.md` |
| T8 | Claude Code keeps transcripts 90 days (default 30), so trends survive a month. | `~/.claude/settings.json` (this machine) |
| T9 | Review rule: a change of many tasks to hooks, gates or install scripts is also reviewed per group of tasks, not only at the end. | `agents/engineering-rules.md` |
| T10 | hangar: a live (Tier 3) change is one checked script covering every cluster that runs the service, with a check after each change and a tested rollback. | hangar `AGENTS.md` |

Session id: `CLAUDE_CODE_SESSION_ID` when set (Claude Code). agy and codex expose no
such variable, so their rows have none and fall back to the time window.

## Not changed

- Cost stays missing: `cost-state` totals fall from about $200 a week to $3 from
  week 41, which looks like a format change, so they are not trusted.
- Two outside-agent row shapes (attempt and success) stay; run records read both.
- Rework is a weekly trend, not a run-record field: at completion time the later
  fixes do not exist yet.
- The 48 h rework heuristic overcounts in large shared files (`_lib.sh`); it is a
  trend, not a per-commit verdict.

## Acceptance

Each change has a test that failed first. All 11 gates pass. Real runs: a gate run
row names `runtime drift` whole and the session; a run record of this session shows
tool errors and denials; `repo_trend.py` prints the rework column for all three repos.
