#!/usr/bin/env python3
"""
test_scope_tracker.py — Unit tests for Lecture 07 scope tracker.
"""

import json
import tempfile
from pathlib import Path
from scope_tracker import check_wip_and_evidence, load_feature_list


def test_clean_state_passes():
    features = [
        {"id": "feat-001", "name": "Task 1", "status": "done"},
        {"id": "feat-002", "name": "Task 2", "status": "pending"},
    ]
    res = check_wip_and_evidence(features)
    assert res["is_valid"] is True
    assert res["active_count"] == 0


def test_single_active_with_verification_passes():
    features = [
        {"id": "feat-001", "name": "Task 1", "status": "done"},
        {
            "id": "feat-002",
            "name": "Task 2",
            "status": "active",
            "verification": "pytest tests/test_task2.py",
        },
    ]
    res = check_wip_and_evidence(features)
    assert res["is_valid"] is True
    assert res["active_count"] == 1


def test_multiple_active_fails_wip_limit():
    features = [
        {"id": "feat-001", "name": "Task 1", "status": "active", "verification": "true"},
        {"id": "feat-002", "name": "Task 2", "status": "active", "verification": "true"},
    ]
    res = check_wip_and_evidence(features)
    assert res["is_valid"] is False
    assert any("WIP LIMIT VIOLATION" in v for v in res["violations"])


def test_active_without_verification_fails():
    features = [
        {"id": "feat-001", "name": "Task 1", "status": "active", "verification": ""},
    ]
    res = check_wip_and_evidence(features)
    assert res["is_valid"] is False
    assert any("COMPLETION EVIDENCE VIOLATION" in v for v in res["violations"])


if __name__ == "__main__":
    test_clean_state_passes()
    test_single_active_with_verification_passes()
    test_multiple_active_fails_wip_limit()
    test_active_without_verification_fails()
    print("All test_scope_tracker tests passed!")
