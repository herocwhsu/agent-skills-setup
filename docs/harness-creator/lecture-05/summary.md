# Harness Creator Training — Lecture 5: Why Long-Running Tasks Lose Continuity

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-05-why-long-running-tasks-lose-continuity/
Target repos: `agent-skills-setup`, `hangar`, `atelier`
Date: 2026-10-04. Full log: [progress-detail.md](./progress-detail.md).

## What the lecture claims

Context is finite, so long work crosses sessions and every crossing loses the "why". State
files (`PROGRESS.md`, a decision log, commits as checkpoints, clock-in/clock-out routines)
let a fresh session rebuild fast. The metric is rebuild cost; the enemy is drift between what
the files say and what the repo is.

## What we measured

Three fresh subagents (one per repo) and agy rebuilt state from repo files alone, answering
seven questions (active work, HEAD vs recorded state, verify command, next task, blockers,
binding owner decisions, contradictions). Rebuild cost was already low: 4 to 9 tool calls,
because `AGENTS.md` routes to short files. What failed was **freshness**:

| Repo | Defect the cold start found |
|---|---|
| agent-skills-setup | Commit `83748b3` (another session) recorded nowhere; five stacked `Active Feature` lines in `PROGRESS.md`; a stale Lecture 4 paragraph in "Current State" |
| atelier | `feature_list.json` and `PROGRESS.md` still said the harness was unmerged, weeks after it merged; README said grouped Renovate PRs need a manual merge, `renovate.json` says they automerge |
| hangar | "In flight" listed only finished work; "Next" was an empty template; "Last updated" a day behind |
| all three | The owner's auto-merge decision lived only in an out-of-repo memory file; agents could not find it |

agy found the same defects as the Claude subagents, so the baseline is not one model's blind
spot. Both models failed the same question: where the binding owner decisions are.

## What we fixed

- atelier (`5cf3595`): harness marked done with evidence, stale PROGRESS text removed, README
  corrected, auto-merge decision recorded in `PROGRESS.md` ("Standing decisions") and `AGENTS.md`.
- hangar (`218a7ff`): TLS item closed, decision recorded, "Next" filled.
- agent-skills-setup (`25eed39`): `feat-030` added, stacked lines collapsed, decision noted.
- Second pass: `PROGRESS.md` 370 → 248 lines: 5 lines of stacked state and the Lecture 4
  paragraph removed (its content is in `lecture-04/summary.md`), then two frozen sections
  (124 lines) moved verbatim to `docs/progress-archive.md`; hangar `docs/architecture.md` Grafana SSO line corrected.

## Result

Re-running agy on the fixed state: every answer matched the files, the auto-merge decision was
quoted with its revisit condition, and the contradictions it had flagged were gone. agy
reported that the project `AGENTS.md` was already in its context before it read any file
(self-report in all three real-repo runs; not independently observed).

## What this does not show

- Rebuild **time** was never measured, only tool calls. The lecture's "under 3 minutes" is untested.
- Exercise 2 (design a four-field handoff template) was skipped: the existing `PROGRESS.md`
  sections already carry those fields. Exercise 3 (three strategies over five sessions) was not run.
- agy rated every answer 5/5, including ones with real ambiguity; its confidence is not a signal.
  Its guess that `83748b3` contradicted `feat-019` was wrong (different credential: Claude Code's
  keychain entry, not Gemini's).
- The post-fix runs were not blind to the answer: the fixed `AGENTS.md` states the decision.
- `PROGRESS.md` "What's Done" is still ~140 lines of history; the trim was only the two
  frozen sections.
- No staleness guard was built. A gate comparing `feature_list.json` with git would also gate
  automerged PRs in hangar and atelier, where a flaky check is costly. Open design question.
- hangar `docs/architecture.md` still says WARP remote access was "not re-verified after the
  top1 retirement"; nothing in the repo says it was.

## Lessons

1. State files rot at session boundaries, not through slow rebuilds. The failure was a closing
   update nobody made, and a commit made in a parallel session.
2. A decision that is not in the repo does not exist for the agent, even if the assistant
   remembers it. It belongs in `AGENTS.md`/`PROGRESS.md`.
3. Prepend-only logs corrupt "current state": five sessions each added a line instead of
   replacing one. Current state must be overwritten, history appended elsewhere.
4. Ask a cold-start question set after any structural change; it finds contradictions that
   linting cannot.
