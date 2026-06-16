---
name: ai-stack-baml
description: Use when adding structured LLM output to any Python or TypeScript service. BAML defines LLM functions in .baml files with typed input/output schemas, generates type-safe client code, and parses LLM responses into declared types — even when the model returns messy output. Replaces manual JSON parsing and prompt string management.
---

# baml

BAML (Boundary Markup Language) is a DSL for writing LLM functions that reliably
return typed, structured data. You define prompt + schema + model in one .baml file,
run `baml-cli generate`, and get a type-safe function in Python or TypeScript.

## When to use

- LLM call must return a structured object (not free text)
- Need to compare the same prompt across multiple models
- Want a test harness for prompts (regression tests)
- Building AI features inside a FastAPI or Node service

## Install

```bash
# Python
pip install baml-py

# TypeScript
npm install @boundaryml/baml

# CLI (generates client code)
pip install baml-cli   # or: npm install -g @boundaryml/baml-cli
```

## Project structure

```
src/
  baml_src/           ← .baml files live here
    clients.baml      ← model/client definitions
    main.baml         ← your LLM functions
  baml_client/        ← auto-generated, never edit manually
    __init__.py
    ...
```

## Define a function (.baml)

```baml
// baml_src/clients.baml
client<llm> Claude {
  provider anthropic
  options {
    model claude-sonnet-4-6
    api_key env.ANTHROPIC_API_KEY
  }
}

client<llm> GPT4o {
  provider openai
  options {
    model gpt-4o
    api_key env.OPENAI_API_KEY
  }
}
```

```baml
// baml_src/main.baml
class AuditReport {
  conflicts    string[]
  gaps         string[]
  risks        string[]
  passed       bool
}

function AuditSpec(spec: string) -> AuditReport {
  client Claude
  prompt #"
    You are a spec auditor. Given the following spec, identify:
    - conflicts (contradictory requirements)
    - gaps (missing behaviors)
    - risks (security, permissions, data integrity)

    Spec:
    {{ spec }}

    {{ ctx.output_format }}
  "#
}
```

## Generate client code

```bash
baml-cli generate
# writes baml_client/ — commit this, it's the typed API
```

## Call from Python

```python
from baml_client import b
from baml_client.types import AuditReport

report: AuditReport = await b.AuditSpec(spec=raw_spec_text)
print(report.conflicts)   # typed list, not raw JSON
```

## Call from TypeScript

```typescript
import { b } from './baml_client'

const report = await b.AuditSpec({ spec: rawSpecText })
console.log(report.conflicts) // typed array
```

## Switch models without changing code

```baml
// change client in .baml, regenerate — no app code changes
function AuditSpec(spec: string) -> AuditReport {
  client GPT4o   // ← swap here
  ...
}
```

## Test prompts

```bash
baml test               # run all tests
baml test -f AuditSpec  # run one function's tests
```

Define tests in .baml:

```baml
test AuditSpec_basic {
  functions [AuditSpec]
  args {
    spec "Users can delete any organization."
  }
  @@assert(passed == false)
}
```

## Streaming (partial structured output)

```python
async with b.stream.AuditSpec(spec=text) as stream:
    async for partial in stream:
        print(partial.gaps)  # fills in as tokens arrive
```

## Retry + fallback

```baml
client<llm> ClaudeWithFallback {
  provider fallback
  options {
    strategy [Claude, GPT4o]  // tries Claude first, falls back to GPT4o
  }
}
```

## Relevant in this stack

- reseller-backend (FastAPI/Python): structured extraction from Jira descriptions,
  generating VO/DTO schemas from API docs, audit report fields
- Any Hermes skill that calls an LLM and needs guaranteed output shape
- Pair with LangSmith (langsmith skill) for eval and tracing

## Pitfalls

- Always run `baml-cli generate` after editing .baml files — stale client = wrong types
- Commit baml_client/ — it's generated but needed at runtime
- `{{ ctx.output_format }}` in the prompt is required for structured output; BAML
  injects the schema description automatically
- Do not parse `ctx.output_format` yourself — BAML handles it
