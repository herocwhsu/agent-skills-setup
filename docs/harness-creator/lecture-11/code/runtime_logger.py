#!/usr/bin/env python3
"""runtime_logger.py

Structured logging and observability module demonstrating the difference between
ad-hoc unstructured logs (print/console.log style) and structured JSON log entries
with trace correlation, automated failure diagnosis, latency analysis, and cascading
failure detection.

Aligned with Lecture 11: "Why Observability Belongs Inside the Harness".
"""

from __future__ import annotations

import json
import secrets
from collections.abc import Callable
from dataclasses import asdict, dataclass, field
from datetime import UTC, datetime
from typing import Any


@dataclass
class StructuredLogEntry:
    """A structured log entry adhering to observability and OpenTelemetry conventions."""

    timestamp: str
    level: str  # "INFO", "WARN", "ERROR", "DEBUG"
    component: str
    action: str
    duration_ms: int
    correlation_id: str
    trace_id: str
    span_id: str
    parent_span_id: str | None = None
    input: dict[str, Any] = field(default_factory=dict)
    output: dict[str, Any] = field(default_factory=dict)
    error: str | None = None

    def __post_init__(self) -> None:
        self.duration_ms = max(0, self.duration_ms)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), ensure_ascii=False)


@dataclass
class PipelineStage:
    """A simulated stage in an agentic multi-stage pipeline."""

    component: str
    action: str
    duration_ms: int
    success: bool = True
    input: dict[str, Any] = field(default_factory=dict)
    output: dict[str, Any] = field(default_factory=dict)
    error_message: str | None = None


