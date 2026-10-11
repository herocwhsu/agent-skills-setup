"""Unit tests for Autonomous Ratchet Loop Engine (Lecture 13)."""

from __future__ import annotations

from pathlib import Path

import pytest
from ratchet_loop import (
    LoopGoal,
    RatchetLoopRunner,
    parse_goal_markdown,
)


def test_parse_goal_markdown() -> None:
    content = """# Goal Loop: Optimize Cache

## Goal
Reduce Redis cache hit latency to below 2ms.

## Acceptance Criteria
- [ ] `pytest tests/test_cache.py` passes
- [ ] Latency benchmark <= 2.0ms

## Fair Game
- `src/cache.py`
- `tests/test_cache.py`

## Hands Off
- `src/config.py`
- `docker-compose.yml`

## Verification Method
1. `pytest tests/test_cache.py`
- `python scripts/bench_cache.py`
$ python scripts/bench_network.py
"""
    goal = parse_goal_markdown(content)
    assert goal.name == "Goal Loop: Optimize Cache"
    assert "Reduce Redis cache hit latency" in goal.description
    assert len(goal.acceptance_criteria) == 2
    assert "src/cache.py" in goal.fair_game_scope
    assert "src/config.py" in goal.hands_off_scope
    assert len(goal.verification_commands) == 3
    assert "pytest tests/test_cache.py" in goal.verification_commands[0]
    assert "python scripts/bench_network.py" in goal.verification_commands[2]


def test_parse_goal_template_file() -> None:
    template_path = Path(__file__).parent / "goal-template.md"
    assert template_path.is_file()
    content = template_path.read_text(encoding="utf-8")
    goal = parse_goal_markdown(content)

    assert goal.name == "Goal Loop Template"
    assert len(goal.acceptance_criteria) == 5
    assert "npx tsc --noEmit" in goal.verification_commands
    assert "npm run lint" in goal.verification_commands
    assert "npm test" in goal.verification_commands
    assert "npx vitest --coverage" in goal.verification_commands
    # Ensure prose line was NOT parsed as a command
    assert not any("After implementation" in cmd for cmd in goal.verification_commands)


def test_is_improvement() -> None:
    # Lower is better (default, e.g. latency, loss)
    goal_lower = LoopGoal(name="Minimization", description="", lower_is_better=True)
    runner_lower = RatchetLoopRunner(goal_lower)
    assert runner_lower.is_improvement(0.15, 0.20) is True
    assert runner_lower.is_improvement(0.25, 0.20) is False
    assert runner_lower.is_improvement(0.20, 0.20) is False
    assert runner_lower.is_improvement(0.20, None) is True
    assert runner_lower.is_improvement(None, 0.20) is False

    # Higher is better (e.g. throughput, accuracy)
    goal_higher = LoopGoal(name="Maximization", description="", lower_is_better=False)
    runner_higher = RatchetLoopRunner(goal_higher)
    assert runner_higher.is_improvement(0.85, 0.80) is True
    assert runner_higher.is_improvement(0.75, 0.80) is False
    assert runner_higher.is_improvement(0.80, 0.80) is False


def test_verification_command_execution(tmp_path: Path) -> None:
    # Passing verification
    goal_pass = LoopGoal(
        name="Pass",
        description="",
        verification_commands=["python3 -c 'exit(0)'"],
    )
    runner_pass = RatchetLoopRunner(goal_pass)
    passed, out = runner_pass.run_verification(cwd=tmp_path)
    assert passed is True

    # Failing verification
    goal_fail = LoopGoal(
        name="Fail",
        description="",
        verification_commands=["python3 -c 'exit(2)'"],
    )
    runner_fail = RatchetLoopRunner(goal_fail)
    passed, out = runner_fail.run_verification(cwd=tmp_path)
    assert passed is False
    assert "Exit 2" in out


