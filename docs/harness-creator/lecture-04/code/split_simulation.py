#!/usr/bin/env python3
"""
Instruction Architecture & Signal-to-Noise Ratio (SNR) Simulation
Harness Creator Training - Lecture 04: Why One Giant Instruction File Fails

Audits instruction files, calculates task-specific Signal-to-Noise Ratio (SNR),
evaluates 'Lost in the Middle' vulnerability across rule positions, and
demonstrates context window savings of Router + Topic Doc splitting vs Monolithic files.
"""

from dataclasses import dataclass
from pathlib import Path
import re
import sys
from typing import Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[4]


@dataclass
class Section:
    name: str
    file: str
    start_line: int
    end_line: int
    line_count: int
    char_count: int
    estimated_tokens: int
    content: str


@dataclass
class TaskProfile:
    name: str
    description: str
    target_sections: List[str]  # Section names considered signal for this task
    needed_topic_docs: List[str]  # Topic docs loaded on demand


def estimate_tokens(text: str) -> int:
    """Rough estimation: ~4 chars per token for code/instructions."""
    return max(1, len(text) // 4)


def parse_markdown_sections(file_path: Path) -> List[Section]:
    """Parse markdown file into sections delimited by H1/H2 headers."""
    if not file_path.exists():
        return []

    lines = file_path.read_text(encoding="utf-8").splitlines()
    sections: List[Section] = []
    current_name = "Header / Intro"
    current_start = 1
    current_lines: List[str] = []

    for idx, line in enumerate(lines, 1):
        if line.startswith("# ") or line.startswith("## "):
            if current_lines:
                content = "\n".join(current_lines)
                sections.append(
                    Section(
                        name=current_name,
                        file=file_path.name,
                        start_line=current_start,
                        end_line=idx - 1,
                        line_count=len(current_lines),
                        char_count=len(content),
                        estimated_tokens=estimate_tokens(content),
                        content=content,
                    )
                )
            current_name = line.strip("# \t")
            current_start = idx
            current_lines = [line]
        else:
            current_lines.append(line)

    if current_lines:
        content = "\n".join(current_lines)
        sections.append(
            Section(
                name=current_name,
                file=file_path.name,
                start_line=current_start,
                end_line=len(lines),
                line_count=len(current_lines),
                char_count=len(content),
                estimated_tokens=estimate_tokens(content),
                content=content,
            )
        )

    return sections


TASKS = [
    TaskProfile(
        name="Task 1: Python Skill Bugfix",
        description="Fix bug in python skill (e.g. regex/keychain in polish_engine.py)",
        target_sections=[
            "Part I: Core Principles (Karpathy's Rules)",
            "Part II: Production Guardrails (@Mnilax Extensions)",
            "Verify",
            "Definition of Done",
            "Python Tooling",
            "Commit style",
        ],
        needed_topic_docs=["skills/README.md"],
    ),
    TaskProfile(
        name="Task 2: New Skill Implementation",
        description="Create a new agent skill (e.g. skills/kanban-ai)",
        target_sections=[
            "Part I: Core Principles (Karpathy's Rules)",
            "Part II: Production Guardrails (@Mnilax Extensions)",
            "Skills symlinks",
            "Boundaries (scope)",
            "Verify",
            "Definition of Done",
            "Commit style",
        ],
        needed_topic_docs=["skills/README.md"],
    ),
    TaskProfile(
        name="Task 3: Shell Hook / Guard Modification",
        description="Modify shell validation hook (e.g. state-layer-guard.sh)",
        target_sections=[
            "Part I: Core Principles (Karpathy's Rules)",
            "Part II: Production Guardrails (@Mnilax Extensions)",
            "Shell Portability",
            "Hook Conventions",
            "Verify",
            "Definition of Done",
            "Commit style",
        ],
        needed_topic_docs=["docs/architecture.md"],
    ),
    TaskProfile(
        name="Task 4: Fast Verification Run",
        description="Run test suite and routine verification",
        target_sections=[
            "Startup Workflow",
            "Verify",
            "Definition of Done",
        ],
        needed_topic_docs=[],
    ),
    TaskProfile(
        name="Task 5: Documentation / Curriculum Update",
        description="Update training lecture notes or architecture docs",
        target_sections=[
            "Startup Workflow",
            "End of Session",
            "Language",
            "Commit style",
            "Definition of Done",
        ],
        needed_topic_docs=["docs/architecture.md"],
    ),
]


def run_audit() -> None:
    agents_md = REPO_ROOT / "AGENTS.md"
    eng_rules = REPO_ROOT / "agents/engineering-rules.md"
    arch_doc = REPO_ROOT / "docs/architecture.md"
    skills_readme = REPO_ROOT / "skills/README.md"

    sec_agents = parse_markdown_sections(agents_md)
    sec_eng = parse_markdown_sections(eng_rules)
    sec_arch = parse_markdown_sections(arch_doc)
    sec_skills = parse_markdown_sections(skills_readme)

    all_entry_sections = sec_agents + sec_eng

    total_entry_lines = sum(s.line_count for s in all_entry_sections)
    total_entry_tokens = sum(s.estimated_tokens for s in all_entry_sections)

    # Monolithic hypothetical file includes router + full architecture + full skills readme + spec workflows
    all_monolithic_sections = sec_agents + sec_eng + sec_arch + sec_skills
    total_mono_lines = sum(s.line_count for s in all_monolithic_sections)
    total_mono_tokens = sum(s.estimated_tokens for s in all_monolithic_sections)

    print("=" * 80)
    print("  HARNESS CREATOR TRAINING — LECTURE 04")
    print("  Instruction File Architecture & SNR Audit")
    print("=" * 80)
    print(f"\n[1] File Footprint Overview:")
    print(f"  • Root Router (AGENTS.md):            {sum(s.line_count for s in sec_agents):>4} lines, ~{sum(s.estimated_tokens for s in sec_agents):>5} tokens")
    print(f"  • Global System Rules (eng-rules.md): {sum(s.line_count for s in sec_eng):>4} lines, ~{sum(s.estimated_tokens for s in sec_eng):>5} tokens")
    print(f"  • Baseline Injected Entry Context:    {total_entry_lines:>4} lines, ~{total_entry_tokens:>5} tokens")
    print(f"  • Topic Doc (docs/architecture.md):    {sum(s.line_count for s in sec_arch):>4} lines, ~{sum(s.estimated_tokens for s in sec_arch):>5} tokens")
    print(f"  • Topic Doc (skills/README.md):        {sum(s.line_count for s in sec_skills):>4} lines, ~{sum(s.estimated_tokens for s in sec_skills):>5} tokens")
    print(f"  • Hypothetical Monolithic File:       {total_mono_lines:>4} lines, ~{total_mono_tokens:>5} tokens\n")

    print("[2] Signal-to-Noise Ratio (SNR) Analysis Across 5 Representative Tasks:")
    print("-" * 80)
    header = f"| {'Task Name':<32} | {'Signal Lines':<12} | {'Total Lines':<11} | {'Line SNR':<9} | {'Token SNR':<9} |"
    print(header)
    print("|" + "-" * 34 + "|" + "-" * 14 + "|" + "-" * 13 + "|" + "-" * 11 + "|" + "-" * 11 + "|")

    snr_results = []
    for task in TASKS:
        signal_sections = [s for s in all_entry_sections if any(t in s.name for t in task.target_sections)]
        sig_lines = sum(s.line_count for s in signal_sections)
        sig_tokens = sum(s.estimated_tokens for s in signal_sections)

        line_snr = (sig_lines / total_entry_lines) * 100 if total_entry_lines else 0
        token_snr = (sig_tokens / total_entry_tokens) * 100 if total_entry_tokens else 0
        snr_results.append((task, sig_lines, sig_tokens, line_snr, token_snr))

        print(f"| {task.name:<32} | {sig_lines:<12} | {total_entry_lines:<11} | {line_snr:>8.1f}% | {token_snr:>8.1f}% |")

    avg_line_snr = sum(r[3] for r in snr_results) / len(snr_results)
    avg_token_snr = sum(r[4] for r in snr_results) / len(snr_results)
    print("|" + "-" * 34 + "|" + "-" * 14 + "|" + "-" * 13 + "|" + "-" * 11 + "|" + "-" * 11 + "|")
    print(f"| {'AVERAGE':<32} | {'-':<12} | {total_entry_lines:<11} | {avg_line_snr:>8.1f}% | {avg_token_snr:>8.1f}% |")
    print("-" * 80)
    print(f"  Key Insight: In the baseline setup, ~{100 - avg_token_snr:.1f}% of loaded instructions are NOISE for any single task!")

    print("\n[3] Monolithic vs Progressive Disclosure (Router + Topic Doc) Simulation:")
    print("-" * 80)
    sim_header = f"| {'Task Name':<32} | {'Monolithic Tokens':<18} | {'Split Tokens':<13} | {'Context Saved':<13} |"
    print(sim_header)
    print("|" + "-" * 34 + "|" + "-" * 20 + "|" + "-" * 15 + "|" + "-" * 15 + "|")

    savings_list = []
    topic_map = {
        "docs/architecture.md": sum(s.estimated_tokens for s in sec_arch),
        "skills/README.md": sum(s.estimated_tokens for s in sec_skills),
    }

    for task, sig_lines, sig_tokens, l_snr, t_snr in snr_results:
        # In split architecture, agent reads Root Router (AGENTS.md) + only the needed topic docs
        router_tokens = sum(s.estimated_tokens for s in sec_agents)
        needed_topic_tokens = sum(topic_map.get(doc, 0) for doc in task.needed_topic_docs)
        split_tokens = router_tokens + needed_topic_tokens

        savings = ((total_mono_tokens - split_tokens) / total_mono_tokens) * 100
        savings_list.append(savings)
        print(f"| {task.name:<32} | {total_mono_tokens:>18} | {split_tokens:>13} | {savings:>12.1f}% |")

    avg_savings = sum(savings_list) / len(savings_list)
    print("|" + "-" * 34 + "|" + "-" * 20 + "|" + "-" * 15 + "|" + "-" * 15 + "|")
    print(f"| {'AVERAGE SAVINGS':<32} | {total_mono_tokens:>18} | {'-':<13} | {avg_savings:>12.1f}% |")
    print("-" * 80)

    print("\n[4] 'Lost in the Middle' Position Risk Analysis:")
    print("-" * 80)
    print("  According to Liu et al. (2023), rules in the 30%-70% depth window suffer severe recall drop.")

    critical_rules = [
        ("Rule 1: Think Before Coding", eng_rules, 9),
        ("Rule 3: Surgical Changes", eng_rules, 15),
        ("Rule 5: Judgment Calls", eng_rules, 25),
        ("Rule 12: Fail Loud", eng_rules, 46),
        ("Personal: Commit Style", eng_rules, 53),
        ("Personal: Prompt Polish", eng_rules, 75),
        ("Spec-Gated Workflow Gate 1-7", eng_rules, 89),
        ("AGENTS: Verify Gate", agents_md, 22),
        ("AGENTS: Definition of Done", agents_md, 32),
        ("AGENTS: Shell Portability (macOS bash 3.2)", agents_md, 48),
        ("AGENTS: Skills Symlinks", agents_md, 52),
        ("AGENTS: Hook Conventions (Exit 2)", agents_md, 56),
        ("AGENTS: Boundaries (Never write override)", agents_md, 66),
    ]

    print(f"  | {'Constraint Name':<38} | {'File':<18} | {'Line':<5} | {'Depth':<7} | {'Zone':<12} | {'Safety Mech':<15} |")
    print("  |" + "-" * 40 + "|" + "-" * 20 + "|" + "-" * 7 + "|" + "-" * 9 + "|" + "-" * 14 + "|" + "-" * 17 + "|")

    for name, file_p, line_no in critical_rules:
        total_lines = len(file_p.read_text(encoding="utf-8").splitlines())
        depth = line_no / total_lines
        if depth < 0.25:
            zone = "Primacy (Top)"
        elif depth > 0.75:
            zone = "Recency (Bottom)"
        else:
            zone = "DANGER (Middle)"

        # Safety mechanism check
        if "Hook" in name or "Exit 2" in name:
            mech = "test_hook_wiring"
        elif "Shell Portability" in name:
            mech = "precommit_sh_check"
        elif "Boundaries" in name:
            mech = "settings.json deny"
        elif "Verify" in name or "Done" in name:
            mech = "harness-verify.sh"
        elif "Symlinks" in name:
            mech = "skill_paths_guard"
        elif "Commit Style" in name:
            mech = "commit_evidence.sh"
        elif "Prompt Polish" in name:
            mech = "Model instruction"
        else:
            mech = "Model instruction"

        print(f"  | {name:<38} | {file_p.name:<18} | {line_no:<5} | {depth * 100:>5.1f}% | {zone:<12} | {mech:<15} |")
    print("-" * 80)
    print("  Key Takeaway: Rules residing in the 'DANGER (Middle)' zone MUST be backed by automated hooks;")
    print("  text instructions alone in the middle of long files are mathematically vulnerable to model neglect.")
    print("=" * 80)


if __name__ == "__main__":
    run_audit()
