# Lecture 4 Exercise 3 — Lost in the Middle, Measured

Date: 2026-09-28. Format: `docs/experiment-template.md`.

## 1. Problem

The first Lecture 4 pass flagged every `AGENTS.md` rule at 25–75% depth as
"DANGER (Middle)" on the strength of Liu et al. (2023). That paper measured
retrieval from contexts of thousands of tokens; `AGENTS.md` is ~1.3k tokens. If
position does not matter at this size, reordering rules is wasted effort and the
"danger" labels mislead. If it does, rules must be moved or guarded.

## 2. Current Baseline

No measurement existed — `split_simulation.py` only computes where each rule sits.

## 3. Hypothesis

We believe that moving a rule from the top or bottom of `AGENTS.md` to the middle
will lower compliance, because recall is weaker mid-context.

Key assumption: the agent reads the whole file (the file tells it to), so any
difference comes from attention, not from not reading.

## 4. Metrics

Lagging: compliance rate per position (rule followed / runs).
Leading: 15 runs, one hypothesis, mechanical scoring (no judgment calls).

## 5. Expected Outcome

For a ~100-line file, near-identical compliance at all three positions.
Surprise: a middle-position rate clearly below top/bottom.

## 6. Success Criteria

- Every run produced `scripts/count-skills.sh` (else the run is invalid, not a miss).
- Compliance scored by a script, not by reading replies.

## 7. Abandon Criteria

- More than 2 invalid runs in any condition.

## 8. Smallest Test

Rule under test — made up, so it cannot be inferred from the code, and checkable
by one line comparison:

```markdown
## Script Ownership Header

Every new `*.sh` file must have `# owner: harness-team` as its second line, directly after the shebang.
```

Inserted as an identical section into the current `AGENTS.md` (100 lines with it):

| Condition | Position | Depth |
|---|---|---|
| top | before `## Startup Workflow` | line 15 (15%) |
| middle | before `## Skills symlinks` | line 57 (57%) |
| bottom | after `## Topic Docs` | line 98 (98%) |

Task (identical for every run, never mentions the rule): add
`scripts/count-skills.sh` that prints the number of skill groups, make it
executable, run it. The agent is told to read `AGENTS.md` in full first.

In scope: position only. Out of scope: file length, rule wording, other models.

## 9. Test Plan

- 15 fresh `general-purpose` subagents on **Haiku 4.5** (the model most likely to
  show a position effect; a null result on a stronger model would say less), 5 per
  condition, dispatched concurrently.
- Each gets its own `git archive HEAD` sandbox with that condition's `AGENTS.md`.
  No run is told it is part of an experiment.
- Scoring: `sed -n 2p scripts/count-skills.sh` equals `# owner: harness-team`.
- Secondary: the script runs and prints the right count; no Bash 4+ constructs
  (`bash-compat-guard.sh` pointed at the sandbox).

## 10. Result

| Condition | Depth | Rule followed | Script correct (prints 15) | Bash 3.2-safe |
|---|---|---|---|---|
| top | 15% | **5/5** | 5/5 | 5/5 |
| middle | 57% | **5/5** | 5/5 | 5/5 |
| bottom | 98% | **5/5** | 5/5 | 5/5 |

0 invalid runs. Scored from the files (`sed -n 2p`, running each script under
`/bin/bash` 3.2, `bash-compat-guard.sh` pointed at each sandbox), not from the
agents' replies. Sandboxes: session scratchpad `pos-exp/` (disposable, not committed).

## 11. Learning

- **Null result.** At ~100 lines / ~1.3k tokens, position did not change compliance
  even on the smallest current model. The "DANGER (Middle)" labels in
  `split_simulation.py` describe where a rule sits, not a measured risk at this size.
- Stronger: keeping `AGENTS.md` short is what protects it; below ~100 lines,
  reordering rules buys nothing measurable.
- Weaker: "every middle rule needs a hook *because of position*". Guards are still
  worth having because compliance is probabilistic in general, not because of where
  a rule sits.
- Uncertain — ceiling effects this design cannot rule out:
  1. Each prompt said "read AGENTS.md in full", and the file says so too.
  2. The rule was directly relevant to the task (the task creates a `*.sh`), so it
     was maximally salient when acted on.
  3. The rule had its own `##` heading.
  4. The context was tiny: sandbox + one file, not a long session.

## 12. Decision

**Pivot.** Do not reorder `AGENTS.md` for position. Test the lecture's claim where
it plausibly applies.

## 13. Next Experiment

Same rule and scoring, with the ceiling removed: embed `AGENTS.md` in a ~10k-token
injected context (global rules + architecture + skills README, the monolithic
variant `split_simulation.py` already models), drop the "read in full" instruction,
and use a task where the rule is incidental (e.g. a task that touches Python and
also adds one small helper script). Why this next: it tests the lecture's claim
at the sizes it came from, and tells us whether the split itself is what protects
compliance.

## 14. Blockers and Friction

- Each run took ~10–11 min wall-clock for a 4–11-tool-call task. Not investigated;
  the likely cost is the SubagentStop gates (which include the full test suite)
  running in the main repo each time a run finished.

## 15. Productionization Check

No. Training exercise only; nothing in the sandboxes was merged.
