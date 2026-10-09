"""e2e_runner.py — E2E Pipeline Verification Harness.

Ported from learn-harness-engineering Lecture 10 (e2e-runner.ts, MIT, WalkingLab).
Evaluates the testing adequacy gap between isolated component unit tests (with mocks)
and full pipeline execution (real state propagation and component interactions).

Demonstrates four core categories of Component Boundary Defects:
1. Interface Mismatch (incompatible data schemas between upstream and downstream)
2. State Propagation Inconsistencies (asynchronous or cross-store mutation drift)
3. Resource Lifecycle Leaks (orphaned resources across stages)
4. Multi-Tenant / Environment Boundary Leakage (cache/isolation cross-talk)
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import Any, Literal

ActualBehavior = Literal["works", "fails", "partial"]


@dataclass
class PipelineStep:
    name: str
    unit_test_passes: bool
    actual_behavior: ActualBehavior
    failure_reason: str | None = None


@dataclass
class TestCase:
    __test__ = False  # Prevent pytest from treating dataclass as a test suite
    name: str
    steps: list[PipelineStep]


@dataclass
class TestResult:
    __test__ = False  # Prevent pytest from treating dataclass as a test suite
    test_case: str
    unit_tests_passed: int
    unit_tests_total: int
    unit_test_result: Literal["PASS", "FAIL"]
    e2e_result: Literal["PASS", "FAIL"]
    e2e_failure_step: str | None = None
    e2e_failure_reason: str | None = None


def run_unit_tests(tc: TestCase) -> tuple[int, int]:
    """Execute unit tests for all steps in isolation (where dependencies are mocked)."""
    passed = sum(1 for step in tc.steps if step.unit_test_passes)
    return passed, len(tc.steps)


def run_e2e_test(tc: TestCase) -> tuple[bool, str | None, str | None]:
    """Execute full pipeline end-to-end.

    If any step hard-fails, pipeline halts immediately with failure.
    If any step completes partially, downstream failure propagates.
    """
    if not tc.steps:
        return False, "EmptyPipeline", "No pipeline steps defined"

    for step in tc.steps:
        if step.actual_behavior == "fails":
            return False, step.name, step.failure_reason or "Component failure"

    # Propagate partial steps if not caught by a preceding hard failure
    partial_steps = [s for s in tc.steps if s.actual_behavior == "partial"]
    if partial_steps:
        last_partial = partial_steps[-1]
        return False, last_partial.name, last_partial.failure_reason or "Partial completion failure"

    return True, None, None


def evaluate_test_cases(cases: list[TestCase]) -> list[TestResult]:
    """Evaluate a suite of test cases across both unit and e2e layers."""
    results: list[TestResult] = []
    for tc in cases:
        ut_passed, ut_total = run_unit_tests(tc)
        e2e_pass, fail_step, fail_reason = run_e2e_test(tc)
        results.append(
            TestResult(
                test_case=tc.name,
                unit_tests_passed=ut_passed,
                unit_tests_total=ut_total,
                unit_test_result="PASS" if (ut_passed == ut_total and ut_total > 0) else "FAIL",
                e2e_result="PASS" if e2e_pass else "FAIL",
                e2e_failure_step=fail_step,
                e2e_failure_reason=fail_reason,
            )
        )
    return results


def calculate_metrics(results: list[TestResult]) -> dict[str, Any]:
    """Calculate false confidence metrics comparing Unit vs E2E outcomes."""
    total = len(results)
    if total == 0:
        return {"total": 0, "false_confidence_count": 0, "false_confidence_rate": 0.0}

    false_confidence_count = sum(
        1 for r in results if r.unit_test_result == "PASS" and r.e2e_result == "FAIL"
    )
    return {
        "total": total,
        "false_confidence_count": false_confidence_count,
        "false_confidence_rate": round(false_confidence_count / total, 4),
    }


def get_standard_scenarios() -> list[TestCase]:
    """Standard realistic pipeline scenarios demonstrating boundary defects."""
    return [
        TestCase(
            name="Document Ingestion & Citations",
            steps=[
                PipelineStep(
                    name="Parse uploaded document", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Store document chunks", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Index chunks for retrieval",
                    unit_test_passes=True,
                    actual_behavior="partial",
                    failure_reason="Embedding dimension mismatch between indexer and retriever",
                ),
                PipelineStep(
                    name="Retrieve relevant chunks",
                    unit_test_passes=True,
                    actual_behavior="fails",
                    failure_reason="Empty results due to dimension mismatch from previous step",
                ),
                PipelineStep(
                    name="Generate answer with citations",
                    unit_test_passes=True,
                    actual_behavior="fails",
                    failure_reason="No chunks retrieved, answer lacks citation provenance",
                ),
            ],
        ),
        TestCase(
            name="Document Deletion & Cache Cleanup",
            steps=[
                PipelineStep(
                    name="Find document by ID", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Delete document record", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Remove indexed chunks",
                    unit_test_passes=True,
                    actual_behavior="fails",
                    failure_reason="Index cleanup query timed out, chunks remain orphaned",
                ),
                PipelineStep(
                    name="Verify document not in search results",
                    unit_test_passes=True,
                    actual_behavior="fails",
                    failure_reason="Orphaned chunks from previous step still appear in query results",
                ),
            ],
        ),
        TestCase(
            name="Multi-User Concurrent Access",
            steps=[
                PipelineStep(
                    name="User A imports document", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="User B imports document", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="User A queries their document",
                    unit_test_passes=True,
                    actual_behavior="partial",
                    failure_reason="No tenant scoping in cache layer, returns chunks from User B",
                ),
                PipelineStep(
                    name="Verify data isolation",
                    unit_test_passes=True,
                    actual_behavior="fails",
                    failure_reason="Results leak cross-tenant documents",
                ),
            ],
        ),
        TestCase(
            name="Healthy Single-Component Flow",
            steps=[
                PipelineStep(
                    name="Input sanitization", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Payload transformation", unit_test_passes=True, actual_behavior="works"
                ),
                PipelineStep(
                    name="Emit structured event", unit_test_passes=True, actual_behavior="works"
                ),
            ],
        ),
    ]


def print_report(results: list[TestResult]) -> None:
    """Print formatted comparison report."""
    print("=" * 80)
    print("  E2E PIPELINE RUNNER: Unit Isolation vs End-to-End Integration")
    print("=" * 80)

    for r in results:
        discrepancy = r.unit_test_result == "PASS" and r.e2e_result == "FAIL"
        tag = "[DISCREPANCY: Unit PASS but E2E FAIL]" if discrepancy else "[CONSISTENT]"
        print(f"\nScenario: {r.test_case}")
        print(f"  Unit Tests : {r.unit_tests_passed}/{r.unit_tests_total} {r.unit_test_result}")
        print(f"  E2E Pipeline: {r.e2e_result}  {tag}")
        if r.e2e_failure_step:
            print(f"  Failure Step: {r.e2e_failure_step}")
            print(f"  Root Cause  : {r.e2e_failure_reason}")

    metrics = calculate_metrics(results)
    print("\n" + "-" * 80)
    print(f"Total Scenarios Evaluated: {metrics['total']}")
    print(f"False Confidence Cases (Unit PASS, E2E FAIL): {metrics['false_confidence_count']}")
    print(f"False Confidence Rate: {metrics['false_confidence_rate'] * 100:.1f}%")
    print("-" * 80)


def main() -> int:
    cases = get_standard_scenarios()
    results = evaluate_test_cases(cases)
    print_report(results)
    return 0


if __name__ == "__main__":
    sys.exit(main())
