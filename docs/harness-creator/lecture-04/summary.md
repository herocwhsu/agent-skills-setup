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

Using our standalone diagnostic simulation script ([`docs/harness-creator/lecture-04/code/split_simulation.py`](file:///Users/phoenix/projects/agent-skills-setup/docs/harness-creator/lecture-04/code/split_simulation.py)), we audited this repository's instruction layers:
- **Root Router (`AGENTS.md`):** 82 lines, ~960 tokens.
- **Global Injected Rules (`agents/engineering-rules.md`):** 147 lines, ~2,765 tokens.
- **Baseline Injected Context:** 229 lines, ~3,725 tokens.
- **Topic Docs (`docs/architecture.md`, `skills/README.md`):** 200 lines, ~3,159 tokens.
- **Hypothetical Monolithic File:** 429 lines, ~6,884 tokens.

### 2.1 Signal-to-Noise Ratio (SNR) Across 5 Canonical Tasks

We analyzed 5 representative software engineering tasks against the baseline injected instructions:

| Task Name | Signal Lines | Total Loaded Lines | Line SNR | Token SNR | Noise % |
|:---|:---:|:---:|:---:|:---:|:---:|
| **Task 1: Python Skill Bugfix** | 67 | 229 | 29.3% | 32.8% | 67.2% |
| **Task 2: New Skill Implementation** | 75 | 229 | 32.8% | 36.4% | 63.6% |
| **Task 3: Shell Hook / Guard Modification** | 71 | 229 | 31.0% | 34.3% | 65.7% |
| **Task 4: Fast Verification Run** | 28 | 229 | 12.2% | 6.6% | 93.4% |
| **Task 5: Documentation / Training Update** | 26 | 229 | 11.4% | 6.2% | 93.8% |
| **AVERAGE** | **53.4** | **229** | **23.3%** | **23.2%** | **76.8%** |

> **Key Finding:** Even in our compact baseline, **76.8% of loaded instructions are noise** for any individual task. For routine verification or documentation tasks, over 93% of the instruction tokens are irrelevant overhead.

### 2.2 Monolithic vs Split Routing Context Savings

Re-measured 2026-09-28 after the metadata and guard changes. The split side now also
pays for `agents/engineering-rules.md`, which is installed into every host file and so
is loaded on every task. The first pass left it out, which inflated savings to 67.7%.

| Task Name | Monolithic Context (Tokens) | Split Context (Tokens) | Context Window Saved |
|:---|:---:|:---:|:---:|
| Task 1: Python Skill Bugfix | 7,229 | 5,141 | **28.9%** |
| Task 2: New Skill Implementation | 7,229 | 5,141 | **28.9%** |
| Task 3: Shell Hook / Guard Modification | 7,229 | 6,117 | **15.4%** |
| Task 4: Fast Verification Run | 7,229 | 4,029 | **44.3%** |
| Task 5: Documentation / Training Update | 7,229 | 6,117 | **15.4%** |
| **AVERAGE SAVINGS** | **7,229** | — | **26.6%** |

> **Result:** Splitting saves about a quarter of instruction context per task. Most of
> what remains is the global rules file, which this repo ships to every agent and cannot
> split per task.

### 2.3 Rule Position vs Enforcement

The script now looks up each rule's line from its heading and resolves the enforcing
file on disk (`MISSING` if absent), instead of hard-coded line numbers and a
name-based guess. Zones: top <25%, middle 25–75%, bottom >75%.

| Constraint | File | Line | Depth | Zone | Enforced by |
|:---|:---|:---:|:---:|:---:|:---|
| Rule 12: Fail Loud | `engineering-rules.md` | 46 | 31% | Middle | prompt only |
| Commit Style | `engineering-rules.md` | 53 | 36% | Middle | prompt only |
| Subagent Verification | `engineering-rules.md` | 71 | 48% | Middle | `commit-evidence.sh` |
| Prompt Polish | `engineering-rules.md` | 75 | 51% | Middle | prompt only |
| Spec-Gated Workflow | `engineering-rules.md` | 87 | 59% | Middle | prompt only |
| Verify / Definition of Done | `AGENTS.md` | 25 / 35 | 26–37% | Middle | `harness-verify.sh` |
| Shell Portability (bash 3.2) | `AGENTS.md` | 51 | 53% | Middle | `bash-compat-guard.sh` (new) |
| Skills Symlinks | `AGENTS.md` | 57 | 59% | Middle | `registry-guard.sh` (registry half only) |
| Hook Conventions | `AGENTS.md` | 63 | 66% | Middle | `*-guard.sh` ratchet in `test_harness_verify.sh` |
| Boundaries | `AGENTS.md` | 77 | 80% | Bottom | prompt only |

(Run the script for the live table; line numbers above are as of this commit.)

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
4. **Relocation not done, on purpose**: `AGENTS.md`'s own sections are 3–8 lines each.
   The 77% noise comes from the global rules file, and splitting that means changing
   `scripts/install-agents-md.sh` output for every agent. That is a separate decision.

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
- `.venv` rebuilt from `requirements-dev.txt`; `types-guard.sh` now runs real mypy (clean).
- `bash scripts/harness-verify.sh`: all 9 gates pass (adds `bash compat`).
