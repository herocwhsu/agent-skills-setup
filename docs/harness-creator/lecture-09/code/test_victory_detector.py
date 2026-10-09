"""test_victory_detector.py — Unit tests for Lecture 09 victory detector."""

from victory_detector import TaskResult, VerificationCheck, analyze_suite, evaluate_task


def test_verified_task_passes():
    task = TaskResult(
        name="Task 1",
        claimed_complete=True,
        checks=[
            VerificationCheck("L1 check", "L1_static", claimed=True, actual=True),
            VerificationCheck("L2 check", "L2_runtime", claimed=True, actual=True),
            VerificationCheck("L3 check", "L3_system", claimed=True, actual=True),
        ],
    )
    res = evaluate_task(task)
    assert res["premature_victory"] is False
    assert res["actual_complete"] is True
    assert res["calibration_gap"] == 0.0


def test_premature_victory_detected():
    task = TaskResult(
        name="Task 2",
        claimed_complete=True,
        checks=[
            VerificationCheck("L1 check", "L1_static", claimed=True, actual=True),
            VerificationCheck("L2 check", "L2_runtime", claimed=True, actual=True),
            VerificationCheck("L3 check", "L3_system", claimed=True, actual=False),
        ],
    )
    res = evaluate_task(task)
    assert res["premature_victory"] is True
    assert res["actual_complete"] is False
    assert res["critical_failures"] == ["L3 check"]
    assert res["calibration_gap"] > 0


def test_suite_analysis():
    t1 = TaskResult("T1", True, [VerificationCheck("C1", "L1_static", True, True)])
    t2 = TaskResult("T2", True, [VerificationCheck("C2", "L2_runtime", True, False)])
    suite = analyze_suite([t1, t2])
    assert suite["total_tasks"] == 2
    assert suite["premature_declarations"] == 1
    assert suite["premature_rate"] == 0.5


def test_empty_checks_cannot_be_complete():
    # Empty check list must never evaluate to complete or allow premature victory to slip by silently
    task = TaskResult(name="Empty Task", claimed_complete=True, checks=[])
    res = evaluate_task(task)
    assert res["actual_complete"] is False
    assert res["premature_victory"] is True
    assert res["calibration_gap"] == 0.0


def test_warning_only_failures_prevent_completion():
    # If a task has only warning checks and they fail, task cannot be complete
    task = TaskResult(
        name="Warning Task",
        claimed_complete=True,
        checks=[
            VerificationCheck(
                "Style guideline check", "L1_static", claimed=True, actual=False, severity="warning"
            )
        ],
    )
    res = evaluate_task(task)
    assert res["actual_complete"] is False
    assert res["premature_victory"] is True
    assert res["warning_failures"] == ["Style guideline check"]


def test_negative_calibration_gap():
    # Under-confident agent (claimed False, actual passed)
    task = TaskResult(
        name="Humble Task",
        claimed_complete=False,
        checks=[
            VerificationCheck("L1 check", "L1_static", claimed=False, actual=True),
        ],
    )
    assert task.calibration_gap == -1.0
    res = evaluate_task(task)
    assert res["premature_victory"] is False
    assert res["actual_complete"] is True
