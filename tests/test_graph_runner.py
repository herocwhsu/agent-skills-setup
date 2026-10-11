"""Unit tests for repository workflow DAG runner (feat-060)."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from graph_runner import (
    END,
    START,
    WorkflowCheckpointer,
    WorkflowGraph,
    create_maker_checker_graph,
)


def test_maker_checker_graph_flow() -> None:
    graph = create_maker_checker_graph(REPO_ROOT)
    # Simulate 2 verification failures before passing
    initial_state = {
        "problem": "Fix race condition in session handoff",
        "simulated_fail_count": 2,
    }
    res = graph.invoke(initial_state, thread_id="test-thread-1")
    assert res.get("__completed__") is True
    assert res.get("attempts") == 3
    assert res.get("review") == "pass"
    assert res.get("merged") is True
    assert res.get("phase") == "merged"


def test_checkpointer_disk_persistence(tmp_path: Path) -> None:
    cp = WorkflowCheckpointer(storage_dir=tmp_path)
    graph = WorkflowGraph()

    def node_a(state: dict[str, Any]) -> dict[str, Any]:
        return {"step_a": True, "data": "alpha"}

    def node_b(state: dict[str, Any]) -> dict[str, Any]:
        return {"step_b": True, "data": state["data"] + "_beta"}

    graph.add_node("a", node_a)
    graph.add_node("b", node_b)
    graph.add_edge(START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", END)

    res = graph.invoke({}, thread_id="disk-test", checkpointer=cp)
    assert res.get("__completed__") is True
    assert res["data"] == "alpha_beta"

    # Verify JSON file created on disk
    saved_file = tmp_path / "disk-test.json"
    assert saved_file.is_file()
    latest = cp.get_latest("disk-test")
    assert latest is not None
    assert latest["data"] == "alpha_beta"


def test_human_approval_pause_and_resume() -> None:
    graph = WorkflowGraph()

    def work(state: dict[str, Any]) -> dict[str, Any]:
        return {"work_done": True}

    def deploy(state: dict[str, Any]) -> dict[str, Any]:
        return {"deployed": True}

    graph.add_node("work", work)
    graph.add_node("deploy", deploy)
    graph.add_edge(START, "work")
    graph.add_edge("work", "deploy")
    graph.add_edge("deploy", END)

    # Pause before deploy
    graph.pause_before("deploy")

    # Step 1: Pauses before deploy
    res1 = graph.invoke({}, thread_id="deploy-thread")
    assert res1.get("__interrupted__") is True
    assert res1.get("__paused_at__") == "deploy"
    assert res1.get("deployed") is None

    # Step 2: Resume with approval
    res2 = graph.invoke({"__human_decision__": "approved"}, thread_id="deploy-thread")
    assert res2.get("__completed__") is True
    assert res2.get("deployed") is True
