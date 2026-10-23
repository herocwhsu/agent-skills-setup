"""Unit tests for repository workflow DAG runner (feat-060)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from graph_runner import (
    END,
    START,
    WorkflowCheckpointer,
    WorkflowGraph,
    create_maker_checker_graph,
)

REPO_ROOT = Path(__file__).resolve().parents[4]


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


def test_linear_graph_execution() -> None:
    graph = WorkflowGraph()

    def step_a(state: dict[str, Any]) -> dict[str, Any]:
        return {"val": state.get("val", 0) + 1}

    def step_b(state: dict[str, Any]) -> dict[str, Any]:
        return {"val": state["val"] * 2}

    graph.add_node("a", step_a)
    graph.add_node("b", step_b)
    graph.add_edge(START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", END)

    res = graph.invoke({"val": 5})
    assert res["val"] == 12
    assert res.get("__completed__") is True


def test_conditional_rollback_edge() -> None:
    graph = WorkflowGraph()

    def implement(state: dict[str, Any]) -> dict[str, Any]:
        attempts = state.get("attempts", 0) + 1
        # Succeeds on round 3
        code = "valid code" if attempts >= 3 else "buggy code"
        return {"code": code, "attempts": attempts}

    def verify(state: dict[str, Any]) -> dict[str, Any]:
        review = "pass" if "valid" in state["code"] else "fail"
        return {"review": review}

    def router(state: dict[str, Any]) -> str:
        return "pass" if state["review"] == "pass" else "fail"

    def merge(state: dict[str, Any]) -> dict[str, Any]:
        return {"merged": True}

    graph.add_node("implement", implement)
    graph.add_node("verify", verify)
    graph.add_node("merge", merge)

    graph.add_edge(START, "implement")
    graph.add_edge("implement", "verify")
    graph.add_conditional_edges("verify", router, {"pass": "merge", "fail": "implement"})
    graph.add_edge("merge", END)

    res = graph.invoke({"attempts": 0})
    assert res["merged"] is True
    assert res["attempts"] == 3
    assert res["review"] == "pass"


def test_max_steps_timeout() -> None:
    graph = WorkflowGraph()

    def loop_node(state: dict[str, Any]) -> dict[str, Any]:
        return {"count": state.get("count", 0) + 1}

    graph.add_node("loop", loop_node)
    graph.add_edge(START, "loop")
    graph.add_edge("loop", "loop")  # infinite loop

    res = graph.invoke({"count": 0}, max_steps=5)
    assert res.get("__max_steps_reached__") is True
    assert res.get("__completed__") is False
    assert res["count"] == 5


def test_corrupted_checkpoint_recovery(tmp_path: Path) -> None:
    checkpointer = WorkflowCheckpointer(storage_dir=tmp_path)
    # 1. Invalid JSON object instead of list
    (tmp_path / "thread-corrupt-1.json").write_text("{}", encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-1") is None

    # 2. List of primitives instead of dicts
    (tmp_path / "thread-corrupt-2.json").write_text("[1, 2, 3]", encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-2") is None

    # 3. Dict without 'state' key
    (tmp_path / "thread-corrupt-3.json").write_text('[{"other": 1}]', encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-3") is None
