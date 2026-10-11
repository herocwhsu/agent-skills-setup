#!/usr/bin/env python3
"""Multi-Agent Workflow DAG & State Machine Runner (feat-060).

Executes development workflows defined as explicit graphs:
- Nodes: work units (research, implement, verify, approve, merge)
- Edges: direct handoffs, conditional branching, and rollback routes
- State: disk-persisted shared workspace with checkpointer
- Interrupt: human-in-the-loop pauses before critical actions

Reference:
- Lecture 14: Graph Engineering (docs/harness-creator/lecture-14/)
- Anthropic: Building Effective Agents (Dec 2024)
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

START = "__START__"
END = "__END__"


class WorkflowCheckpointer:
    """Manages disk-backed checkpoint state per thread/session."""

    def __init__(self, storage_dir: Path | None = None) -> None:
        self.storage_dir = storage_dir
        self._memory_store: dict[str, list[dict[str, Any]]] = {}
        if self.storage_dir:
            self.storage_dir.mkdir(parents=True, exist_ok=True)

    def save(self, thread_id: str, step: int, node_name: str, state: dict[str, Any]) -> None:
        record = {
            "thread_id": thread_id,
            "step": step,
            "node": node_name,
            "state": copy.deepcopy(state),
        }
        if thread_id not in self._memory_store:
            self._memory_store[thread_id] = []
        self._memory_store[thread_id].append(record)

        if self.storage_dir:
            file_path = self.storage_dir / f"{thread_id}.json"
            try:
                file_path.write_text(json.dumps(self._memory_store[thread_id], indent=2), encoding="utf-8")
            except OSError:
                pass

    def get_latest(self, thread_id: str) -> dict[str, Any] | None:
        records = self._memory_store.get(thread_id)
        if records:
            return records[-1]["state"]

        if self.storage_dir:
            file_path = self.storage_dir / f"{thread_id}.json"
            if file_path.is_file():
                try:
                    data = json.loads(file_path.read_text(encoding="utf-8"))
                    if isinstance(data, list) and data and isinstance(data[-1], dict) and "state" in data[-1]:
                        return data[-1]["state"]
                except (json.JSONDecodeError, OSError, KeyError, TypeError, IndexError):
                    return None
        return None


class WorkflowGraph:
    """DAG state machine orchestrating nodes and conditional rollback edges."""

    def __init__(self) -> None:
        self.nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {}
        self.edges: dict[str, str] = {}
        self.conditional_edges: dict[str, tuple[Callable[[dict[str, Any]], str], dict[str, str]]] = {}
        self.pause_nodes: set[str] = set()

    def add_node(self, name: str, func: Callable[[dict[str, Any]], dict[str, Any]]) -> None:
        if name in (START, END):
            raise ValueError(f"Cannot use reserved name '{name}' as a node")
        self.nodes[name] = func

    def add_edge(self, source: str, target: str) -> None:
        if source != START and source not in self.nodes:
            raise KeyError(f"Source node '{source}' not registered in graph")
        if target != END and target not in self.nodes:
            raise KeyError(f"Target node '{target}' not registered in graph")
        self.edges[source] = target

    def add_conditional_edges(
        self,
        source: str,
        router: Callable[[dict[str, Any]], str],
        path_map: dict[str, str],
    ) -> None:
        if source not in self.nodes:
            raise KeyError(f"Source node '{source}' not registered in graph")
        for target in path_map.values():
            if target != END and target not in self.nodes:
                raise KeyError(f"Target node '{target}' not registered in graph")
        self.conditional_edges[source] = (router, path_map)

    def pause_before(self, node_name: str) -> None:
        self.pause_nodes.add(node_name)

    def invoke(
        self,
        initial_state: dict[str, Any],
        thread_id: str = "default",
        checkpointer: WorkflowCheckpointer | None = None,
        max_steps: int = 50,
    ) -> dict[str, Any]:
        cp = checkpointer or WorkflowCheckpointer()

        saved_state = cp.get_latest(thread_id)
        if saved_state:
            current_state = copy.deepcopy(saved_state)
            current_state.update(initial_state)
        else:
            current_state = copy.deepcopy(initial_state)

        if current_state.get("__interrupted__") and current_state.get("__paused_at__"):
            current_node = current_state["__paused_at__"]
        elif START in self.edges:
            current_node = self.edges[START]
        else:
            raise RuntimeError("Graph must have an edge originating from START")

        step = 0
        while current_node != END and step < max_steps:
            step += 1

            if current_node in self.pause_nodes:
                if current_state.get("__human_decision__") != "approved":
                    current_state["__interrupted__"] = True
                    current_state["__paused_at__"] = current_node
                    cp.save(thread_id, step, current_node, current_state)
                    return current_state
                current_state.pop("__human_decision__", None)
                current_state["__interrupted__"] = False

            node_fn = self.nodes[current_node]
            node_output = node_fn(current_state)
            if isinstance(node_output, dict):
                current_state.update(node_output)

            cp.save(thread_id, step, current_node, current_state)

            if current_node in self.conditional_edges:
                router, path_map = self.conditional_edges[current_node]
                route_key = router(current_state)
                if route_key not in path_map:
                    raise KeyError(f"Router returned '{route_key}' which is not in path_map {list(path_map.keys())}")
                current_node = path_map[route_key]
            elif current_node in self.edges:
                current_node = self.edges[current_node]
            else:
                current_node = END

        if step >= max_steps and current_node != END:
            current_state["__max_steps_reached__"] = True
            current_state["__completed__"] = False
        else:
            current_state["__completed__"] = (current_node == END)

        return current_state


def create_maker_checker_graph(repo_dir: Path) -> WorkflowGraph:
    """Constructs the canonical 4-node automated Maker-Checker development sub-graph."""
    graph = WorkflowGraph()

    def research_node(state: dict[str, Any]) -> dict[str, Any]:
        problem = state.get("problem", "Generic task")
        requirements = state.get("requirements") or f"Specification for {problem}"
        return {"requirements": requirements, "phase": "researched"}

    def implement_node(state: dict[str, Any]) -> dict[str, Any]:
        attempts = state.get("attempts", 0) + 1
        return {"code_ready": True, "attempts": attempts, "phase": "implemented"}

    def verify_node(state: dict[str, Any]) -> dict[str, Any]:
        # If simulated fail_count specified, fail until that count reached
        fail_count = state.get("simulated_fail_count", 0)
        attempts = state.get("attempts", 1)
        if attempts <= fail_count:
            return {"review": "fail", "feedback": f"Review failed on attempt {attempts}"}
        return {"review": "pass", "feedback": "Code approved by independent checker"}

    def verify_router(state: dict[str, Any]) -> str:
        return "pass" if state.get("review") == "pass" else "fail"

    def merge_node(state: dict[str, Any]) -> dict[str, Any]:
        return {"merged": True, "phase": "merged"}

    graph.add_node("research", research_node)
    graph.add_node("implement", implement_node)
    graph.add_node("verify", verify_node)
    graph.add_node("merge", merge_node)

    graph.add_edge(START, "research")
    graph.add_edge("research", "implement")
    graph.add_edge("implement", "verify")
    graph.add_conditional_edges("verify", verify_router, {"pass": "merge", "fail": "implement"})
    graph.add_edge("merge", END)

    return graph


def main() -> int:
    parser = argparse.ArgumentParser(description="Multi-Agent Workflow DAG & State Machine Runner (feat-060)")
    parser.add_argument("--demo", action="store_true", help="Run a demonstration Maker-Checker graph")
    parser.add_argument("--thread-id", type=str, default="demo-session", help="Thread ID for checkpointer")
    parser.add_argument("--repo-dir", type=Path, help="Target repository directory")
    parser.add_argument("--fails", type=int, default=1, help="Simulate N failures before verify passes")
    args = parser.parse_args()

    repo_dir = args.repo_dir or Path.cwd()

    if args.demo:
        print("=== Multi-Agent Workflow DAG Demonstration (Lecture 14) ===")
        graph = create_maker_checker_graph(repo_dir)
        checkpointer = WorkflowCheckpointer()

        initial_state = {
            "problem": "Implement feature X with rollback resilience",
            "simulated_fail_count": args.fails,
        }

        print(f"Starting graph execution (thread: {args.thread_id}, simulated fails: {args.fails})...")
        res = graph.invoke(initial_state, thread_id=args.thread_id, checkpointer=checkpointer)

        print("\n=== Graph Execution Completed ===")
        print(f"Final Phase: {res.get('phase')}")
        print(f"Review Verdict: {res.get('review')}")
        print(f"Total Attempts (including rollbacks): {res.get('attempts')}")
        print(f"Merged: {res.get('merged')}")
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
