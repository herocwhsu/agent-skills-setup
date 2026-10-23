#!/usr/bin/env python3
"""Multi-Agent Team Topologies & Consensus Orchestration Runner (feat-062).

Coordinates multi-agent workflows across:
- Hierarchical Supervisor (Task planning & aggregation)
- Dynamic Worker Pools (Isolated contexts, specialized execution)
- Consensus Engine (Multi-role review councils with quorum & veto power)

References:
- Lecture 15: Multi-Agent Team Topologies (docs/harness-creator/lecture-15/)
"""

from __future__ import annotations

import argparse
import enum
import json
import sys
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


class QuorumRule(str, enum.Enum):
    """Quorum evaluation rules for multi-role consensus."""

    MAJORITY = "majority"
    UNANIMOUS = "unanimous"
    SECURITY_VETO = "security_veto"


class Decision(str, enum.Enum):
    """Individual reviewer decision."""

    APPROVE = "APPROVE"
    REJECT = "REJECT"
    ABSTAIN = "ABSTAIN"


class ConsensusVerdict(str, enum.Enum):
    """Consensus outcome."""

    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    NO_QUORUM = "NO_QUORUM"


@dataclass
class Task:
    """A unit of work dispatched to a worker."""

    task_id: str
    role_required: str
    prompt: str
    payload: dict[str, Any] = field(default_factory=dict)
    timeout_sec: float = 30.0


@dataclass
class TaskResult:
    """Outcome of an executed task."""

    task_id: str
    status: str  # "completed", "failed", "timeout"
    output: dict[str, Any] = field(default_factory=dict)
    error: str | None = None
    duration_ms: float = 0.0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class Vote:
    """Single reviewer evaluation."""

    reviewer_id: str
    role: str
    decision: Decision
    confidence: float = 1.0
    rationale: str = ""
    has_veto_power: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "reviewer_id": self.reviewer_id,
            "role": self.role,
            "decision": self.decision.value,
            "confidence": self.confidence,
            "rationale": self.rationale,
            "has_veto_power": self.has_veto_power,
        }


@dataclass
class ConsensusResult:
    """Consensus tally outcome."""

    verdict: ConsensusVerdict
    quorum_rule: QuorumRule
    approve_count: int
    reject_count: int
    abstain_count: int
    total_votes: int
    vetoed: bool
    veto_by: str | None = None
    votes: list[Vote] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "verdict": self.verdict.value,
            "quorum_rule": self.quorum_rule.value,
            "approve_count": self.approve_count,
            "reject_count": self.reject_count,
            "abstain_count": self.abstain_count,
            "total_votes": self.total_votes,
            "vetoed": self.vetoed,
            "veto_by": self.veto_by,
            "votes": [v.to_dict() for v in self.votes],
        }


WorkerHandler = Callable[[Task], dict[str, Any]]
ReviewerHandler = Callable[[dict[str, Any]], Vote]


class WorkerPool:
    """Dynamic pool of specialized workers with isolated execution."""

    def __init__(self) -> None:
        self._handlers: dict[str, WorkerHandler] = {}

    def register_worker(self, role: str, handler: WorkerHandler) -> None:
        """Register a handler for a given worker role."""
        self._handlers[role] = handler

    def execute_task(self, task: Task) -> TaskResult:
        """Execute a task in isolated scope with error and duration tracking."""
        handler = self._handlers.get(task.role_required)
        if not handler:
            return TaskResult(
                task_id=task.task_id,
                status="failed",
                error=f"No worker registered for role '{task.role_required}'",
            )

        start_time = time.perf_counter()
        try:
            raw_output = handler(task)
            duration_ms = (time.perf_counter() - start_time) * 1000

            if duration_ms > (task.timeout_sec * 1000):
                return TaskResult(
                    task_id=task.task_id,
                    status="timeout",
                    error=f"Task exceeded timeout budget ({duration_ms:.1f}ms > {task.timeout_sec * 1000:.1f}ms)",
                    duration_ms=round(duration_ms, 2),
                )

            output = raw_output if isinstance(raw_output, dict) else {"data": raw_output}
            return TaskResult(
                task_id=task.task_id,
                status="completed",
                output=output,
                duration_ms=round(duration_ms, 2),
            )
        except Exception as exc:  # noqa: BLE001
            duration_ms = (time.perf_counter() - start_time) * 1000
            return TaskResult(
                task_id=task.task_id,
                status="failed",
                error=str(exc),
                duration_ms=round(duration_ms, 2),
            )