def test_execute_round_ratchet_decisions(tmp_path: Path) -> None:
    state_file = tmp_path / "state.md"
    tsv_file = tmp_path / "results.tsv"
    goal = LoopGoal(
        name="Test Ratchet",
        description="Optimize metric",
        target_metric_threshold=0.10,
        max_rounds=5,
        max_consecutive_failures=2,
    )
    runner = RatchetLoopRunner(goal, state_file=state_file, results_tsv_file=tsv_file)

    rollbacks: list[int] = []

    def rollback() -> None:
        rollbacks.append(runner.state.current_round)

    # Round 1: Baseline success (metric 0.30)
    r1 = runner.execute_round(
        maker_action=lambda: ("Initial attempt", 0.30),
        checker_eval=lambda desc, m, v: ("PASS", []),
        rollback_action=rollback,
    )
    assert r1.action_taken == "KEEP"
    assert runner.state.best_metric == 0.30
    assert runner.state.consecutive_failures == 0
    assert len(rollbacks) == 0

    # Round 2: Metric regression (0.35 > 0.30) -> REVERT
    r2 = runner.execute_round(
        maker_action=lambda: ("Regression attempt", 0.35),
        checker_eval=lambda desc, m, v: ("PASS", []),
        rollback_action=rollback,
    )
    assert r2.action_taken == "REVERT"
    assert runner.state.best_metric == 0.30
    assert runner.state.consecutive_failures == 1
    assert len(rollbacks) == 1
    assert rollbacks[-1] == 2

    # Round 3: Metric improvement but Checker rejects -> REVERT
    r3 = runner.execute_round(
        maker_action=lambda: ("Checker rejection", 0.20),
        checker_eval=lambda desc, m, v: ("FAIL", ["Missing type annotations"]),
        rollback_action=rollback,
    )
    assert r3.action_taken == "REVERT"
    assert runner.state.best_metric == 0.30
    assert runner.state.consecutive_failures == 2
    # Consecutive failures threshold reached (2) -> status BLOCKED
    assert runner.state.status == "BLOCKED"
    assert len(runner.state.blockers) > 0


def test_target_completion_threshold(tmp_path: Path) -> None:
    goal = LoopGoal(
        name="Target Completion",
        description="",
        target_metric_threshold=0.05,
        max_rounds=5,
    )
    runner = RatchetLoopRunner(goal, state_file=tmp_path / "state.md")

    r = runner.execute_round(
        maker_action=lambda: ("Great win", 0.04),
        checker_eval=lambda desc, m, v: ("PASS", []),
    )
    assert r.action_taken == "KEEP"
    assert runner.state.status == "COMPLETED"


def test_max_rounds_circuit_breaker(tmp_path: Path) -> None:
    goal = LoopGoal(
        name="Max Rounds",
        description="",
        max_rounds=2,
        max_consecutive_failures=10,
    )
    runner = RatchetLoopRunner(goal)

    runner.execute_round(
        maker_action=lambda: ("Round 1", 0.50),
        checker_eval=lambda desc, m, v: ("PASS", []),
    )
    assert runner.state.status == "IN_PROGRESS"

    runner.execute_round(
        maker_action=lambda: ("Round 2", 0.40),
        checker_eval=lambda desc, m, v: ("PASS", []),
    )
    assert runner.state.status == "MAX_ROUNDS_REACHED"

    # Terminal state guard
    with pytest.raises(RuntimeError, match="already in terminal state"):
        runner.execute_round(
            maker_action=lambda: ("Round 3", 0.30),
            checker_eval=lambda desc, m, v: ("PASS", []),
        )


def test_rollback_exception_handling() -> None:
    goal = LoopGoal(name="Rollback Error", description="")
    runner = RatchetLoopRunner(goal)

    def crashing_rollback() -> None:
        raise OSError("Simulated git lockfile error")

    # Force a revert
    runner.execute_round(
        maker_action=lambda: ("Failing step", 0.5),
        checker_eval=lambda desc, m, v: ("FAIL", ["Broken"]),
        rollback_action=crashing_rollback,
    )
    assert runner.state.status == "BLOCKED"
    assert any("Rollback failed" in b for b in runner.state.blockers)


def test_state_persistence_and_markdown(tmp_path: Path) -> None:
    state_file = tmp_path / "state.md"
    tsv_file = tmp_path / "results.tsv"
    goal = LoopGoal(name="Persistence Test", description="")
    runner = RatchetLoopRunner(goal, state_file=state_file, results_tsv_file=tsv_file)

    runner.execute_round(
        maker_action=lambda: ("Round 1", 0.25),
        checker_eval=lambda desc, m, v: ("PASS", []),
    )

    assert state_file.is_file()
    assert tsv_file.is_file()

    state_md = state_file.read_text(encoding="utf-8")
    assert "Persistence Test" in state_md
    assert "Kept Improvements" in state_md
    assert "Verification" in state_md
    assert "Checker" in state_md

    tsv_content = tsv_file.read_text(encoding="utf-8")
    assert "round\ttimestamp\tmetric\tpassed" in tsv_content
    assert "0.2500" in tsv_content
