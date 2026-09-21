---
subcommand: change-eval
group: utils
slash: /utils-change-eval <diff-or-path> [--task <description>]
output: stdout (a short verdict list); optional saved report if asked
---

# utils/change-eval — Independent Review of a Repo Change

Gets a second, genuinely different model's critical read on a change (a
hook's fallback logic, a permissions rule, a config edit) before treating it
as done, then mechanically checks every claim the reviewer makes before
acting on it. Built from the pattern used successfully in the
`harness-creator` training (`docs/harness-creator/lecture-02/`): `codex-kiro`
caught two real defects in a permissions block and a venv fallback that a
same-model review missed; a third model (`agy`) then produced two confident,
specific, and false claims in the same session — both caught only because
they were checked, not trusted.

## Why this exists, and why it is NOT `skill-eval`

`utils/skill-eval` evaluates a **skill's transcript** — did it follow its own
behavioral protocol (checked the cache, fell back correctly). That has
mechanical markers to count (`<PREFIX>_STATUS:` lines) and explicitly
rejects LLM grading as an extra source of error on top of an already-cheap
mechanical check (`skill-eval/IMPL.md`'s "Common mistakes" table).

This tool evaluates a **repo-level change** — a diff to a hook, a config
file, a script. There is no mechanical marker for "is this fallback logic
correct" or "is this permission pattern safe" — nothing to count. A
different model's critique is the only way to generate a hypothesis worth
checking at all. So this tool uses LLM review on purpose, in a scope where
`skill-eval`'s no-LLM-grading rule does not apply — and compensates for the
LLM's unreliability by never trusting a claim without mechanically
confirming it first. If you're evaluating a skill's own behavior rather than
a code/config change, use `skill-eval` instead.

## Two modes

### Mode 1 — Review (default; cheap, fast, use most of the time)

Hand the diff to a different model, ask for a blunt critique, then verify
every specific claim before acting on it. This is what caught the glob-depth
bug and the version-drift gap in Lecture 2 — both real defects a same-model
read missed.

### Mode 2 — Task-completion comparison (occasional; expensive, use sparingly)

Seed identical before/after states of a real task, dispatch fresh agents to
each, independently verify the outcome. This answers "does this change
measurably affect agent *behavior*," not just "is this well-designed." Use
only when Mode 1 can't answer the question — e.g. testing whether removing
a harness subsystem (Instructions/State/Feedback) actually degrades a real
agent's work, which is a behavioral question, not a design-critique one.

The Lecture 2 exclusion test (`docs/harness-creator/lecture-02/`) used this
mode and got a null result — the task was too small and too well-scaffolded
by sibling files to discriminate. That's itself useful information: Mode 2
only works when the seeded task is genuinely sensitive to what's being
removed. A trivial task will pass every condition and tell you nothing.

## Workflow — Mode 1 (Review)

### Step 1 — Pick a reviewer model

Prefer a model from a genuinely different family than whichever model is
doing the primary work, not just a different session of the same model:

| Reviewer | Invocation | Family |
|---|---|---|
| `codex-kiro` | `codex-kiro exec -s read-only -C <repo> "<prompt>"` | GPT, via kiro-gateway |
| `agy` | `agy --model gemini-3.1-pro-low --dangerously-skip-permissions --print="<prompt>"` | Gemini |

Use `gemini-3.1-pro-low`, not the CLI's Flash default — Flash produced two
false claims (a real PyPI package called a "typosquat"; an installed Python
version claimed to "not exist") in the session that motivated this tool.
`agy` needs `--dangerously-skip-permissions` to run any tool in headless
`--print` mode (it cannot prompt for approval) — only grant this for a
read-only review command, and say so explicitly in the prompt so the
reviewer doesn't attempt writes.

If the primary reviewer fails (a real possibility — `codex-kiro` failed
outright once mid-training with a hard stream disconnect), retry once before
falling back to a second reviewer. A single transient failure is not
evidence the tool is broken; bring in a second model specifically because
one failed, the way `agy` was brought in that session.

### Step 2 — Ask for a blunt, specific critique

Bad prompt: "does this look OK?" — invites a rubber stamp.

Good prompt: name the exact files, the exact pattern to critique, and ask
for a verdict per point, under a word limit so the reviewer commits to
specifics rather than hedging. See
`docs/harness-creator/lecture-02/progress-detail.md` Part 4 and Part 8 for
two worked examples of prompts that produced real findings.

### Step 3 — Verify every specific, checkable claim (do not skip this)

For each claim the reviewer makes, ask: is this something I can check right
now with a command, not just re-read the code and agree? Then run that
command. Examples from this tool's origin session:

| Claim | How it was checked | Result |
|---|---|---|
| "`Write(//Users/*/AGENTS.override.md)` doesn't cross path segments" | Built a local fixture tree, ran the glob both ways | True — fixed |
| "`.venv` version drift would be silently used" | Simulated drift (`echo 9.9.9 > .python-version`), ran the gate | True — fixed |
| "Python 3.14.7 does not exist" | Already-run `python3 --version` output from earlier in the same session | False — refuted |
| "`httpx2`/`httpcore2` are potential typosquats" | `pip show httpx2` + `pipdeptree --reverse -p httpx2` | False — refuted |
| "`google-generativeai` is deprecated" | `WebFetch` on `pypi.org/project/google-generativeai/` directly | True — recorded as an open finding |

A claim with no available check (pure design opinion, e.g. "this feels
fragile") stays a lead, not a verdict — note it, don't act on it without
independent confirmation.

### Step 4 — Act only on confirmed findings

Fix what's confirmed true. Explicitly record what was checked and found
false — that's real information too (which reviewer/tier produces noise),
not something to discard silently. Never fold an unconfirmed claim into a
change as if it were verified.

## Workflow — Mode 2 (Task-completion comparison)

1. Design a task genuinely sensitive to the thing being tested — not
   "mirror this 20-line file," which any capable model can do from the
   sibling file alone regardless of harness presence. Prefer tasks with
   real ambiguity in scope, a non-obvious stopping point, or enough steps
   that losing state plausibly costs something.
2. Build one full "baseline" environment with everything present.
3. Copy it into N variants, each with exactly one thing removed or changed
   — never build variants independently, or you can't attribute a
   difference to the one thing you changed.
4. Dispatch a **fresh** `general-purpose` subagent per variant (not a
   fork — a fork inherits this conversation's context and would know it's
   part of an experiment, contaminating the result). Give it only the
   variant's directory and a neutral instruction to read what's there and
   do the task.
5. Independently verify every condition's outcome yourself — run the actual
   verification command, don't take a subagent's self-report ("all tests
   pass") at face value.
6. Compare outcomes across conditions. A null result (no difference) is a
   real finding — it means the task didn't discriminate, not that the
   harness component doesn't matter. Say so plainly rather than forcing a
   conclusion the data doesn't support.

## When to run this

- Before considering a hook, config, or script change "done," when the
  change encodes a security- or correctness-relevant assumption (a
  permission pattern, a fallback path, a version check) — Mode 1.
- When a harness-design question is genuinely behavioral, not just
  structural, and worth the cost of a live comparison — Mode 2.
- NOT for routine, low-risk edits (a comment fix, a doc typo) — the review
  cost isn't worth it, and running it on everything would train you to
  ignore its output.

## Common mistakes

| Mistake | Fix |
|---|---|
| Treating the reviewer's verdict as ground truth | Every specific, checkable claim must be independently confirmed before acting — see Step 3 |
| Using the CLI's default (often fast/cheap) model tier for `agy` | Pin to `gemini-3.1-pro-low`; the Flash default produced false claims in this tool's origin session |
| Running Mode 2 with a task any model can do from context alone | Design for genuine sensitivity to what's being removed, or expect a null result |
| Treating a null Mode-2 result as "the harness doesn't matter" | It usually means the task didn't discriminate — redesign the task before concluding anything about the harness |
| Giving up after one reviewer failure | Retry once; if it fails again, bring in a second, differently-sourced model rather than abandoning the review |
| Merging this with `skill-eval` | Different scope (repo changes vs. skill transcripts) and opposite default stance on LLM grading — see "Why this exists" above |
