"""victory_detector.py — Detect premature completion declarations and confidence calibration gaps.

Ported from learn-harness-engineering Lecture 09 (victory-detector.ts, MIT, WalkingLab).
Simulates or evaluates an agent that claims task completion against actual verification checks,
categorizing discrepancies across a Three-Layer Termination Gate:
  - Layer 1: Static / Syntax (lint, types)
  - Layer 2: Runtime / Unit tests (fast behavior)
  - Layer 3: System / End-to-End (wiring, side-effects, real integration)
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import Any, Literal


@dataclass
class VerificationCheck:
    description: str
    layer: Literal["L1_static", "L2_runtime", "L3_system"]
    claimed: bool
    actual: bool
    severity: Literal["critical", "warning"] = "critical"


@dataclass
class TaskResult:
    name: str
    claimed_complete: bool
    checks: list[VerificationCheck]

    @property
    def actual_complete(self) -> bool:
        if not self.checks:
            return False
        criticals = [c for c in self.checks if c.severity == "critical"]
        if not criticals:
            return all(c.actual for c in self.checks)
        return all(c.actual for c in criticals)

    @property
    def is_premature_victory(self) -> bool:
        return self.claimed_complete and not self.actual_complete

    @property
    def calibration_gap(self) -> float:
        if not self.checks:
            return 0.0
        claimed_passed = sum(1 for c in self.checks if c.claimed)
        actual_passed = sum(1 for c in self.checks if c.actual)
        return (claimed_passed - actual_passed) / len(self.checks)


def evaluate_task(task: TaskResult) -> dict[str, Any]:
    critical_failures = [c for c in task.checks if c.severity == "critical" and not c.actual]
    warning_failures = [c for c in task.checks if c.severity == "warning" and not c.actual]
    by_layer = {
        "L1_static": [c for c in task.checks if c.layer == "L1_static"],
        "L2_runtime": [c for c in task.checks if c.layer == "L2_runtime"],
        "L3_system": [c for c in task.checks if c.layer == "L3_system"],
    }

    layer_breakdown = {}
    for l_name, l_checks in by_layer.items():
        if not l_checks:
            continue
        c_passed = sum(1 for c in l_checks if c.actual)
        layer_breakdown[l_name] = {
            "total": len(l_checks),
            "passed": c_passed,
            "failed": len(l_checks) - c_passed,
            "clean": c_passed == len(l_checks),
        }

    return {
        "name": task.name,
        "claimed_complete": task.claimed_complete,
        "actual_complete": task.actual_complete,
        "premature_victory": task.is_premature_victory,
        "calibration_gap": round(task.calibration_gap, 3),
        "critical_failures": [c.description for c in critical_failures],
        "warning_failures": [c.description for c in warning_failures],
        "layer_breakdown": layer_breakdown,
    }


def analyze_suite(tasks: list[TaskResult]) -> dict[str, Any]:
    evaluations = [evaluate_task(t) for t in tasks]
    total = len(tasks)
    premature_count = sum(1 for e in evaluations if e["premature_victory"])
    avg_gap = sum(e["calibration_gap"] for e in evaluations) / (total or 1)

    return {
        "total_tasks": total,
        "premature_declarations": premature_count,
        "premature_rate": round(premature_count / (total or 1), 3),
        "average_calibration_gap": round(avg_gap, 3),
        "tasks": evaluations,
    }


def main() -> int:
    sample_tasks = [
        TaskResult(
            name="Add search endpoint",
            claimed_complete=True,
            checks=[
                VerificationCheck(
                    "Route syntax & types valid", "L1_static", claimed=True, actual=True
                ),
                VerificationCheck(
                    "Input validation unit tests pass", "L2_runtime", claimed=True, actual=True
                ),
                VerificationCheck(
                    "Authentication middleware applied", "L3_system", claimed=True, actual=False
                ),
                VerificationCheck(
                    "End-to-end curl response 200", "L3_system", claimed=True, actual=False
                ),
            ],
        ),
        TaskResult(
            name="Migrate credential storage",
            claimed_complete=True,
            checks=[
                VerificationCheck("Typecheck passes", "L1_static", claimed=True, actual=True),
                VerificationCheck(
                    "Storage adapter unit tests pass", "L2_runtime", claimed=True, actual=True
                ),
                VerificationCheck(
                    "Keychain backend integration verifies live",
                    "L3_system",
                    claimed=True,
                    actual=False,
                ),
            ],
        ),
        TaskResult(
            name="Fast verify stop hook wrapper",
            claimed_complete=True,
            checks=[
                VerificationCheck("Bash syntax clean", "L1_static", claimed=True, actual=True),
                VerificationCheck("Unit tests 10/10 pass", "L2_runtime", claimed=True, actual=True),
                VerificationCheck(
                    "Stop gate triggers on simulated exit", "L3_system", claimed=True, actual=True
                ),
            ],
        ),
    ]

    report = analyze_suite(sample_tasks)
    print("=== VICTORY DETECTOR: Premature Completion Audit ===")
    print(f"Total tasks: {report['total_tasks']}")
    print(f"Premature completion rate: {report['premature_rate'] * 100:.1f}%")
    print(f"Average calibration gap: {report['average_calibration_gap'] * 100:.1f}%\n")

    for t in report["tasks"]:
        flag = " [PREMATURE VICTORY]" if t["premature_victory"] else " [VERIFIED]"
        print(f"Task: '{t['name']}'{flag}")
        print(f"  Claimed: {t['claimed_complete']} | Actual: {t['actual_complete']}")
        if t["critical_failures"]:
            print(f"  Critical unmet checks: {', '.join(t['critical_failures'])}")
        for l_name, l_stat in t["layer_breakdown"].items():
            status = "PASS" if l_stat["clean"] else f"FAIL ({l_stat['failed']} broken)"
            print(f"    - {l_name}: {status}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
