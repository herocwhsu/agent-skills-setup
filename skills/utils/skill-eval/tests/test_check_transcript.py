"""Tests for utils/skill-eval/lib/check_transcript.py.

The tool is a heuristic reporter, not a pass/fail gate: it always exits 0 when
given a readable transcript, so every assertion here is on what it reports.
"""
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "lib" / "check_transcript.py"


def run(transcript, tmp_path, prefix="DOMAIN_NOTES"):
    f = tmp_path / "transcript.txt"
    f.write_text(transcript, encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(SCRIPT), prefix, str(f)],
        capture_output=True,
        text=True,
    )


def test_wrong_argument_count_exits_nonzero():
    r = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
    assert r.returncode == 1


def test_missing_markers_is_reported_and_not_an_error(tmp_path):
    r = run("just some prose\nno markers here\n", tmp_path)
    assert r.returncode == 0
    assert "No DOMAIN_NOTES_STATUS markers found" in r.stdout


def test_marker_count_is_reported(tmp_path):
    r = run("DOMAIN_NOTES_STATUS: HIT\nDOMAIN_NOTES_STATUS: MISS\n", tmp_path)
    assert "markers found: 2" in r.stdout


def test_only_the_requested_prefix_is_counted(tmp_path):
    r = run("OTHER_STATUS: HIT\nDOMAIN_NOTES_STATUS: HIT\n", tmp_path)
    assert "markers found: 1" in r.stdout


def test_prefix_is_regex_escaped(tmp_path):
    # A prefix with regex metacharacters must be matched literally, not compiled
    # as a pattern (a bare '.' would otherwise match any character).
    r = run("A.B_STATUS: HIT\n", tmp_path, prefix="A.B")
    assert "markers found: 1" in r.stdout
    r2 = run("AXB_STATUS: HIT\n", tmp_path, prefix="A.B")
    assert "No A.B_STATUS markers found" in r2.stdout


def test_miss_with_no_following_investigation_is_flagged(tmp_path):
    r = run("prose\nDOMAIN_NOTES_STATUS: MISS\nmore prose\n", tmp_path)
    assert "MISS with no visible fallback investigation" in r.stdout


def test_miss_followed_by_tool_calls_is_not_flagged(tmp_path):
    transcript = "prose\nDOMAIN_NOTES_STATUS: MISS\n[tool: Grep] searching\n"
    r = run(transcript, tmp_path)
    assert "no visible fallback" not in r.stdout


def test_hit_with_many_following_tool_calls_is_flagged(tmp_path):
    calls = "".join(f"[tool: Read] file{i}\n" for i in range(5))
    r = run(f"DOMAIN_NOTES_STATUS: HIT\n{calls}", tmp_path)
    assert "cache ignored?" in r.stdout


def test_hit_with_few_following_tool_calls_is_not_flagged(tmp_path):
    r = run("DOMAIN_NOTES_STATUS: HIT\n[tool: Read] one\n", tmp_path)
    assert "cache ignored?" not in r.stdout


def test_appended_with_no_preceding_investigation_is_flagged(tmp_path):
    r = run("prose only\nDOMAIN_NOTES_STATUS: APPENDED\n", tmp_path)
    assert "fabricated note?" in r.stdout


def test_appended_after_investigation_is_not_flagged(tmp_path):
    r = run("[tool: Grep] looked\nDOMAIN_NOTES_STATUS: APPENDED\n", tmp_path)
    assert "fabricated note?" not in r.stdout


def test_skipped_spot_check_is_noted(tmp_path):
    r = run("DOMAIN_NOTES_STATUS: SPOT_CHECK_SKIPPED\n", tmp_path)
    assert "spot-check was skipped" in r.stdout


def test_state_matching_is_case_insensitive(tmp_path):
    r = run("prose\nDOMAIN_NOTES_STATUS: miss\n", tmp_path)
    assert "no visible fallback" in r.stdout


def test_undecodable_bytes_do_not_crash(tmp_path):
    f = tmp_path / "t.bin"
    f.write_bytes(b"\xff\xfe binary\nDOMAIN_NOTES_STATUS: HIT\n")
    r = subprocess.run(
        [sys.executable, str(SCRIPT), "DOMAIN_NOTES", str(f)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0
    assert "markers found: 1" in r.stdout


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-q"]))
