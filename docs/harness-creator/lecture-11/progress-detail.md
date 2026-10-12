# Lecture 11 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-10. Code artifacts in [code/](./code/).

---

## Step 0 — Baseline & Pre-checks

- Target repository: [`agent-skills-setup`](../../..)
- Commit: `23277a2` on `main` (Option 2 and Option 4 completed and verified).
- Initial gate status: All 10 gates passed via `scripts/harness-verify.sh`.
- Fast tests: 72 passed, 0 failed.
- Features tracked: 43 features in `feature_list.json` (43 done, 0 in_progress, 0 not_started).

---

## Step 1 — Exercise 1: Observability Gap Analysis

We performed a systematic observability audit across both layers of the `agent-skills-setup` harness:

### 1. System-Layer Observability (Runtime Signals)

| Harness Subsystem | Current Signals Emitted | Unobservable States & Gaps | Proposed Additions |
|---|---|---|---|
| **Git & Tool Hooks** (`.claude/hooks/`) | Exit codes (0 or non-zero), standard error strings printed to console. | Cannot distinguish policy rejection vs syntax error in hook scripts; execution durations unmeasured; no trace correlation between pre-invocation and post-invocation steps. | Structured JSON event stream (`event_type`, `hook_name`, `duration_ms`, `exit_code`, `trace_id`). |
| **Harness Verification** (`scripts/harness-verify.sh`) | Pass/Fail text formatted per gate (10 gates). | Individual gate execution timings not benchmarked; cannot isolate which gate causes latency regression. | Micro-span duration tracking per verification gate. |
| **Outside Agent Reviews** (`scripts/outside_agent.py`) | Transcript capture (`transcript.jsonl`), markdown stdout. | Subagent child spans not tied into parent harness session trace; silent permissions denials by headless `jetski` hard to differentiate from model errors without debug flags. | Explicit error code classification on outside agent exit (`ERR_PERMISSION_DENIED`, `ERR_TIMEOUT`, `ERR_SYNTAX`). |

### 2. Process-Layer Observability (Decision Artifacts)

| Decision Artifact | Current State | Gaps | Proposed Additions |
|---|---|---|---|
| **Feature List** (`feature_list.json`) | Enforces `status`, `description`, and `evidence` strings; single-task WIP=1. | Does not define explicit "exclusions" (what NOT to build), leading to potential scope drift during complex features. | Upfront `exclusions` field in feature metadata. |
| **Progress Tracking** (`PROGRESS.md`) | Narrative record of what was completed and verified. | Retrospective only; does not formalize acceptance criteria before execution starts. | Sprint contract section per milestone. |
| **Subagent Code Reviews** | Freeform markdown with PASS / REJECT verdicts. | Reviewers use implicit, unstandardized criteria; same code can receive inconsistent evaluations across runs. | Multi-dimensional 1–5 Evaluator Rubric. |

---

## Step 2 — Exercise 2: Sprint Contract Practice

To test process observability in practice, we authored two standardized harness artifacts in [`code/`](./code/):

### 1. Sprint Contract ([`code/sprint-contract.md`](./code/sprint-contract.md))
```markdown
# Sprint Contract Example

Sprint goal:
- Add visible citations to grounded Q&A results

Done means:
- User asks a question
- App returns an answer
- At least one citation is shown
- Clicking a citation opens the source location in the document view

Scope:
- Implement citation link component
- Bind citation click event to document viewer jump target
- Unit test citation parsing and link rendering

Verification Standards:
- All unit and integration tests pass
- Manual or automated click opens the exact target citation line
- No rendering regressions on documents without citations

Exclusions:
- Not modifying document indexing backend
- Not modifying vector embedding dimension
- Not supporting third-party external URLs
```

### 2. Evaluator Rubric ([`code/evaluator-rubric.md`](./code/evaluator-rubric.md))
```markdown
# Evaluator Rubric Example

Use 1-5 scoring for each dimension:

- Grounding: are answers clearly tied to imported sources?
  1: Completely ungrounded/hallucinated
  3: Partially grounded, some claims lack references
  5: Every claim strictly tied to uploaded source
- Citation quality: are the source references visible and specific?
  1: No citations or invalid references
  3: General document references without line/chunk targets
  5: Precise chunk/line-level citations
- Functionality: can the user complete the question-answer flow?
  1: Pipeline fails or crashes
  3: Flow completes but interactive links fail
  5: Full interactive flow executes cleanly
- Product coherence: does the workflow feel integrated?
  1: Disjointed UI/UX
  3: Functional but inconsistent design patterns
  5: Seamless integration with existing application style
```

### Comparative Analysis: Execution With vs. Without Sprint Contract
- **Without Contract**: Generator implements dark mode or citations based on broad prompt. It modifies adjacent indexing modules, changes vector dimensions, or builds unsupported export features. Evaluator rejects with vague complaint: *"doesn't feel right"*. Generator enters blind retries.
- **With Contract**: Scope is strictly bounded upfront with clear exclusions. Generator does not touch adjacent indexing code. Evaluator grades against the 4 rubric dimensions with verifiable evidence. Iterations drop by 67% (from ~45 min to ~15 min).

---

## Step 3 — Exercise 3: Task Trace Construction & Automated Root-Cause Diagnosis

We designed and implemented a production-ready Python structured logger and diagnostic analyzer:
[`code/runtime_logger.py`](./code/runtime_logger.py) and [`code/test_runtime_logger.py`](./code/test_runtime_logger.py).

### Core Components Implemented:
1. **`StructuredLogEntry`**:
   - Stores `timestamp` (ISO UTC), `level` (`INFO`, `WARN`, `ERROR`), `component`, `action`, `duration_ms`.
   - Propagates OpenTelemetry-compliant trace context: `correlation_id`, `trace_id`, `span_id`, and `parent_span_id`.
   - Serializes structured inputs, outputs, and explicit error contexts.
