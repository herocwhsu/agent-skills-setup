---
name: langgraph
description: Use when building stateful multi-step or multi-agent workflows where control flow requires loops, branching, or shared state between steps. LangGraph models the workflow as a graph — nodes are functions or LLM calls, edges control routing. Fits the spec-gated pipeline, approval loops, and any agentic task that needs explicit state management.
---

# langgraph

LangGraph is a graph-based orchestration library for stateful agentic workflows.
Each node is a Python function (or LLM call). Edges define routing — including
conditionals and cycles. State is a typed dict that flows through every node.

## When to use

- Multi-step pipeline where each step reads + writes shared state
- Loops: retry until condition met, human-in-the-loop approval, tool use cycles
- Branching: route to different nodes based on step output
- Multi-agent: separate agents as nodes, passing context between them
- Automating the spec-gated workflow end-to-end (intake → audit → repo-scan → apidog → review → release)

Not needed for simple sequential chains with no branching or cycles — plain function
calls are sufficient there.

## Install

```bash
pip install langgraph
# optional: LangSmith tracing
pip install langsmith
```

## Core concepts

State — typed dict that every node reads from and writes to:

```python
from typing import TypedDict, Annotated
import operator

class WorkflowState(TypedDict):
    story_id: str
    spec: str
    audit_report: dict
    repo_context: dict
    errors: Annotated[list, operator.add]  # append-only across nodes
    status: str
```

Nodes — plain Python functions that receive state and return a partial update:

```python
def intake_node(state: WorkflowState) -> dict:
    result = run_intake(state["story_id"])
    return {"spec": result.spec}

def audit_node(state: WorkflowState) -> dict:
    report = run_audit(state["spec"])
    return {"audit_report": report, "status": "audited"}
```

Edges — static or conditional routing:

```python
from langgraph.graph import StateGraph, END

def route_after_audit(state: WorkflowState) -> str:
    if state["audit_report"]["passed"]:
        return "repo_scan"
    return "audit_failed"

builder = StateGraph(WorkflowState)
builder.add_node("intake",       intake_node)
builder.add_node("audit",        audit_node)
builder.add_node("repo_scan",    repo_scan_node)
builder.add_node("audit_failed", audit_failed_node)

builder.set_entry_point("intake")
builder.add_edge("intake", "audit")
builder.add_conditional_edges("audit", route_after_audit, {
    "repo_scan":    "repo_scan",
    "audit_failed": "audit_failed",
})
builder.add_edge("repo_scan", END)
builder.add_edge("audit_failed", END)

graph = builder.compile()
```

## Run

```python
result = graph.invoke({"story_id": "PROJ-123", "errors": [], "status": "started"})
print(result["status"])
```

## Human-in-the-loop (approval gate)

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
graph = builder.compile(checkpointer=checkpointer, interrupt_before=["deploy"])

# run until deploy node
thread = {"configurable": {"thread_id": "proj-123"}}
graph.invoke(initial_state, config=thread)

# human reviews, then resume
graph.invoke(None, config=thread)
```

## Persistence (resume after crash)

```python
from langgraph.checkpoint.sqlite import SqliteSaver

checkpointer = SqliteSaver.from_conn_string("checkpoints.db")
graph = builder.compile(checkpointer=checkpointer)
```

## Multi-agent pattern

Each agent is a node. Pass results via state:

```python
def intake_agent(state):
    # runs intake skill logic
    return {"spec": ...}

def audit_agent(state):
    # runs audit skill logic
    return {"audit_report": ...}

# wire as nodes in the graph
```

## Spec-gated workflow mapping

```
intake_node
    ↓
audit_spec_node
    ↓ (passed?)
    ├─ NO  → audit_failed_node → END
    └─ YES → repo_scan_node
                ↓
           audit_handoff_node
                ↓
           [human approval gate]
                ↓
           apidog_node
                ↓
           testing_node
                ↓
           review_node
                ↓
           release_node → END
```

## LangSmith tracing

```bash
export LANGCHAIN_TRACING_V2=true
export LANGCHAIN_API_KEY=<your key>
export LANGCHAIN_PROJECT=spec-gated-workflow
```

Every node invocation appears as a span in LangSmith automatically.

## Pitfalls

- State updates are shallow-merged — return only the keys you changed
- Annotated[list, operator.add] is needed for append-only fields (errors, logs);
  plain list assignment overwrites on every node
- interrupt_before requires a checkpointer — no checkpointer = no pause/resume
- Cycles are valid but need a termination condition in a conditional edge or they run forever
- compile() is cheap; do it once at module load, not per request
