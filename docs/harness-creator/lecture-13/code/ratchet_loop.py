#!/usr/bin/env python3
"""Autonomous Ratchet Loop Engine (Lecture 13).

Implements Karpathy's 9-step ratchet loop with Generator/Evaluator (Maker/Checker)
separation, disk-persisted external state, automated verification, and rollback
on regression.

Reference:
- Karpathy: autoresearch (https://github.com/karpathy/autoresearch)
- Addy Osmani: Loop Engineering (https://addyosmani.com/blog/loop-engineering/)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class LoopGoal:
    """Specification of the loop's target and stopping conditions."""

    name: str
    description: str
    acceptance_criteria: list[str] = field(default_factory=list)
    verification_commands: list[str] = field(default_factory=list)
    fair_game_scope: list[str] = field(default_factory=list)
    hands_off_scope: list[str] = field(default_factory=list)
    target_metric_name: str = "metric"
    lower_is_better: bool = True
    target_metric_threshold: float | None = None
    max_rounds: int = 10
    max_consecutive_failures: int = 3


@dataclass
class RoundLog:
    """Record of a single iteration of the ratchet loop."""

    round_number: int
    started_at: str
    maker_summary: str
    verification_passed: bool
    checker_verdict: str  # "PASS", "FAIL", "BLOCKED"
    metric_value: float | None
    is_improvement: bool
    action_taken: str  # "KEEP", "REVERT", "ABORT"
    issues_found: list[str] = field(default_factory=list)
    duration_seconds: float = 0.0


@dataclass
class LoopState:
    """Persistent state of the loop tracked across iterations."""

    loop_name: str
    status: str = "IN_PROGRESS"  # "IN_PROGRESS", "COMPLETED", "BLOCKED", "MAX_ROUNDS_REACHED"
    current_round: int = 0
    best_metric: float | None = None
    best_round: int | None = None
    consecutive_failures: int = 0
    rounds: list[RoundLog] = field(default_factory=list)
    blockers: list[str] = field(default_factory=list)


def parse_goal_markdown(content: str) -> LoopGoal:
    """Parse a Markdown goal file into a structured LoopGoal object."""
    lines = content.splitlines()
    name = "Untitled Loop"
    desc_lines: list[str] = []
    criteria: list[str] = []
    commands: list[str] = []
    fair_game: list[str] = []
    hands_off: list[str] = []

    current_section = ""
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("# "):
            name = stripped[2:].strip()
            continue
        if stripped.startswith("## "):
            current_section = stripped[3:].strip().lower()
            continue
        if stripped.startswith("### "):
            current_section = stripped[4:].strip().lower()
            continue

        if current_section == "goal" and stripped and not stripped.startswith("<!--"):
            desc_lines.append(stripped)
        elif "acceptance" in current_section and stripped.startswith("- [ ]"):
            criteria.append(stripped[5:].strip())
        elif "verification" in current_section:
            # Strictly extract inline code `cmd` or explicit shell lines starting with $
            if "`" in stripped:
                cmd = stripped.split("`")[1].strip()
                if cmd and cmd not in commands:
                    commands.append(cmd)
            elif stripped.startswith("$ "):
                cmd = stripped[2:].strip()
                if cmd and cmd not in commands:
                    commands.append(cmd)
        elif "fair game" in current_section and stripped.startswith("- "):
            fair_game.append(stripped[2:].strip().strip("`"))
        elif "hands off" in current_section and stripped.startswith("- "):
            hands_off.append(stripped[2:].strip().strip("`"))

    description = " ".join(desc_lines).strip()
    return LoopGoal(
        name=name,
        description=description,
        acceptance_criteria=criteria,
        verification_commands=commands,
        fair_game_scope=fair_game,
        hands_off_scope=hands_off,
    )


def render_state_markdown(state: LoopState) -> str:
    """Render a LoopState object into a human-readable Markdown document."""
    lines = [
        f"# Loop State: {state.loop_name}",
        "",
        "## Basic Info",
        f"- **Status**: `{state.status}`",
        f"- **Current Round**: {state.current_round}",
        f"- **Best Metric**: {state.best_metric if state.best_metric is not None else 'N/A'} (Round {state.best_round or 'N/A'})",
        f"- **Consecutive Failures**: {state.consecutive_failures}",
        "",
        "## Cumulative Stats",
        "| Metric | Value |",
        "| :--- | :--- |",
        f"| Rounds Completed | {len(state.rounds)} |",
        f"| Kept Improvements | {sum(1 for r in state.rounds if r.action_taken == 'KEEP')} |",
        f"| Reverted Attempts | {sum(1 for r in state.rounds if r.action_taken == 'REVERT')} |",
        f"| Total Issues Found | {sum(len(r.issues_found) for r in state.rounds)} |",
        "",
        "## Round History",
        "| Round | Started | Metric | Verification | Checker | Action | Duration | Summary |",
        "| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
    ]

    for r in state.rounds:
        metric_str = f"{r.metric_value:.4f}" if r.metric_value is not None else "-"
        v_str = "PASS" if r.verification_passed else "FAIL"
        c_str = r.checker_verdict
        lines.append(
            f"| {r.round_number} | {r.started_at[:19]} | {metric_str} | **{v_str}** | **{c_str}** | `{r.action_taken}` | {r.duration_seconds:.1f}s | {r.maker_summary[:35]} |"
        )

    if state.blockers:
        lines.extend(["", "## Blocker List"])
        for b in state.blockers:
            lines.append(f"- ⚠️ {b}")

    return "\n".join(lines) + "\n"


