"""Unit tests for multi-agent team runner (feat-062)."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from team_runner import (
    ConsensusEngine,
    ConsensusVerdict,
    Decision,
    QuorumRule,
    Supervisor,
    Task,
    Vote,
    WorkerPool,
    build_demo_team,
)


def test_build_demo_team_success():
    supervisor, tasks = build_demo_team(simulate_security_flaw=False)
    result = supervisor.run_team_pipeline(tasks, quorum_rule=QuorumRule.SECURITY_VETO)
    assert result["status"] == "accepted"
    assert result["consensus"]["verdict"] == "ACCEPTED"
    assert not result["consensus"]["vetoed"]


def test_build_demo_team_security_veto():
    supervisor, tasks = build_demo_team(simulate_security_flaw=True)
    result = supervisor.run_team_pipeline(tasks, quorum_rule=QuorumRule.SECURITY_VETO)
    assert result["status"] == "rejected"
    assert result["consensus"]["verdict"] == "REJECTED"
    assert result["consensus"]["vetoed"] is True
    assert result["consensus"]["veto_by"] == "sec_auditor"


def test_quorum_majority_override():
    pool = WorkerPool()
    pool.register_worker("w1", lambda _t: {"data": 123})

    council = ConsensusEngine()
    council.add_reviewer(lambda _p: Vote("r1", "dev", Decision.APPROVE))
    council.add_reviewer(lambda _p: Vote("r2", "qa", Decision.REJECT))
    council.add_reviewer(lambda _p: Vote("r3", "lead", Decision.APPROVE))

    supervisor = Supervisor(pool, council)
    tasks = [Task("t1", "w1", "Run work")]

    result = supervisor.run_team_pipeline(tasks, quorum_rule=QuorumRule.MAJORITY)
    assert result["status"] == "accepted"
    assert result["consensus"]["verdict"] == ConsensusVerdict.ACCEPTED
    assert result["consensus"]["approve_count"] == 2
    assert result["consensus"]["reject_count"] == 1