class RuntimeLogger:
    """Harness-level structured logger supporting traces and spans."""

    def __init__(self, trace_id: str | None = None, correlation_id: str | None = None):
        self.trace_id: str = trace_id or f"trace-{secrets.token_hex(8)}"
        self.correlation_id: str = correlation_id or f"req-{secrets.token_hex(4)}"
        self.entries: list[StructuredLogEntry] = []

    def create_span_id(self) -> str:
        return f"span-{secrets.token_hex(4)}"

    def log(
        self,
        component: str,
        action: str,
        level: str,
        duration_ms: int,
        span_id: str | None = None,
        parent_span_id: str | None = None,
        input_data: dict[str, Any] | None = None,
        output_data: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> StructuredLogEntry:
        entry = StructuredLogEntry(
            timestamp=datetime.now(UTC).isoformat(),
            level=level.upper(),
            component=component,
            action=action,
            duration_ms=duration_ms,
            correlation_id=self.correlation_id,
            trace_id=self.trace_id,
            span_id=span_id or self.create_span_id(),
            parent_span_id=parent_span_id,
            input=input_data or {},
            output=output_data or {},
            error=error,
        )
        self.entries.append(entry)
        return entry

    def log_info(
        self,
        component: str,
        action: str,
        duration_ms: int = 0,
        input_data: dict[str, Any] | None = None,
        output_data: dict[str, Any] | None = None,
        span_id: str | None = None,
        parent_span_id: str | None = None,
    ) -> StructuredLogEntry:
        return self.log(
            component=component,
            action=action,
            level="INFO",
            duration_ms=duration_ms,
            span_id=span_id,
            parent_span_id=parent_span_id,
            input_data=input_data,
            output_data=output_data,
        )

    def log_error(
        self,
        component: str,
        action: str,
        error_msg: str,
        duration_ms: int = 0,
        input_data: dict[str, Any] | None = None,
        output_data: dict[str, Any] | None = None,
        span_id: str | None = None,
        parent_span_id: str | None = None,
    ) -> StructuredLogEntry:
        return self.log(
            component=component,
            action=action,
            level="ERROR",
            duration_ms=duration_ms,
            span_id=span_id,
            parent_span_id=parent_span_id,
            input_data=input_data,
            output_data=output_data,
            error=error_msg,
        )


def build_sample_pipeline() -> list[PipelineStage]:
    """Generates the canonical 5-stage document Q&A pipeline with a seeded failure."""
    return [
        PipelineStage(
            component="DocumentLoader",
            action="parse_upload",
            duration_ms=45,
            success=True,
            input={"filename": "quarterly_report.pdf", "size": "2.3MB"},
            output={"chunks": 47},
        ),
        PipelineStage(
            component="ChunkIndexer",
            action="embed_and_store",
            duration_ms=230,
            success=True,
            input={"chunks": 47},
            output={"indexed": 47, "embedding_dim": 1536},
        ),
        PipelineStage(
            component="QueryRouter",
            action="route_query",
            duration_ms=12,
            success=True,
            input={"query": "What is the Q3 revenue target?"},
            output={"routed_to": "RetrievalEngine"},
        ),
        PipelineStage(
            # SEEDED FAILURE: Vector dimension mismatch in query embedding
            component="RetrievalEngine",
            action="semantic_search",
            duration_ms=180,
            success=False,
            error_message="Vector dimension mismatch: query embedding dim=768, index embedding dim=1536",
            input={"query": "What is the Q3 revenue target?", "top_k": 5},
            output={"results": 0},
        ),
        PipelineStage(
            # Cascading failure: AnswerGenerator receives empty context
            component="AnswerGenerator",
            action="generate_with_citations",
            duration_ms=1500,
            success=True,  # Execution succeeds without crashing, but output is invalid/empty
            input={"context": [], "query": "What is the Q3 revenue target?"},
            output={"answer": "I could not find relevant information in the uploaded document.", "citations": 0},
        ),
    ]


def run_adhoc_logging(stages: list[PipelineStage]) -> list[str]:
    """Simulates ad-hoc print/console.log output from an agent execution."""
    logs: list[str] = [
        "Starting document Q&A pipeline...",
        "User uploaded quarterly_report.pdf",
    ]
    for stage in stages:
        if stage.success:
            logs.append(f"{stage.component}: {stage.action} done ({stage.duration_ms}ms)")
        else:
            logs.append(f"{stage.component}: something went wrong")
    logs.append("Pipeline finished. Answer: I could not find relevant information in the uploaded document.")
    return logs


def run_structured_logging(
    stages: list[PipelineStage], logger: RuntimeLogger | None = None
) -> list[StructuredLogEntry]:
    """Records structured log entries for each pipeline stage."""
    log = logger or RuntimeLogger()
    parent_span: str | None = None

    for stage in stages:
        span_id = log.create_span_id()
        level = "INFO" if stage.success else "ERROR"
        log.log(
            component=stage.component,
            action=stage.action,
            level=level,
            duration_ms=stage.duration_ms,
            span_id=span_id,
            parent_span_id=parent_span,
            input_data=stage.input,
            output_data=stage.output,
            error=stage.error_message,
        )
        parent_span = span_id
    return log.entries


@dataclass
class DiagnosticReport:
    """Automated root-cause and anomaly analysis derived from structured logs."""

    root_causes: list[dict[str, Any]] = field(default_factory=list)
    latency_spikes: list[dict[str, Any]] = field(default_factory=list)
    cascading_failures: list[dict[str, Any]] = field(default_factory=list)
    trace_id: str = ""
    trace_ids: list[str] = field(default_factory=list)
    correlation_id: str = ""

    @property
    def has_anomalies(self) -> bool:
        return bool(self.root_causes or self.latency_spikes or self.cascading_failures)


def diagnose_from_structured(
    entries: list[StructuredLogEntry],
    latency_threshold_ms: int = 1000,
    cascade_predicate: Callable[[StructuredLogEntry], tuple[bool, str]] | None = None,
) -> DiagnosticReport:
    """Performs deterministic analysis on structured logs without relying on qualitative guesses."""
    report = DiagnosticReport()
    if entries:
        report.trace_id = entries[0].trace_id
        report.trace_ids = sorted({e.trace_id for e in entries})
        report.correlation_id = entries[0].correlation_id

    # 1. Identify explicit errors (Root Causes)
    for entry in entries:
        if entry.level == "ERROR" or entry.error is not None:
            report.root_causes.append({
                "component": entry.component,
                "action": entry.action,
                "error": entry.error,
                "input": entry.input,
                "output": entry.output,
                "span_id": entry.span_id,
                "correlation_id": entry.correlation_id,
                "trace_id": entry.trace_id,
            })

    # 2. Identify latency spikes
    for entry in entries:
        if entry.duration_ms > latency_threshold_ms:
            report.latency_spikes.append({
                "component": entry.component,
                "action": entry.action,
                "duration_ms": entry.duration_ms,
                "threshold_ms": latency_threshold_ms,
                "span_id": entry.span_id,
                "trace_id": entry.trace_id,
            })

    # 3. Detect cascading failures (degraded downstream steps following an upstream error)
    had_error = False
    for entry in entries:
        is_error = entry.level == "ERROR" or entry.error is not None
        if is_error:
            had_error = True
            continue

        if had_error:
            if cascade_predicate is not None:
                is_degraded, symptom = cascade_predicate(entry)
                if is_degraded:
                    report.cascading_failures.append({
                        "component": entry.component,
                        "action": entry.action,
                        "input": entry.input,
                        "output": entry.output,
                        "symptom": symptom,
                        "span_id": entry.span_id,
                        "trace_id": entry.trace_id,
                    })
            else:
                # Default generic & pipeline degradation checks
                has_empty_context = entry.input.get("context") == [] or entry.output.get("results") == 0
                has_zero_citations = entry.output.get("citations") == 0
                has_empty_output = entry.output == {}
                if has_empty_context or has_zero_citations or has_empty_output:
                    symptom = "Downstream degradation due to upstream failure"
                    if has_zero_citations:
                        symptom += " (0 citations returned)"
                    report.cascading_failures.append({
                        "component": entry.component,
                        "action": entry.action,
                        "input": entry.input,
                        "output": entry.output,
                        "symptom": symptom,
                        "span_id": entry.span_id,
                        "trace_id": entry.trace_id,
                    })

    return report


def format_table(entries: list[StructuredLogEntry]) -> str:
    """Formats structured log entries into a clean ASCII table."""
    lines = []
    lines.append(f"| {'Status':<6} | {'Timestamp':<28} | {'Level':<6} | {'Component':<18} | {'Action':<24} | {'Duration':<10} | {'Error':<35} |")
    lines.append(f"|{'-'*8}|{'-'*30}|{'-'*8}|{'-'*20}|{'-'*26}|{'-'*12}|{'-'*37}|")
    for e in entries:
        err = (e.error or "")[:35]
        status = "ERROR" if (e.level == "ERROR" or e.error is not None) else "OK"
        lines.append(f"| {status:<6} | {e.timestamp:<28} | {e.level:<6} | {e.component:<18} | {e.action:<24} | {f'{e.duration_ms}ms':<10} | {err:<35} |")
    return "\n".join(lines)


def run_comparison() -> dict[str, Any]:
    """Runs both scenarios and returns comparison metrics."""
    stages = build_sample_pipeline()
    logger = RuntimeLogger()
    structured = run_structured_logging(stages, logger)
    diagnostics = diagnose_from_structured(structured)

    comparison = {
        "root_cause_identifiable": {"adhoc": False, "structured": True},
        "input_output_traceable": {"adhoc": False, "structured": True},
        "correlation_across_steps": {"adhoc": False, "structured": True},
        "machine_parseable": {"adhoc": False, "structured": True},
        "time_to_diagnose": {"adhoc": "Minutes (manual guesswork)", "structured": "Milliseconds (automated query)"},
        "root_cause_count": len(diagnostics.root_causes),
        "latency_spike_count": len(diagnostics.latency_spikes),
        "cascade_count": len(diagnostics.cascading_failures),
    }
    return comparison


def main() -> None:
    print("=" * 80)
    print("  OBSERVABILITY DEMO — Ad-hoc vs Structured Logging (Lecture 11)")
    print("=" * 80)

    stages = build_sample_pipeline()

    # Scenario A: Ad-hoc
    print("\n" + "-" * 80)
    print("  SCENARIO A: Ad-hoc Unstructured Logs")
    print("-" * 80)
    adhoc_logs = run_adhoc_logging(stages)
    for log in adhoc_logs:
        print(f"  {log}")
    print("\n  Diagnostic Verdict: Hard to tell what failed. 'something went wrong' lacks context.")

    # Scenario B: Structured
    print("\n" + "-" * 80)
    print("  SCENARIO B: Structured JSON Logs with Trace Correlation")
    print("-" * 80)
    logger = RuntimeLogger()
    structured_entries = run_structured_logging(stages, logger)
    print(format_table(structured_entries))

    # Automated Diagnosis
    print("\n" + "-" * 80)
    print("  AUTOMATED ROOT-CAUSE DIAGNOSIS")
    print("-" * 80)
    report = diagnose_from_structured(structured_entries)
    print(f"  Trace ID: {report.trace_id} | Correlation ID: {report.correlation_id}")
    for rc in report.root_causes:
        print("\n  [!] ROOT CAUSE DETECTED:")
        print(f"      Component: {rc['component']}.{rc['action']}")
        print(f"      Error:     {rc['error']}")
        print(f"      Input:     {json.dumps(rc['input'])}")
        print(f"      Output:    {json.dumps(rc['output'])}")

    for ls in report.latency_spikes:
        print("\n  [~] LATENCY SPIKE DETECTED:")
        print(f"      Component: {ls['component']}.{ls['action']}")
        print(f"      Duration:  {ls['duration_ms']}ms (threshold: {ls['threshold_ms']}ms)")

    for cf in report.cascading_failures:
        print("\n  [*] CASCADING FAILURE DETECTED:")
        print(f"      Component: {cf['component']}.{cf['action']}")
        print(f"      Symptom:   {cf['symptom']}")
        print(f"      Input:     {json.dumps(cf['input'])}")
        print(f"      Output:    {json.dumps(cf['output'])}")

    print("\n" + "=" * 80)
    print("  COMPARISON SUMMARY")
    print("=" * 80)
    comp = run_comparison()
    print("  | Metric                       | Ad-hoc Logs             | Structured Logs         |")
    print("  |------------------------------|-------------------------|-------------------------|")
    print("  | Root cause identifiable     | No                      | Yes                     |")
    print("  | Input/output traceable       | No                      | Yes                     |")
    print("  | Step correlation (Trace ID)  | No                      | Yes                     |")
    print("  | Machine parseable            | No                      | Yes                     |")
    print(f"  | Time to diagnose             | {comp['time_to_diagnose']['adhoc']:<23} | {comp['time_to_diagnose']['structured']:<23} |")
    print()


if __name__ == "__main__":
    main()
