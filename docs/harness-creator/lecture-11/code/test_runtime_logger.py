#!/usr/bin/env python3
"""test_runtime_logger.py

Unit and integration tests for Lecture 11 runtime logger and observability module.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Ensure code directory is in sys.path
code_dir = Path(__file__).resolve().parent
if str(code_dir) not in sys.path:
    sys.path.insert(0, str(code_dir))

from runtime_logger import (
    RuntimeLogger,
    StructuredLogEntry,
    build_sample_pipeline,
    diagnose_from_structured,
    run_adhoc_logging,
    run_comparison,
    run_structured_logging,
)


def test_structured_log_entry_serialization() -> None:
    entry = StructuredLogEntry(
        timestamp="2026-10-10T11:00:00Z",
        level="INFO",
        component="TestComponent",
        action="test_action",
        duration_ms=42,
        correlation_id="req-1234",
        trace_id="trace-abcd",
        span_id="span-5678",
        parent_span_id="span-parent",
        input={"param": "value"},
        output={"status": "ok"},
        error=None,
    )
    d = entry.to_dict()
    assert d["component"] == "TestComponent"
    assert d["duration_ms"] == 42
    assert d["trace_id"] == "trace-abcd"

    raw_json = entry.to_json()
    parsed = json.loads(raw_json)
    assert parsed["span_id"] == "span-5678"
    assert parsed["input"] == {"param": "value"}


def test_logger_trace_and_span_propagation() -> None:
    logger = RuntimeLogger(trace_id="trace-fixed-01", correlation_id="req-fixed-01")
    s1 = logger.log_info("CompA", "step1", duration_ms=10)
    s2 = logger.log_error("CompB", "step2", error_msg="fail", duration_ms=20, parent_span_id=s1.span_id)

    assert len(logger.entries) == 2
    assert s1.trace_id == "trace-fixed-01"
    assert s2.trace_id == "trace-fixed-01"
    assert s1.correlation_id == "req-fixed-01"
    assert s2.correlation_id == "req-fixed-01"
    assert s2.parent_span_id == s1.span_id
    assert s2.level == "ERROR"
    assert s2.error == "fail"


def test_adhoc_logging_blind_spot() -> None:
    stages = build_sample_pipeline()
    adhoc_logs = run_adhoc_logging(stages)

    # Ad-hoc logging obscures the true error message
    assert any("something went wrong" in line for line in adhoc_logs)
    assert not any("Vector dimension mismatch" in line for line in adhoc_logs)
    assert not any("dim=768" in line for line in adhoc_logs)


def test_structured_logging_pipeline() -> None:
    stages = build_sample_pipeline()
    entries = run_structured_logging(stages)

    assert len(entries) == 5
    assert entries[0].component == "DocumentLoader"
    assert entries[0].level == "INFO"

    retrieval_entry = entries[3]
    assert retrieval_entry.component == "RetrievalEngine"
    assert retrieval_entry.level == "ERROR"
    assert "Vector dimension mismatch" in str(retrieval_entry.error)
    assert retrieval_entry.output == {"results": 0}


def test_automated_diagnosis_root_cause() -> None:
    stages = build_sample_pipeline()
    entries = run_structured_logging(stages)
    report = diagnose_from_structured(entries)

    assert report.has_anomalies is True
    assert len(report.root_causes) == 1
    root = report.root_causes[0]
    assert root["component"] == "RetrievalEngine"
    assert root["action"] == "semantic_search"
    assert "query embedding dim=768" in root["error"]
    assert root["input"]["top_k"] == 5


def test_automated_diagnosis_latency_spikes() -> None:
    stages = build_sample_pipeline()
    entries = run_structured_logging(stages)
    report = diagnose_from_structured(entries, latency_threshold_ms=1000)

    assert len(report.latency_spikes) == 1
    spike = report.latency_spikes[0]
    assert spike["component"] == "AnswerGenerator"
    assert spike["duration_ms"] == 1500


def test_automated_diagnosis_cascading_failures() -> None:
    stages = build_sample_pipeline()
    entries = run_structured_logging(stages)
    report = diagnose_from_structured(entries)

    assert len(report.cascading_failures) >= 1
    cascade = report.cascading_failures[0]
    assert cascade["component"] == "AnswerGenerator"
    assert cascade["input"]["context"] == []
    assert cascade["output"]["citations"] == 0


def test_empty_log_diagnosis() -> None:
    report = diagnose_from_structured([])
    assert report.has_anomalies is False
    assert len(report.root_causes) == 0
    assert len(report.latency_spikes) == 0
    assert len(report.cascading_failures) == 0


def test_comparison_metrics() -> None:
    comp = run_comparison()
    assert comp["root_cause_identifiable"]["structured"] is True
    assert comp["root_cause_identifiable"]["adhoc"] is False
    assert comp["machine_parseable"]["structured"] is True
    assert comp["root_cause_count"] == 1
    assert comp["latency_spike_count"] == 1
    assert comp["cascade_count"] == 1


def test_duration_sanitization_negative_value() -> None:
    entry = StructuredLogEntry(
        timestamp="2026-10-10T11:00:00Z",
        level="INFO",
        component="Test",
        action="action",
        duration_ms=-100,
        correlation_id="c1",
        trace_id="t1",
        span_id="s1",
    )
    assert entry.duration_ms == 0


def test_custom_cascade_predicate() -> None:
    logger = RuntimeLogger()
    s1 = logger.log_error("Step1", "fail", error_msg="db error")
    s2 = logger.log_info("Step2", "process", output_data={"custom_status": "degraded_fallback"})

    def my_predicate(e: StructuredLogEntry) -> tuple[bool, str]:
        if e.output.get("custom_status") == "degraded_fallback":
            return True, "Triggered fallback path"
        return False, ""

    report = diagnose_from_structured(logger.entries, cascade_predicate=my_predicate)
    assert len(report.cascading_failures) == 1
    assert report.cascading_failures[0]["symptom"] == "Triggered fallback path"
    assert report.cascading_failures[0]["span_id"] == s2.span_id
    assert report.root_causes[0]["span_id"] == s1.span_id


def test_multi_trace_tracking() -> None:
    logger1 = RuntimeLogger(trace_id="trace-01")
    logger1.log_info("Comp", "act1")

    logger2 = RuntimeLogger(trace_id="trace-02")
    logger2.log_info("Comp", "act2")

    merged = logger1.entries + logger2.entries
    report = diagnose_from_structured(merged)
    assert report.trace_ids == ["trace-01", "trace-02"]


def test_table_formatting_clean_alignment() -> None:
    from runtime_logger import format_table

    stages = build_sample_pipeline()
    entries = run_structured_logging(stages)
    table = format_table(entries)

    lines = table.split("\n")
    assert lines[0].startswith("| Status | Timestamp")
    # No line should begin with markdown blockquote '>> '
    assert not any(line.startswith(">>") for line in lines)
    # Every row starts with '| ' and contains '|'
    for line in lines:
        assert line.startswith("|")
        assert line.endswith("|") or "Error" in line