class RatchetLoopRunner:
    """Executes the autonomous ratchet loop cycle."""

    def __init__(
        self,
        goal: LoopGoal,
        state: LoopState | None = None,
        state_file: Path | None = None,
        results_tsv_file: Path | None = None,
    ) -> None:
        self.goal = goal
        self.state = state or LoopState(loop_name=goal.name)
        self.state_file = state_file
        self.results_tsv_file = results_tsv_file

    def is_improvement(self, current: float | None, best: float | None) -> bool:
        """Evaluate if the current metric is an improvement over the best metric."""
        if current is None:
            return False
        if best is None:
            return True
        if self.goal.lower_is_better:
            return current < best
        return current > best

    def run_verification(self, cwd: Path | None = None) -> tuple[bool, str]:
        """Run all verification commands defined in the goal."""
        if not self.goal.verification_commands:
            return True, "No verification commands specified."

        combined_output: list[str] = []
        for cmd in self.goal.verification_commands:
            try:
                res = subprocess.run(
                    cmd,
                    shell=True,
                    cwd=cwd,
                    capture_output=True,
                    text=True,
                    timeout=300,
                    check=False,
                )
                output = f"[{cmd}] Exit {res.returncode}:\n{res.stdout}\n{res.stderr}".strip()
                combined_output.append(output)
                if res.returncode != 0:
                    return False, "\n".join(combined_output)
            except (subprocess.SubprocessError, OSError) as e:
                return False, f"Verification failed to run '{cmd}': {e}"

        return True, "\n".join(combined_output)

    def execute_round(
        self,
        maker_action: Callable[[], tuple[str, float | None]],
        checker_eval: Callable[
            [str, float | None, bool], tuple[str, list[str]]
        ],  # returns (verdict, issues)
        rollback_action: Callable[[], None] | None = None,
    ) -> RoundLog:
        """Execute one complete ratchet loop step."""
        if self.state.status != "IN_PROGRESS":
            raise RuntimeError(
                f"Cannot execute round: loop is already in terminal state '{self.state.status}'"
            )

        start_time = time.time()
        start_ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start_time))
        round_no = self.state.current_round + 1
        self.state.current_round = round_no

        # 1. Maker Step
        maker_summary, current_metric = maker_action()

        # 2. Verification Step
        v_passed, _v_output = self.run_verification()

        # 3. Checker Evaluation Step (Independent Evaluator)
        checker_verdict, issues = checker_eval(maker_summary, current_metric, v_passed)

        # 4. Ratchet Decision
        improved = False
        action_taken = "REVERT"

        if v_passed and checker_verdict == "PASS":
            if self.is_improvement(current_metric, self.state.best_metric):
                improved = True
                action_taken = "KEEP"
                self.state.best_metric = current_metric
                self.state.best_round = round_no
                self.state.consecutive_failures = 0
            else:
                action_taken = "REVERT"
                self.state.consecutive_failures += 1
        else:
            action_taken = "REVERT"
            self.state.consecutive_failures += 1

        # 5. Rollback on Revert with exception handling
        if action_taken == "REVERT" and rollback_action is not None:
            try:
                rollback_action()
            except Exception as e:  # noqa: BLE001
                issues.append(f"Rollback failed: {e}")
                self.state.status = "BLOCKED"
                self.state.blockers.append(f"Rollback failed in round {round_no}: {e}")

        duration = time.time() - start_time

        log = RoundLog(
            round_number=round_no,
            started_at=start_ts,
            maker_summary=maker_summary,
            verification_passed=v_passed,
            checker_verdict=checker_verdict,
            metric_value=current_metric,
            is_improvement=improved,
            action_taken=action_taken,
            issues_found=issues,
            duration_seconds=duration,
        )

        self.state.rounds.append(log)

        # Check circuit breakers / stopping conditions (if not already blocked)
        if self.state.status == "IN_PROGRESS":
            if (
                self.goal.target_metric_threshold is not None
                and self.state.best_metric is not None
                and (
                    (
                        self.goal.lower_is_better
                        and self.state.best_metric <= self.goal.target_metric_threshold
                    )
                    or (
                        not self.goal.lower_is_better
                        and self.state.best_metric >= self.goal.target_metric_threshold
                    )
                )
            ):
                self.state.status = "COMPLETED"

            if self.state.consecutive_failures >= self.goal.max_consecutive_failures:
                self.state.status = "BLOCKED"
                self.state.blockers.append(
                    f"Exceeded max consecutive failures ({self.goal.max_consecutive_failures}). Halting loop."
                )
            elif self.state.current_round >= self.goal.max_rounds:
                self.state.status = "MAX_ROUNDS_REACHED"

        self.persist()
        return log

    def persist(self) -> None:
        """Persist state to disk in both Markdown and TSV formats."""
        if self.state_file:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            self.state_file.write_text(render_state_markdown(self.state), encoding="utf-8")

        if self.results_tsv_file and self.state.rounds:
            self.results_tsv_file.parent.mkdir(parents=True, exist_ok=True)
            write_header = not self.results_tsv_file.exists()
            with open(self.results_tsv_file, "a", encoding="utf-8") as f:
                if write_header:
                    f.write("round\ttimestamp\tmetric\tpassed\tverdict\taction\tduration\tdescription\n")
                r = self.state.rounds[-1]
                m_str = f"{r.metric_value:.4f}" if r.metric_value is not None else "-"
                clean_desc = r.maker_summary.replace("\t", " ").replace("\n", " ")[:60]
                f.write(
                    f"{r.round_number}\t{r.started_at}\t{m_str}\t{r.verification_passed}\t{r.checker_verdict}\t{r.action_taken}\t{r.duration_seconds:.2f}\t{clean_desc}\n"
                )


