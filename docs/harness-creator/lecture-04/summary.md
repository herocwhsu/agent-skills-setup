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

Comparing a single monolithic instruction file against the split router + on-demand topic doc architecture:

| Task Name | Monolithic Context (Tokens) | Split Context (Tokens) | Context Window Saved |
|:---|:---:|:---:|:---:|
| Task 1: Python Skill Bugfix | 6,884 | 2,072 | **69.9%** |
| Task 2: New Skill Implementation | 6,884 | 2,072 | **69.9%** |
| Task 3: Shell Hook / Guard Modification | 6,884 | 3,007 | **56.3%** |
| Task 4: Fast Verification Run | 6,884 | 960 | **86.1%** |
| Task 5: Documentation / Training Update | 6,884 | 3,007 | **56.3%** |
| **AVERAGE SAVINGS** | **6,884** | **2,224** | **67.7%** |

> **Result:** The progressive disclosure architecture reduces upfront context expenditure by **67.7% on average** (and up to **86.1%** for lightweight tasks), preserving thousands of tokens of budget for actual code understanding, diffing, and test output.

### 2.3 "Lost in the Middle" Vulnerability Scan

Mapping repository constraints to their normalized file depth reveals the danger zone:

| Constraint Name | File | Line | Depth | Attention Zone | Safety Mechanism |
|:---|:---|:---:|:---:|:---:|:---|
| Rule 1: Think Before Coding | `engineering-rules.md` | 9 | 6.1% | Primacy (Top) | Model prompt |
| Rule 3: Surgical Changes | `engineering-rules.md` | 15 | 10.2% | Primacy (Top) | Model prompt |
| Rule 5: Judgment Calls | `engineering-rules.md` | 25 | 17.0% | Primacy (Top) | Model prompt |
| **Rule 12: Fail Loud** | `engineering-rules.md` | 46 | 31.3% | **DANGER (Middle)** | Model prompt |
| **Personal: Commit Style** | `engineering-rules.md` | 53 | 36.1% | **DANGER (Middle)** | `commit_evidence.sh` |
| **Personal: Prompt Polish** | `engineering-rules.md` | 75 | 51.0% | **DANGER (Middle)** | Model prompt |
| **Spec-Gated Workflow Gate 1-7**| `engineering-rules.md` | 89 | 60.5% | **DANGER (Middle)** | Model prompt |
| **AGENTS: Verify Gate** | `AGENTS.md` | 22 | 26.8% | **DANGER (Middle)** | `harness-verify.sh` |
| **AGENTS: Definition of Done** | `AGENTS.md` | 32 | 39.0% | **DANGER (Middle)** | `harness-verify.sh` |
| **AGENTS: Shell Portability (macOS bash 3.2)** | `AGENTS.md` | 48 | 58.5% | **DANGER (Middle)** | `precommit_sh_check.sh` |
| **AGENTS: Skills Symlinks** | `AGENTS.md` | 52 | 63.4% | **DANGER (Middle)** | `skill_paths_guard.sh` |
| AGENTS: Hook Conventions (Exit 2) | `AGENTS.md` | 56 | 68.3% | Recency (Near Bottom)| `test_hook_wiring.sh` |
| AGENTS: Boundaries (Never write override) | `AGENTS.md` | 66 | 80.5% | Recency (Bottom) | `.claude/settings.json` deny |

> **Architectural Law:** Invariants residing in the 30%–70% depth window **cannot rely on prompt compliance alone**. In this harness, `Shell Portability`, `Skills Symlinks`, `Verify Gate`, and `Boundaries` are safeguarded by deterministic bash guard hooks, test suites, and permission deny rules.

---

## 3. Remediations & Improvements Applied

1. **Root Router Elevation ([`AGENTS.md`](file:///Users/phoenix/projects/agent-skills-setup/AGENTS.md)):**
   - Transformed `AGENTS.md` into an explicit routing engine by adding a `## Topic Docs` section pointing to:
     - [`docs/architecture.md`](file:///Users/phoenix/projects/agent-skills-setup/docs/architecture.md) — System layers, invariants, and directory layout.
     - [`agents/engineering-rules.md`](file:///Users/phoenix/projects/agent-skills-setup/agents/engineering-rules.md) — 12 core engineering rules, personal conventions, and spec-gated workflow.
     - [`skills/README.md`](file:///Users/phoenix/projects/agent-skills-setup/skills/README.md) — Subcommand specifications and integration contracts.
     - [`docs/harness-creator/`](file:///Users/phoenix/projects/agent-skills-setup/docs/harness-creator/) — Harness engineering curriculum logs, diagnostics, and exercises.
     - [`docs/migration.md`](file:///Users/phoenix/projects/agent-skills-setup/docs/migration.md) — Host environments, pyenv interpreters, and multi-agent directory setups.
   - Kept total file length at 82 lines (well within the 50–200 line limit).

2. **Automated SNR & Context Audit Tool ([`docs/harness-creator/lecture-04/code/split_simulation.py`](file:///Users/phoenix/projects/agent-skills-setup/docs/harness-creator/lecture-04/code/split_simulation.py)):**
   - Authored an executable simulation tool that parses markdown headers, calculates token and line footprints, measures task SNR across customizable task profiles, and quantifies position depth for middle-loss analysis.

3. **Instruction Lifecycle Tracking:**
   - Formalized instruction metadata requirements: each rule must define its **Source** (incident origin), **Applicability Condition** (when active), and **Expiry / Automation Path** (how it converts to a mechanical check).

---

## 4. Verification

- `docs/harness-creator/lecture-04/code/split_simulation.py`: Executed cleanly, outputting full SNR and context reduction metrics.
- `bash scripts/run-tests.sh --fast`: **54 passed, 0 failed, 0 skipped**.
- `bash scripts/harness-verify.sh`: All 8 gates passed cleanly (`registry`, `types`, `tests`, `skill paths`, `cred backends`, `hook wiring`, `state layer`, `secret scan`).
