# Harness Creator Training — Lecture 4: Split Instructions Across Files (Why One Giant Instruction File Fails)

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-04-why-one-giant-instruction-file-fails/  
Target repo: `agent-skills-setup` (this repo)  
Date: 2026-09-26  

---

## 1. Why This Exercise

In early agent adoption, teams instinctively respond to every agent failure with: *"Add a rule to prevent this."*  
Over weeks and months, the primary instruction file (`AGENTS.md` or system prompt) balloons from 50 lines to 300, 500, or 800+ lines. 

This introduces the **Giant Instruction File Trap**:
1. **Context Budget Depletion:** Consuming 10,000–20,000 tokens (8–15% of context) before reading code or executing tasks.
2. **"Lost in the Middle" (Liu et al., 2023):** Attention in LLMs is strongly biased toward the beginning (primacy) and end (recency). Critical constraints buried at line 300 are routinely missed or diluted.
3. **Low Signal-to-Noise Ratio (SNR):** For any specific task (e.g. a simple bugfix), the agent is forced to process dozens of irrelevant deployment, database, or onboarding instructions.
4. **Maintenance Decay & Contradictions:** Rules are easy to add but rarely deleted, leading to conflicting guidance where agents choose randomly.

Lecture 4 establishes the **Instruction Architecture** solution:
- **Entry File as Router:** 50–200 lines maximum (`AGENTS.md`), containing only high-level overview, verification entry points, global hard constraints (≤15), and routing pointers to topic documents.
- **Progressive Disclosure (Reveal on Demand):** Specialized rules reside in dedicated topic docs (`docs/*.md`, `skills/<name>/SKILL.md`) of 50–150 lines, loaded only when a task triggers their applicability condition.
- **Code-Level Invariants:** Types, schemas, and signatures remain in source code rather than duplicated in natural language prompts.
- **Guard Hook Backing:** Invariants in the middle of instruction files must be backed by deterministic verification hooks (`*-guard.sh`), eliminating dependence on probabilistic LLM recall.

---

## 2. Empirical Findings from `agent-skills-setup`

Measured with [`code/split_simulation.py`](code/split_simulation.py) at three points. Numbers
in the rest of this section are from the latest run (after feat-018); rerun the script
for live values.

| Layer | First pass (feat-015) | After fixes (feat-016) | After rules split (feat-018) |
|:---|:---:|:---:|:---:|
| `AGENTS.md` (repo router) | 82 lines / ~960 tok | 96 / ~1,264 | 96 / ~1,264 |
| `agents/engineering-rules.md` (global, every host, every task) | 147 / ~2,765 | 147 / ~2,765 | **86 / ~1,800** |
| Always-loaded total | 229 / ~3,725 | 243 / ~4,029 | **182 / ~3,064** |
| Average task SNR | 23.2% | 22.9% | **30.2%** |
| Average savings vs. one monolithic file | 67.7% (miscounted) | 26.6% | **30.8%** |

feat-016 added about 300 tokens of rule metadata to `AGENTS.md`. feat-018 moved the
production gate procedure out of the global file into the `spec-workflow` skill (§3.4).

### 2.1 Signal-to-Noise Ratio (SNR) Across 5 Canonical Tasks

| Task Name | Signal Lines | Total Loaded Lines | Line SNR | Token SNR |
|:---|:---:|:---:|:---:|:---:|
| Task 1: Python Skill Bugfix | 69 | 182 | 37.9% | 41.5% |
| Task 2: New Skill Implementation | 79 | 182 | 43.4% | 47.8% |
| Task 3: Shell Hook / Guard Modification | 75 | 182 | 41.2% | 45.9% |
| Task 4: Fast Verification Run | 28 | 182 | 15.4% | 8.0% |
| Task 5: Documentation / Training Update | 26 | 182 | 14.3% | 7.5% |
| **AVERAGE** | — | **182** | **30.4%** | **30.2%** |

> **Key Finding:** About 70% of always-loaded instruction tokens are still noise for any
> single task. What remains is mostly Rules 1–12 and personal conventions, which are
> short and general and belong in every session. The "signal" labels per task are
> hand-chosen in `TASKS`, so treat these as relative, not absolute.

### 2.2 Monolithic vs Split Routing Context Savings

Split context = both always-loaded files + only the topic docs a task needs. The first
pass left `engineering-rules.md` off this side, which inflated savings to 67.7%.

| Task Name | Monolithic (Tokens) | Split (Tokens) | Saved |
|:---|:---:|:---:|:---:|
| Task 1: Python Skill Bugfix | 6,297 | 4,209 | **33.2%** |
| Task 2: New Skill Implementation | 6,297 | 4,209 | **33.2%** |
| Task 3: Shell Hook / Guard Modification | 6,297 | 5,152 | **18.2%** |
| Task 4: Fast Verification Run | 6,297 | 3,064 | **51.3%** |
| Task 5: Documentation / Training Update | 6,297 | 5,152 | **18.2%** |
| **AVERAGE SAVINGS** | **6,297** | — | **30.8%** |

### 2.3 Rule Position vs Enforcement

The script looks up each rule's line from its heading and resolves the enforcing file
on disk (`MISSING` if absent). Zones: top <25%, middle 25–75%, bottom >75%. Shortening
the global file moved its rules: Rule 5 is now in the middle, and the personal
conventions and Part IV are at the bottom.