def main() -> int:
    """CLI entrypoint for autonomous ratchet loop."""
    parser = argparse.ArgumentParser(description="Autonomous Ratchet Loop Runner (Lecture 13)")
    parser.add_argument("--goal-file", type=Path, help="Path to goal.md file")
    parser.add_argument("--state-file", type=Path, help="Path to state.md output file")
    parser.add_argument("--tsv-file", type=Path, help="Path to results.tsv output file")
    parser.add_argument("--demo", action="store_true", help="Run a synthetic demonstration loop")
    args = parser.parse_args()

    if args.demo:
        print("=== Autonomous Ratchet Loop Demo ===")
        goal = LoopGoal(
            name="Demo Optimization Loop",
            description="Optimize synthetic loss to below 0.10",
            target_metric_threshold=0.10,
            max_rounds=5,
            max_consecutive_failures=3,
        )
        runner = RatchetLoopRunner(goal, state_file=args.state_file, results_tsv_file=args.tsv_file)

        # Synthetic sequence of improvements and regressions
        simulated_metrics = [0.25, 0.20, 0.22, 0.18, 0.08]

        def maker_step() -> tuple[str, float | None]:
            idx = runner.state.current_round
            val = simulated_metrics[idx] if idx < len(simulated_metrics) else 0.05
            return f"Experiment {idx + 1}: tweak hyperparameters", val

        def checker_step(desc: str, metric: float | None, passed: bool) -> tuple[str, list[str]]:
            # Reject if metric > 0.21
            if metric is not None and metric > 0.21:
                return "FAIL", ["Metric exceeds sanity threshold"]
            return "PASS", []

        rolled_back = []

        def rollback() -> None:
            rolled_back.append(runner.state.current_round)
            print(f"  [Ratchet] Rollback executed for round {runner.state.current_round}")

        while runner.state.status == "IN_PROGRESS":
            r = runner.execute_round(maker_step, checker_step, rollback_action=rollback)
            print(
                f"Round {r.round_number}: Metric={r.metric_value} Checker={r.checker_verdict} Action={r.action_taken} Status={runner.state.status}"
            )

        print("\nFinal State Summary:")
        print(render_state_markdown(runner.state))
        return 0

    if args.goal_file:
        if not args.goal_file.is_file():
            print(f"Error: Goal file not found: {args.goal_file}", file=sys.stderr)
            return 1
        content = args.goal_file.read_text(encoding="utf-8")
        goal = parse_goal_markdown(content)
        print("=== Loaded Goal Specification ===")
        print(f"Name: {goal.name}")
        print(f"Description: {goal.description}")
        print(f"Acceptance Criteria ({len(goal.acceptance_criteria)}):")
        for c in goal.acceptance_criteria:
            print(f"  - [ ] {c}")
        print(f"Verification Commands ({len(goal.verification_commands)}):")
        for cmd in goal.verification_commands:
            print(f"  - {cmd}")
        print(f"Fair Game Scope ({len(goal.fair_game_scope)}): {', '.join(goal.fair_game_scope) or 'None'}")
        print(f"Hands Off Scope ({len(goal.hands_off_scope)}): {', '.join(goal.hands_off_scope) or 'None'}")
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
