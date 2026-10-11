#!/usr/bin/env python3
"""Zero-dependency StateGraph engine for multi-agent workflows (Lecture 14).

Provides core primitives of Graph Engineering:
- StateGraph: Node registration, linear and conditional edge routing.
- Shared State: Typed dictionary with reducer support.
- Checkpointer: In-memory and disk persistence for checkpoint replayability.
- Interrupt / Human-in-the-loop: Pause execution before specified nodes.
"""

from __future__ import annotations

import copy
import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

START = "__START__"
END = "__END__"


class Checkpointer:
    """Checkpointer that records state snapshots per thread id."""

    def __init__(self, storage_dir: Path | None = None) -> None:
        self.storage_dir = storage_dir
        self._memory_store: dict[str, list[dict[str, Any]]] = {}
        if self.storage_dir:
            self.storage_dir.mkdir(parents=True, exist_ok=True)

    def save(self, thread_id: str, step: int, node_name: str, state: dict[str, Any]) -> None:
        """Save a snapshot of the current state."""
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
        """Retrieve the latest checkpoint state for a thread."""
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


class StateGraph:
    """StateGraph orchestrating multi-agent workflow nodes and edges."""

    def __init__(self, state_schema: type | None = None) -> None:
        self.state_schema = state_schema
        self.nodes: dict[str, Callable[[dict[str, Any]], dict[str, Any]]] = {}
        self.edges: dict[str, str] = {}
        self.conditional_edges: dict[str, tuple[Callable[[dict[str, Any]], str], dict[str, str]]] = {}
        self.pause_nodes: set[str] = set()

    def add_node(self, name: str, func: Callable[[dict[str, Any]], dict[str, Any]]) -> None:
        """Register a work unit node."""
        if name in (START, END):
            raise ValueError(f"Cannot use reserved name '{name}' as a node")
        self.nodes[name] = func

    def add_edge(self, source: str, target: str) -> None:
        """Register a direct linear edge between nodes."""
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
        """Register a conditional branching edge driven by a routing function."""
        if source not in self.nodes:
            raise KeyError(f"Source node '{source}' not registered in graph")
        for target in path_map.values():
            if target != END and target not in self.nodes:
                raise KeyError(f"Target node '{target}' not registered in graph")
        self.conditional_edges[source] = (router, path_map)

    def pause_before(self, node_name: str) -> None:
        """Flag a node to interrupt execution for human approval before running."""
        self.pause_nodes.add(node_name)

    def compile(self, checkpointer: Checkpointer | None = None) -> CompiledGraph:
        """Compile the graph into an executable runner."""
        return CompiledGraph(self, checkpointer=checkpointer)


class CompiledGraph:
    """Compiled executable instance of a StateGraph."""

    def __init__(self, graph: StateGraph, checkpointer: Checkpointer | None = None) -> None:
        self.graph = graph
        self.checkpointer = checkpointer or Checkpointer()

    def invoke(
        self,
        initial_state: dict[str, Any],
        config: dict[str, Any] | None = None,
        max_steps: int = 50,
    ) -> dict[str, Any]:
        """Execute the graph from START until END, interrupt, or max_steps."""
        config = config or {}
        thread_id = config.get("configurable", {}).get("thread_id", "default")

        # Resume from checkpoint if present and thread matches
        saved_state = self.checkpointer.get_latest(thread_id)
        if saved_state:
            current_state = copy.deepcopy(saved_state)
            current_state.update(initial_state)
        else:
            current_state = copy.deepcopy(initial_state)

        # Determine current node
        if current_state.get("__interrupted__") and current_state.get("__paused_at__"):
            current_node = current_state["__paused_at__"]
        elif START in self.graph.edges:
            current_node = self.graph.edges[START]
        else:
            raise RuntimeError("Graph must have an edge originating from START")

        step = 0
        while current_node != END and step < max_steps:
            step += 1

            # Check if this node is paused for human interaction
            if current_node in self.graph.pause_nodes:
                if current_state.get("__human_decision__") != "approved":
                    current_state["__interrupted__"] = True
                    current_state["__paused_at__"] = current_node
                    self.checkpointer.save(thread_id, step, current_node, current_state)
                    return current_state
                # Consumed approval; clear temporary flag
                current_state.pop("__human_decision__", None)
                current_state["__interrupted__"] = False

            # Execute node
            node_fn = self.graph.nodes[current_node]
            node_output = node_fn(current_state)
            if isinstance(node_output, dict):
                current_state.update(node_output)

            # Checkpoint after step
            self.checkpointer.save(thread_id, step, current_node, current_state)

            # Determine next node via conditional or direct edges
            if current_node in self.graph.conditional_edges:
                router, path_map = self.graph.conditional_edges[current_node]
                route_key = router(current_state)
                if route_key not in path_map:
                    raise KeyError(f"Router returned '{route_key}' which is not in path_map {list(path_map.keys())}")
                current_node = path_map[route_key]
            elif current_node in self.graph.edges:
                current_node = self.graph.edges[current_node]
            else:
                # Default terminal if no outgoing edge
                current_node = END

        if step >= max_steps and current_node != END:
            current_state["__max_steps_reached__"] = True
            current_state["__completed__"] = False
        else:
            current_state["__completed__"] = (current_node == END)

        return current_state
