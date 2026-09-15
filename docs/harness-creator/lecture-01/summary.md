# Harness Creator Training — Lecture 1: Why Capable Agents Still Fail

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-01-why-capable-agents-still-fail/
Skill used: `harness-creator` (`/Users/herohsu/Project/.agents/skills/harness-creator`)
Target repo: `agent-skills-setup` (this repo)
Date: 2026-09-14 / 2026-09-15

## Why this exercise

The lecture's core claim: unreliable agent behavior is usually a harness problem (instructions, state, verification, scope, lifecycle), not a model-capability problem. Rather than just read the lecture, we used `harness-creator`'s scripts to audit this real repo, found and fixed the actual bottleneck, and then ran a genuine verification-gap measurement — including catching a blind spot in our own review process along the way. Full step-by-step log: [progress-detail.md](./progress-detail.md).

## What we found

Auditing `agent-skills-setup` with `harness-creator`'s `validate-harness.mjs` scored it **32/100**, bottleneck **state** (0/5 raw). The repo had real tests, real hooks, real CI-style gates — but nothing telling a fresh agent session what was done, in progress, or next. That's exactly the lecture's "loss of state across sessions" failure layer, caught mechanically instead of by guessing.

## What we did

Ran the lecture's diagnostic loop for real, iterating four times:

| Run | Fix applied | Score |
|---|---|---|
| 1 | (baseline) | 32/100 |
| 2 | Added `feature_list.json`, `progress.md`, `init.sh` (real state, not placeholders) | 64/100 |
| 3 | Added startup workflow + Definition of Done to `AGENTS.md` | 80/100 |
| 4 | Added End-of-Session section, renamed a heading to surface an existing scope boundary | 88/100 |

Two checks were left deliberately unsatisfied rather than gamed: a literal `set -e` text match (this repo's actual convention is `set -uo pipefail`, for good reason — see `AGENTS.md`), and a "one feature at a time" phrase (this repo is an ongoing multi-skill toolkit, not a single-feature build, so that phrase would misdescribe it). The lecture's own warning — optimizing the benchmark instead of real reliability — applied directly here, and we didn't cross that line for two points.

## The verification-gap exercise

Per the lecture's exercise 2 (claimed-done vs. independently-verified), we dispatched 5 bounded cleanup tasks to isolated-worktree subagents and independently re-checked every claim ourselves. Result: **0/5 factual overstatement** — every claim held up. But the exercise surfaced a real gap in the exercise design itself: 3 of 5 agents used "DONE" ambiguously (to mean "checked, found nothing wrong" rather than "made a fix"), because the task prompts never defined what DONE should mean when nothing needs fixing. That's the lecture's own failure-layer-1 (unclear task specification) happening inside the harness we were building to avoid it.

## The bigger lesson: same-model review isn't independent review

The first verification pass used Claude subagents to both do the 5 tasks *and* cross-check them — same blind spots by construction, since it's the same model family reviewing itself. The tool for a genuine second opinion here is `codex-kiro` — a shell alias that points `CODEX_HOME` at a separate config and routes through the local `kiro-gateway` Docker proxy to a different model (`gpt-5.6-sol`), not another Claude instance. (Bare `codex`, without that alias, has no stored credentials on this machine and cannot authenticate at all — it is not a usable tool here, just the wrong entry point we ruled out on the way to `codex-kiro`.)

Once correctly invoked, `codex-kiro` reviewed the two real diffs from the verification-gap exercise and caught something the same-model review missed: one new test case exercised a code path whose outcome didn't depend on the feature it claimed to test — it would pass identically whether the feature worked or was broken. This wasn't accepted on the second opinion's word alone: we confirmed it via mutation testing (deliberately broke the code, watched the old test pass anyway, fixed the test, watched it correctly fail on the same mutation, then watched it pass again once the code was restored), then had `codex-kiro` re-confirm the fix independently. Full commands and output are in [progress-detail.md](./progress-detail.md).

The takeaway: "I asked another agent to check" is not evidence of independence if that agent shares the same training and failure modes. Real independent verification means a genuinely different model, and even then, claims from it are worth confirming mechanically rather than taking on faith — which is the same standard the lecture applies to the primary agent's own claims of "done."

## Outcome

- Diagnostic-loop score: 32 → 88/100, with the remaining 12 points understood and deliberately not chased.
- Real state layer now in place: `feature_list.json`, `progress.md`, `init.sh`, plus `AGENTS.md` sections routing to them.
- One pre-existing bug fixed for real (a stale mypy type-annotation gap), verified independently by a second agent (`kiro-cli`) reconstructing status from the state files alone with zero shared context.
- Two real fixes merged from the verification-gap exercise (a README consistency fix, and a test-coverage gap caught only by cross-model review + mutation testing).
- Full test suite green (52/52) throughout.

Not done from the lecture's full exercise set: the formal "Project 01: Prompt-Only vs. Rules-First" Electron-app companion project — judged not worth the setup cost, since its qualitative lesson (harness presence changes agent behavior) was already demonstrated with real evidence on a repo that matters, rather than a throwaway toy app.
