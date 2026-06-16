---
name: ai-stack
description: Use when adding AI/LLM features to a service — typed structured output, agent orchestration, retrieval, or evaluation. Subcommands document specific libraries (baml, langgraph). Reference material, not part of the spec-gated workflow.
---

# ai-stack

Reference bundle for libraries used to build LLM-powered features.
Activate when working on a service that calls models, parses their output,
or orchestrates multi-step agent flows.

Sits outside the spec-gated workflow — these subcommands describe library
usage, not story phases.

## Subcommands

| Skill | What it does | Implementation |
|---|---|---|
| `ai-stack/baml` | BAML — typed LLM functions with schema-driven response parsing for Python/TypeScript services | `baml/IMPL.md` |
| `ai-stack/langgraph` | LangGraph — graph-based orchestration for stateful, multi-step, or multi-agent workflows | `langgraph/IMPL.md` |

## When to use which subcommand

```
LLM call must return structured object → ai-stack/baml
Multi-step pipeline with shared state, branching, or loops → ai-stack/langgraph
Both (typed output inside an agent flow) → ai-stack/langgraph + ai-stack/baml
```

## Adding a new library

Create a new subdir `skills/ai-stack/<lib>/IMPL.md` with frontmatter
`name: ai-stack-<lib>`. Add a row to the table above. No registry change
needed — `ai-stack` is already registered as `local-optional`.

## Why local-optional

Most users of this repo build business apps and don't need LLM-library
reference material loaded into their agent context. Opt in by uncommenting
or explicitly running `bash scripts/install.sh` after adding `ai-stack` to
the registry's enabled list.