class ConsensusEngine:
    """Multi-role voting engine evaluating proposals under formal quorum rules."""

    def __init__(self) -> None:
        self._reviewers: list[ReviewerHandler] = []

    def add_reviewer(self, reviewer: ReviewerHandler) -> None:
        """Add a reviewer to the council."""
        self._reviewers.append(reviewer)

    def evaluate_proposal(
        self,
        proposal: dict[str, Any],
        rule: QuorumRule = QuorumRule.MAJORITY,
    ) -> ConsensusResult:
        """Gather votes from reviewers and calculate quorum verdict."""
        votes: list[Vote] = []
        for reviewer in self._reviewers:
            try:
                vote = reviewer(proposal)
            except Exception as exc:  # noqa: BLE001
                vote = Vote(
                    reviewer_id="reviewer_error",
                    role="reviewer_exception",
                    decision=Decision.ABSTAIN,
                    confidence=0.0,
                    rationale=f"Reviewer execution exception: {exc}",
                )
            votes.append(vote)

        if not votes:
            return ConsensusResult(
                verdict=ConsensusVerdict.NO_QUORUM,
                quorum_rule=rule,
                approve_count=0,
                reject_count=0,
                abstain_count=0,
                total_votes=0,
                vetoed=False,
                votes=[],
            )

        approve_count = sum(1 for v in votes if v.decision == Decision.APPROVE)
        reject_count = sum(1 for v in votes if v.decision == Decision.REJECT)
        abstain_count = sum(1 for v in votes if v.decision == Decision.ABSTAIN)
        total_valid = approve_count + reject_count

        # Check for Veto Power first
        veto_voters = [
            v for v in votes if v.has_veto_power and v.decision == Decision.REJECT
        ]
        if rule == QuorumRule.SECURITY_VETO and veto_voters:
            veto_by_str = ", ".join(v.reviewer_id for v in veto_voters)
            return ConsensusResult(
                verdict=ConsensusVerdict.REJECTED,
                quorum_rule=rule,
                approve_count=approve_count,
                reject_count=reject_count,
                abstain_count=abstain_count,
                total_votes=len(votes),
                vetoed=True,
                veto_by=veto_by_str,
                votes=votes,
            )

        # Quorum evaluation
        if rule == QuorumRule.UNANIMOUS:
            if approve_count == len(votes) and reject_count == 0:
                verdict = ConsensusVerdict.ACCEPTED
            else:
                verdict = ConsensusVerdict.REJECTED
        elif rule in (QuorumRule.MAJORITY, QuorumRule.SECURITY_VETO):
            if total_valid == 0:
                verdict = ConsensusVerdict.NO_QUORUM
            elif approve_count > reject_count:
                verdict = ConsensusVerdict.ACCEPTED
            else:
                verdict = ConsensusVerdict.REJECTED
        else:
            verdict = ConsensusVerdict.NO_QUORUM

        return ConsensusResult(
            verdict=verdict,
            quorum_rule=rule,
            approve_count=approve_count,
            reject_count=reject_count,
            abstain_count=abstain_count,
            total_votes=len(votes),
            vetoed=False,
            votes=votes,
        )


class Supervisor:
    """Hierarchical supervisor orchestrating task delegation and consensus gates."""

    def __init__(
        self,
        worker_pool: WorkerPool,
        consensus_engine: ConsensusEngine | None = None,
    ) -> None:
        self.pool = worker_pool
        self.consensus = consensus_engine or ConsensusEngine()

    def run_team_pipeline(
        self,
        tasks: list[Task],
        quorum_rule: QuorumRule = QuorumRule.SECURITY_VETO,
    ) -> dict[str, Any]:
        """Dispatch tasks to worker pool, aggregate outputs, and gate via consensus."""
        results: dict[str, TaskResult] = {}
        proposal_payload: dict[str, Any] = {}

        for task in tasks:
            result = self.pool.execute_task(task)
            results[task.task_id] = result
            if result.status == "completed":
                proposal_payload[task.task_id] = result.output
            else:
                return {
                    "status": "failed",
                    "failed_task": task.task_id,
                    "error": result.error,
                    "task_results": {k: v.to_dict() for k, v in results.items()},
                    "consensus": None,
                }

        # Subject aggregated proposal to multi-role consensus
        consensus_result = self.consensus.evaluate_proposal(
            proposal_payload, rule=quorum_rule
        )

        if consensus_result.verdict == ConsensusVerdict.ACCEPTED:
            team_status = "accepted"
        elif consensus_result.verdict == ConsensusVerdict.NO_QUORUM:
            team_status = "no_quorum"
        else:
            team_status = "rejected"

        return {
            "status": team_status,
            "task_results": {k: v.to_dict() for k, v in results.items()},
            "consensus": consensus_result.to_dict(),
        }


