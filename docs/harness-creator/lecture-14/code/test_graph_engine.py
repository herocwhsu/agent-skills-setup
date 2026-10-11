"""Unit tests for Lecture 14 Graph Engine (graph_engine.py)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from graph_engine import END, START, Checkpointer, StateGraph


def test_linear_graph_execution() -> None:
    graph = StateGraph()

    def step_a(state: dict[str, Any]) -> dict[str, Any]:
        return {"val": state.get("val", 0) + 1}

    def step_b(state: dict[str, Any]) -> dict[str, Any]:
        return {"val": state["val"] * 2}

    graph.add_node("a", step_a)
    graph.add_node("b", step_b)
    graph.add_edge(START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", END)

    app = graph.compile()
    res = app.invoke({"val": 5})
    assert res["val"] == 12
    assert res.get("__completed__") is True


def test_conditional_rollback_edge() -> None:
    graph = StateGraph()

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

    app = graph.compile()
    res = app.invoke({"attempts": 0})
    assert res["merged"] is True
    assert res["attempts"] == 3
    assert res["review"] == "pass"


def test_checkpointer_persistence_and_resume(tmp_path: Path) -> None:
    checkpointer = Checkpointer(storage_dir=tmp_path)
    graph = StateGraph()

    def step_one(state: dict[str, Any]) -> dict[str, Any]:
        return {"count": 1}

    def step_two(state: dict[str, Any]) -> dict[str, Any]:
        return {"count": state["count"] + 10}

    graph.add_node("one", step_one)
    graph.add_node("two", step_two)
    graph.add_edge(START, "one")
    graph.add_edge("one", "two")
    graph.add_edge("two", END)

    # Flag human approval before 'two'
    graph.pause_before("two")

    app = graph.compile(checkpointer=checkpointer)

    # Run 1: Should halt at 'two'
    res1 = app.invoke({"count": 0}, config={"configurable": {"thread_id": "thread-1"}})
    assert res1.get("__interrupted__") is True
    assert res1.get("__paused_at__") == "two"
    assert res1["count"] == 1

    # Run 2: Resume with human approval
    res2 = app.invoke(
        {"__human_decision__": "approved"},
        config={"configurable": {"thread_id": "thread-1"}},
    )
    assert res2.get("__completed__") is True
    assert res2["count"] == 11


def test_max_steps_timeout() -> None:
    graph = StateGraph()

    def loop_node(state: dict[str, Any]) -> dict[str, Any]:
        return {"count": state.get("count", 0) + 1}

    graph.add_node("loop", loop_node)
    graph.add_edge(START, "loop")
    graph.add_edge("loop", "loop")  # infinite loop

    app = graph.compile()
    res = app.invoke({"count": 0}, max_steps=5)
    assert res.get("__max_steps_reached__") is True
    assert res.get("__completed__") is False
    assert res["count"] == 5


def test_corrupted_checkpoint_recovery(tmp_path: Path) -> None:
    checkpointer = Checkpointer(storage_dir=tmp_path)
    # 1. Invalid JSON object instead of list
    (tmp_path / "thread-corrupt-1.json").write_text("{}", encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-1") is None

    # 2. List of primitives instead of dicts
    (tmp_path / "thread-corrupt-2.json").write_text("[1, 2, 3]", encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-2") is None

    # 3. Dict without 'state' key
    (tmp_path / "thread-corrupt-3.json").write_text("[{\"other\": 1}]", encoding="utf-8")
    assert checkpointer.get_latest("thread-corrupt-3") is None

