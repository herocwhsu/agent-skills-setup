"""Unit tests for multi-agent team runner (feat-062)."""

from __future__ import annotations

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


def test_worker_pool_execution():
    pool = WorkerPool()
    pool.register_worker("coder", lambda task: {"code": "def hello(): pass", "lines": 1})

    task = Task(task_id="t1", role_required="coder", prompt="Write hello function")
    res = pool.execute_task(task)

    assert res.status == "completed"
    assert res.output["lines"] == 1
    assert res.duration_ms >= 0.0
    assert res.error is None


def test_worker_pool_missing_role():
    pool = WorkerPool()
    task = Task(task_id="t1", role_required="designer", prompt="Design UI")
    res = pool.execute_task(task)

    assert res.status == "failed"
    assert "No worker registered" in (res.error or "")


def test_worker_pool_exception_handling():
    pool = WorkerPool()

    def buggy_worker(_task):
        raise ValueError("Simulated crash")

    pool.register_worker("tester", buggy_worker)
    task = Task(task_id="t2", role_required="tester", prompt="Run tests")
    res = pool.execute_task(task)

    assert res.status == "failed"
    assert res.error == "Simulated crash"


def test_consensus_empty_reviewers():
    engine = ConsensusEngine()
    result = engine.evaluate_proposal({"diff": "sample"})
    assert result.verdict == ConsensusVerdict.NO_QUORUM
    assert result.total_votes == 0


def test_consensus_majority_rule():
    engine = ConsensusEngine()
    engine.add_reviewer(lambda _p: Vote("r1", "architect", Decision.APPROVE, rationale="Clean"))
    engine.add_reviewer(lambda _p: Vote("r2", "reviewer", Decision.APPROVE, rationale="Looks good"))
    engine.add_reviewer(lambda _p: Vote("r3", "qa", Decision.REJECT, rationale="Edge case bug"))

    result = engine.evaluate_proposal({}, rule=QuorumRule.MAJORITY)
    assert result.verdict == ConsensusVerdict.ACCEPTED
    assert result.approve_count == 2
    assert result.reject_count == 1
    assert not result.vetoed


def test_consensus_unanimous_rule():
    engine = ConsensusEngine()
    engine.add_reviewer(lambda _p: Vote("r1", "lead", Decision.APPROVE))
    engine.add_reviewer(lambda _p: Vote("r2", "dev", Decision.REJECT))

    result = engine.evaluate_proposal({}, rule=QuorumRule.UNANIMOUS)
    assert result.verdict == ConsensusVerdict.REJECTED


def test_consensus_security_veto_power():
    engine = ConsensusEngine()
    # 2 developers approve
    engine.add_reviewer(lambda _p: Vote("dev1", "coder", Decision.APPROVE))
    engine.add_reviewer(lambda _p: Vote("dev2", "coder", Decision.APPROVE))
    # Security auditor vetoes
    engine.add_reviewer(
        lambda _p: Vote(
            "sec1",
            "security",
            Decision.REJECT,
            has_veto_power=True,
            rationale="Hardcoded token found",
        )
    )

    result = engine.evaluate_proposal({}, rule=QuorumRule.SECURITY_VETO)
    assert result.verdict == ConsensusVerdict.REJECTED
    assert result.vetoed is True
    assert result.veto_by == "sec1"
    assert result.approve_count == 2
    assert result.reject_count == 1


def test_supervisor_full_pipeline_success():
    pool = WorkerPool()
    pool.register_worker("planner", lambda _t: {"plan": "3 steps"})
    pool.register_worker("coder", lambda _t: {"code": "print('ok')"})

    council = ConsensusEngine()
    council.add_reviewer(
        lambda _p: Vote("auditor", "checker", Decision.APPROVE, has_veto_power=True)
    )

    supervisor = Supervisor(pool, council)
    tasks = [
        Task("t1", "planner", "Plan work"),
        Task("t2", "coder", "Write code"),
    ]

    res = supervisor.run_team_pipeline(tasks, quorum_rule=QuorumRule.SECURITY_VETO)
    assert res["status"] == "accepted"
    assert "t1" in res["task_results"]
    assert "t2" in res["task_results"]
    assert res["consensus"]["verdict"] == "ACCEPTED"


def test_supervisor_pipeline_worker_failure():
    pool = WorkerPool()
    supervisor = Supervisor(pool)
    tasks = [Task("t1", "nonexistent", "Do work")]

    res = supervisor.run_team_pipeline(tasks)
    assert res["status"] == "failed"
    assert res["failed_task"] == "t1"
    assert res["consensus"] is None


def test_reviewer_exception_handled_as_abstain():
    engine = ConsensusEngine()

    def bad_reviewer(_p):
        raise RuntimeError("Reviewer model timed out")

    engine.add_reviewer(bad_reviewer)
    engine.add_reviewer(lambda _p: Vote("r2", "auditor", Decision.APPROVE))

    result = engine.evaluate_proposal({}, rule=QuorumRule.MAJORITY)
    assert result.verdict == ConsensusVerdict.ACCEPTED
    assert result.approve_count == 1
    assert result.abstain_count == 1
    assert result.votes[0].decision == Decision.ABSTAIN
    assert "Reviewer execution exception" in result.votes[0].rationale


def test_worker_timeout_handling():
    import time

    pool = WorkerPool()

    def slow_worker(_t):
        time.sleep(0.02)
        return {"done": True}

    pool.register_worker("slow", slow_worker)
    # Set timeout to 0.005 seconds (5ms)
    task = Task("t_slow", "slow", "Do heavy work", timeout_sec=0.005)
    res = pool.execute_task(task)

    assert res.status == "timeout"
    assert "exceeded timeout budget" in (res.error or "")


def test_worker_non_dict_output_wrapping():
    pool = WorkerPool()
    pool.register_worker("raw", lambda _t: "plain string result")
    task = Task("t_raw", "raw", "Return text")
    res = pool.execute_task(task)

    assert res.status == "completed"
    assert res.output == {"data": "plain string result"}


def test_supervisor_no_quorum_status():
    pool = WorkerPool()
    pool.register_worker("w1", lambda _t: {"ok": True})
    council = ConsensusEngine()
    # No reviewers added -> NO_QUORUM
    supervisor = Supervisor(pool, council)
    res = supervisor.run_team_pipeline([Task("t1", "w1", "run")])

    assert res["status"] == "no_quorum"
    assert res["consensus"]["verdict"] == "NO_QUORUM"


def test_multiple_veto_reviewers_attribution():
    engine = ConsensusEngine()
    engine.add_reviewer(lambda _p: Vote("sec1", "sec", Decision.REJECT, has_veto_power=True))
    engine.add_reviewer(lambda _p: Vote("sec2", "sec", Decision.REJECT, has_veto_power=True))

    result = engine.evaluate_proposal({}, rule=QuorumRule.SECURITY_VETO)
    assert result.verdict == ConsensusVerdict.REJECTED
    assert result.vetoed is True
    assert "sec1" in (result.veto_by or "")
    assert "sec2" in (result.veto_by or "")