def build_demo_team(simulate_security_flaw: bool = False) -> tuple[Supervisor, list[Task]]:
    """Build a standard 3-worker pool and 3-reviewer consensus council demo."""
    pool = WorkerPool()

    # Worker 1: Scoping / Research
    pool.register_worker(
        "researcher",
        lambda t: {
            "findings": "Scope identified 2 API endpoints",
            "files_to_touch": ["src/api.py"],
        },
    )

    # Worker 2: Implementation
    def coder_fn(t: Task) -> dict[str, Any]:
        code = "def authenticate(): pass"
        if simulate_security_flaw:
            code += "\nAPI_KEY = 'hardcoded-secret-123'"
        return {"code": code, "lines": len(code.splitlines())}

    pool.register_worker("coder", coder_fn)

    # Worker 3: QA / Test scaffolding
    pool.register_worker(
        "tester",
        lambda t: {"test_file": "tests/test_api.py", "assertions": 3},
    )

    # Consensus Council: 3 Reviewers
    council = ConsensusEngine()

    # Reviewer 1: Architecture Reviewer
    council.add_reviewer(
        lambda p: Vote(
            reviewer_id="architect",
            role="Domain Architect",
            decision=Decision.APPROVE,
            rationale="Adheres to clean architecture boundaries",
        )
    )

    # Reviewer 2: Security Auditor (Holds Veto Power)
    def security_reviewer(proposal: dict[str, Any]) -> Vote:
        coder_out = proposal.get("task_code", {}).get("code", "")
        if "hardcoded" in coder_out or "secret" in coder_out:
            return Vote(
                reviewer_id="sec_auditor",
                role="Security Auditor",
                decision=Decision.REJECT,
                rationale="Hardcoded credential or secret detected in code payload",
                has_veto_power=True,
            )
        return Vote(
            reviewer_id="sec_auditor",
            role="Security Auditor",
            decision=Decision.APPROVE,
            rationale="No secret or injection vulnerabilities detected",
            has_veto_power=True,
        )

    council.add_reviewer(security_reviewer)

    # Reviewer 3: QA Verification Checker
    council.add_reviewer(
        lambda p: Vote(
            reviewer_id="qa_checker",
            role="QA Reviewer",
            decision=Decision.APPROVE,
            rationale="Automated test suite covers all modified endpoints",
        )
    )

    supervisor = Supervisor(pool, council)
    tasks = [
        Task(task_id="task_research", role_required="researcher", prompt="Scan API surface"),
        Task(task_id="task_code", role_required="coder", prompt="Generate implementation"),
        Task(task_id="task_test", role_required="tester", prompt="Scaffold unit tests"),
    ]

    return supervisor, tasks


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Multi-Agent Team Topologies & Consensus Orchestration Runner (feat-062)"
    )
    parser.add_argument("--demo", action="store_true", help="Run simulated team pipeline")
    parser.add_argument(
        "--simulate-flaw",
        action="store_true",
        help="Simulate security flaw in demo to trigger veto gate",
    )
    parser.add_argument(
        "--rule",
        choices=["majority", "unanimous", "security_veto"],
        default="security_veto",
        help="Consensus quorum rule (default: security_veto)",
    )
    parser.add_argument("--config", type=Path, help="Path to custom team configuration JSON")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")

    args = parser.parse_args()

    quorum_rule = QuorumRule(args.rule)

    if args.demo or not args.config:
        supervisor, tasks = build_demo_team(simulate_security_flaw=args.simulate_flaw)
        result = supervisor.run_team_pipeline(tasks, quorum_rule=quorum_rule)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print(f"=== Multi-Agent Team Execution: {result['status'].upper()} ===")
            print(f"Quorum Rule: {quorum_rule.value}")
            print(f"Tasks Executed: {len(result['task_results'])}")
            for tid, tr in result["task_results"].items():
                print(f"  • [{tr['status'].upper()}] {tid} ({tr['duration_ms']}ms)")

            consensus = result.get("consensus")
            if consensus:
                print(f"\nConsensus Verdict: {consensus['verdict']}")
                print(
                    f"Votes: {consensus['approve_count']} APPROVE / "
                    f"{consensus['reject_count']} REJECT / "
                    f"{consensus['abstain_count']} ABSTAIN"
                )
                if consensus["vetoed"]:
                    print(f"⛔ VETO TRIGGERED by: {consensus['veto_by']}")
                for v in consensus["votes"]:
                    veto_tag = " [VETO POWER]" if v["has_veto_power"] else ""
                    print(f"  - [{v['decision']}] {v['reviewer_id']} ({v['role']}){veto_tag}: {v['rationale']}")

        return 0 if result["status"] == "accepted" else 1

    print("Config mode not yet implemented", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