| Constraint | File | Line | Depth | Zone | Enforced by |
|:---|:---|:---:|:---:|:---:|:---|
| Rule 5: Judgment Calls | `engineering-rules.md` | 25 | 29% | Middle | prompt only |
| Rule 12: Fail Loud | `engineering-rules.md` | 46 | 54% | Middle | prompt only |
| Commit Style | `engineering-rules.md` | 53 | 62% | Middle | prompt only |
| Subagent Verification | `engineering-rules.md` | 71 | 83% | Bottom | `commit-evidence.sh` |
| Prompt Polish | `engineering-rules.md` | 75 | 87% | Bottom | prompt only |
| Part IV: Workflow Triggers | `engineering-rules.md` | 83 | 97% | Bottom | routes to `skills/spec-workflow/SKILL.md` |
| Verify / Definition of Done | `AGENTS.md` | 25 / 35 | 26–37% | Middle | `harness-verify.sh` |
| Shell Portability (bash 3.2) | `AGENTS.md` | 51 | 53% | Middle | `bash-compat-guard.sh` |
| Skills Symlinks | `AGENTS.md` | 57 | 59% | Middle | `registry-guard.sh` (registry half only) |
| Hook Conventions | `AGENTS.md` | 63 | 66% | Middle | `*-guard.sh` ratchet in `test_harness_verify.sh` |
| Boundaries | `AGENTS.md` | 77 | 80% | Bottom | prompt only |

Exercise 3 (§2.4) found no position effect at this file size, so the middle-zone,
prompt-only rules above are recorded, not treated as defects.

### 2.4 Does position matter here? (Exercise 3)

Measured, not assumed: [`position-experiment.md`](position-experiment.md). A made-up
rule placed at 15% / 57% / 98% depth of `AGENTS.md` was followed in **15/15** Haiku 4.5
runs (5/5 at each position). At ~100 lines, position made no measurable difference; the
design has known ceiling effects, and the next experiment repeats it at ~10k tokens.

---

## 3. Remediations Applied

1. **Router `AGENTS.md`** (96 lines): `## Topic Docs` now gives each doc a *Load when*
   condition, and each incident section carries a one-line *Source / Applies / Expires*
   record. The sources were restored from the original incident text in `ee34b0a`, which
   `303e7f3` had trimmed away.
2. **`bash-compat-guard.sh` (new)**: blocks `mapfile`/`readarray`,
   `declare|local|typeset -A` and `;&`/`;;&` in any `*.sh`, in command position only.
   Wired into `harness-verify.sh` and Stop/SubagentStop; 15-case fixture test passes
   under both `/bin/bash` 3.2 and bash 5. Previously the Shell Portability rule had no
   repo-wide check: `precommit-sh-check.sh` runs `bash -n` + shellcheck, and both accept
   these constructs under bash 5.
3. **`split_simulation.py` corrected**: counts always-loaded rules on the split side,
   finds line numbers by heading, and checks that enforcing files exist.
4. **Relocation, done where the noise was**: `AGENTS.md`'s own sections are 3–8 lines
   each, so they stay. The noise was in the global rules file. Part IV's production gate
   procedure (Jira/OpenSpec, Claude-only slash commands and paths) moved verbatim into the
   new required `spec-workflow` skill. The global file keeps two host-neutral trigger
   lines. `engineering-rules.md` went from 147 to 86 lines, always-loaded context from 243
   to 182 lines, and average SNR from 22.9% to 30.2%.
   `scripts/tests/test_engineering_rules_scope.sh` keeps the global file host-general.

---

## 4. Corrections to the First Pass (2026-09-26 → 2026-09-28)

| First-pass claim | Actual |
|:---|:---|
| 67.7% average savings (86.1% max) | 26.6% (44.3% max): the always-loaded rules file was omitted from the split side |
| `precommit_sh_check.sh` enforces bash 3.2 | It checks syntax only; nothing enforced bash 3.2 until `bash-compat-guard.sh` |
| `skill_paths_guard.sh` enforces symlinks | It checks undefined path variables in skill recipes; nothing checks symlinks |
| `commit_evidence.sh` enforces commit style | It surfaces new commits for verification; commit style is prompt-only |
| Hook file names | Real names use hyphens: `precommit-sh-check.sh`, `skill-paths-guard.sh`, `commit-evidence.sh` |
| Instruction lifecycle "formalized" | No file carried it; now in `AGENTS.md` |
| Middle-zone rules "mathematically vulnerable" | Not supported at this size: 15/15 compliance in exercise 3 |
| All 8 gates passed | True, but the `types` gate had silently skipped (no `.venv`, mypy absent) and still printed `OK` |

---

## 5. Verification

- `bash .claude/hooks/tests/test_bash_compat_guard.sh`: 15/15 under `/bin/bash` 3.2.57 and bash 5.3.
- `bash scripts/tests/test_engineering_rules_scope.sh`: 0/6 before the rules split, 6/6 after.
- `.venv` rebuilt from `requirements-dev.txt`; `types-guard.sh` runs real mypy (clean).
- `bash scripts/run-tests.sh --fast`: 56 passed. `bash scripts/harness-verify.sh`: 9/9 gates.
- `spec-workflow` symlinked into Claude Code, Codex, Antigravity, and Kiro skill dirs by `install.sh`.

## 6. Status

Lecture 4 is closed. Open items live outside the lecture: `scripts/install-agents-md.sh`
has not been re-run, so host rule files still carry the old Part IV (needs approval),
and feat-017 (`harness-verify` prints `OK` for a skipped gate) is still open.
