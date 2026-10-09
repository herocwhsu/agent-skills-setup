"""test_e2e_runner.py — Unit tests for Lecture 10 E2E runner."""

from __future__ import annotations

import os
import sys

# Ensure module path resolution
sys.path.insert(0, os.path.dirname(__file__))

from e2e_runner import (
    PipelineStep,
    TestCase,
    calculate_metrics,
    evaluate_test_cases,
    get_standard_scenarios,
    run_e2e_test,
    run_unit_tests,
)


def test_healthy_pipeline_passes_both():
    tc = TestCase(
        name="Healthy Flow",
        steps=[
            PipelineStep(name="Step 1", unit_test_passes=True, actual_behavior="works"),
            PipelineStep(name="Step 2", unit_test_passes=True, actual_behavior="works"),
        ],
    )
    ut_passed, ut_total = run_unit_tests(tc)
    assert ut_passed == 2
    assert ut_total == 2

    e2e_pass, fail_step, fail_reason = run_e2e_test(tc)
    assert e2e_pass is True
    assert fail_step is None
    assert fail_reason is None


def test_hard_failure_caught_by_e2e():
    tc = TestCase(
        name="Service Outage",
        steps=[
            PipelineStep(name="Auth", unit_test_passes=True, actual_behavior="works"),
            PipelineStep(
                name="Query DB",
                unit_test_passes=True,
                actual_behavior="fails",
                failure_reason="Deadlock in transaction pool",
            ),
        ],
    )
    ut_passed, _ = run_unit_tests(tc)
    assert ut_passed == 2  # Unit test mocked the DB

    e2e_pass, fail_step, fail_reason = run_e2e_test(tc)
    assert e2e_pass is False
    assert fail_step == "Query DB"
    assert fail_reason == "Deadlock in transaction pool"


def test_partial_failure_propagates_downstream():
    tc = TestCase(
        name="Silent Degradation",
        steps=[
            PipelineStep(
                name="Schema Transform",
                unit_test_passes=True,
                actual_behavior="partial",
                failure_reason="Dropped nullable timestamp column",
            ),
            PipelineStep(
                name="Downstream Consumer",
                unit_test_passes=True,
                actual_behavior="works",
            ),
        ],
    )
    e2e_pass, fail_step, fail_reason = run_e2e_test(tc)
    assert e2e_pass is False
    assert fail_step == "Schema Transform"
    assert fail_reason == "Dropped nullable timestamp column"


def test_empty_pipeline_handled():
    tc = TestCase(name="Empty Pipeline", steps=[])
    ut_passed, ut_total = run_unit_tests(tc)
    assert ut_passed == 0
    assert ut_total == 0

    e2e_pass, fail_step, _ = run_e2e_test(tc)
    assert e2e_pass is False
    assert fail_step == "EmptyPipeline"

    res = evaluate_test_cases([tc])
    assert res[0].unit_test_result == "FAIL"
    assert res[0].e2e_result == "FAIL"


def test_standard_scenarios_and_metrics_calculation():
    cases = get_standard_scenarios()
    results = evaluate_test_cases(cases)
    assert len(results) == 4

    metrics = calculate_metrics(results)
    assert metrics["total"] == 4
    assert metrics["false_confidence_count"] == 3
    assert metrics["false_confidence_rate"] == 0.75