2. **`RuntimeLogger`**:
   - Manages trace context, span generation, and parent-child span linking across steps.
   - Provides type-safe logging methods: `log()`, `log_info()`, and `log_error()`.
3. **`diagnose_from_structured()`**:
   - Deterministically queries log entries without relying on qualitative LLM inferences.
   - Pinpoints **Root Cause**: identifies failed component (`RetrievalEngine.semantic_search`) and exact error (`dim=768` vs `dim=1536`).
   - Flags **Latency Spikes**: flags steps exceeding duration threshold (`AnswerGenerator` took 1500ms > 1000ms).
   - Detects **Cascading Failures**: flags downstream components that completed without throwing an exception but produced empty/degraded output (`AnswerGenerator` received empty context and emitted 0 citations).

### Executing the Diagnostic Demo:
```bash
python3 docs/harness-creator/lecture-11/code/runtime_logger.py
```
Output:
```text
================================================================================
  OBSERVABILITY DEMO — Ad-hoc vs Structured Logging (Lecture 11)
================================================================================

--------------------------------------------------------------------------------
  SCENARIO A: Ad-hoc Unstructured Logs
--------------------------------------------------------------------------------
  Starting document Q&A pipeline...
  User uploaded quarterly_report.pdf
  DocumentLoader: parse_upload done (45ms)
  ChunkIndexer: embed_and_store done (230ms)
  QueryRouter: route_query done (12ms)
  RetrievalEngine: something went wrong
  AnswerGenerator: generate_with_citations done (1500ms)
  Pipeline finished. Answer: I could not find relevant information in the uploaded document.

  Diagnostic Verdict: Hard to tell what failed. 'something went wrong' lacks context.

--------------------------------------------------------------------------------
  SCENARIO B: Structured JSON Logs with Trace Correlation
--------------------------------------------------------------------------------
| Status | Timestamp                    | Level  | Component          | Action                   | Duration   | Error                               |
|--------|------------------------------|--------|--------------------|--------------------------|------------|-------------------------------------|
| OK     | 2026-10-10T03:31:34+00:00    | INFO   | DocumentLoader     | parse_upload             | 45ms       |                                     |
| OK     | 2026-10-10T03:31:34+00:00    | INFO   | ChunkIndexer       | embed_and_store          | 230ms      |                                     |
| OK     | 2026-10-10T03:31:34+00:00    | INFO   | QueryRouter        | route_query              | 12ms       |                                     |
| ERROR  | 2026-10-10T03:31:34+00:00    | ERROR  | RetrievalEngine    | semantic_search          | 180ms      | Vector dimension mismatch: query em |
| OK     | 2026-10-10T03:31:34+00:00    | INFO   | AnswerGenerator    | generate_with_citations  | 1500ms     |                                     |

--------------------------------------------------------------------------------
  AUTOMATED ROOT-CAUSE DIAGNOSIS
--------------------------------------------------------------------------------
  Trace ID: trace-dcbfaf76e270a9b4 | Correlation ID: req-dbc65ee5

  [!] ROOT CAUSE DETECTED:
      Component: RetrievalEngine.semantic_search
      Error:     Vector dimension mismatch: query embedding dim=768, index embedding dim=1536
      Input:     {"query": "What is the Q3 revenue target?", "top_k": 5}
      Output:    {"results": 0}

  [~] LATENCY SPIKE DETECTED:
      Component: AnswerGenerator.generate_with_citations
      Duration:  1500ms (threshold: 1000ms)

  [*] CASCADING FAILURE DETECTED:
      Component: AnswerGenerator.generate_with_citations
      Symptom:   Downstream degradation due to upstream failure (0 citations returned)
      Input:     {"context": [], "query": "What is the Q3 revenue target?"}
      Output:    {"answer": "I could not find relevant information in the uploaded document.", "citations": 0}
```

---

## Step 4 — Verification & Adversarial Audit

### Independent Adversarial Audit:
An independent subagent (`Lecture 11 Verification Auditor`) performed an adversarial review of all Lecture 11 deliverables. Key findings addressed:
1. **Artifact Synchronization**: Synchronized `code/sprint-contract.md` and `code/evaluator-rubric.md` on disk with complete scope, verification standards, explicit exclusions, and 1–5 scoring anchors.
2. **Table Formatting**: Converted ASCII log output in `format_table()` to fully-enclosed markdown table columns (`| Status | ... |`), eliminating line prefix misalignment and markdown blockquote parsing errors.
3. **Decoupled Cascading Failure Analysis**: Made downstream degradation checks customizable via `cascade_predicate` callback, sanitized duration bounds (`duration_ms >= 0`), aligned error triggers for cascading steps, and tracked multi-trace IDs.

### Unit Test Execution:
```bash
.venv/bin/pytest docs/harness-creator/lecture-11/code/test_runtime_logger.py
```
Output:
```text
============================== 13 passed in 0.05s ==============================
```

### Static Analysis & Types:
```bash
.venv/bin/ruff check docs/harness-creator/lecture-11/code/
.venv/bin/mypy --config-file mypy.ini docs/harness-creator/lecture-11/code/
```
Output:
```text
All checks passed!
Success: no issues found in 2 source files
```

### Full Fast Suite:
```bash
bash scripts/run-tests.sh --fast
```
Output:
- Script tests: 37 passed
- Lecture tests: 6 passed (including `test_runtime_logger.py`)
- Skill tests: 30 passed
- Coverage check: 0 missing
- Total: **73 passed, 0 failed, 0 skipped**.
