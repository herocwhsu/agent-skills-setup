# Lecture 14 Code Artifacts

This directory contains the code artifacts and blueprints for Lecture 14:

- [`graph.md`](./graph.md): Complete blueprint of the Maker-Checker multi-agent graph with explicit nodes, edges, state schema, and routing rules.
- [`scripts/graph_runner.py`](../../../../scripts/graph_runner.py): Pure Python zero-dependency StateGraph engine implementing nodes, conditional routing, checkpointer persistence, and human interrupt.
- [`tests/test_graph_runner.py`](../../../../tests/test_graph_runner.py): Comprehensive unit tests covering DAG execution, conditional branching, rollback cycles, and checkpoint resuming.
