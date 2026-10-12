"""Unit tests for scripts/state_brief.py."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import state_brief as sb

PROGRESS = """# Session Progress Log

## Status

### What's In Progress

- Nothing active (WIP=0, clean state).

### What's Next

**Prioritized Technical Queue (WIP=1):**
1. **[DONE 2026-10-12] Smoke test:** finished long ago, with plenty of detail.
2. **Cut the fresh-session context cost: plan is lazy loading.** Long rationale that must not appear.
   - *Verification:* before/after total.
3. **Resume Hermes cleanup.** More detail.

**Pending Owner Decisions (Blocked on Human):**
- **Handy branch:** decide.

## Blockers / Risks
"""


def _repo(tmp_path: Path, features: list[dict], progress: str = PROGRESS) -> Path:
    (tmp_path / "feature_list.json").write_text(json.dumps({"features": features}))
    (tmp_path / "PROGRESS.md").write_text(progress)
    return tmp_path


def _feat(fid: str, status: str, **extra: object) -> dict:
    return {"id": fid, "name": f"name of {fid}", "status": status, **extra}


def test_active_feature_shows_id_name_and_verification(tmp_path):
    repo = _repo(
        tmp_path,
        [
            _feat("feat-001", "completed", description="OLD-DESCRIPTION-MARKER"),
            _feat("feat-002", "active", verification="bash run-the-check.sh"),
        ],
    )
    out = sb.brief(repo)
    assert "Active: feat-002 name of feat-002" in out
    assert "bash run-the-check.sh" in out
    assert "OLD-DESCRIPTION-MARKER" not in out


def test_no_active_feature_is_stated_and_last_done_is_named(tmp_path):
    repo = _repo(tmp_path, [_feat("feat-001", "completed"), _feat("feat-002", "completed")])
    out = sb.brief(repo)
    assert "Active: none" in out
    assert "Last completed: feat-002 name of feat-002" in out


def test_queue_lists_open_items_by_title_only(tmp_path):
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")]))
    assert "Cut the fresh-session context cost: plan is lazy loading." in out
    assert "Resume Hermes cleanup." in out
    assert "Smoke test" not in out
    assert "Long rationale" not in out
    assert "Handy branch" not in out


def test_in_progress_section_is_included(tmp_path):
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")]))
    assert "Nothing active (WIP=0, clean state)." in out


def test_missing_state_files_fail_loud(tmp_path):
    with pytest.raises(sb.StateMissing, match="feature_list.json"):
        sb.brief(tmp_path)


def test_main_returns_2_on_missing_files(tmp_path, capsys):
    assert sb.main([str(tmp_path)]) == 2
    assert "feature_list.json" in capsys.readouterr().err


def test_in_progress_section_is_bounded(tmp_path):
    detail = "\n".join(f"- detail line {i}" for i in range(100))
    progress = PROGRESS.replace("- Nothing active (WIP=0, clean state).", detail)
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")], progress))
    assert "detail line 0" in out
    assert "detail line 99" not in out
    assert len(out.splitlines()) <= 15


@pytest.mark.parametrize("body", ["5", "null", '{"features": {"a": 1}}', '{"features": "x"}'])
def test_malformed_feature_list_shape_fails_loud(tmp_path, body):
    (tmp_path / "feature_list.json").write_text(body)
    (tmp_path / "PROGRESS.md").write_text(PROGRESS)
    with pytest.raises(sb.StateMissing, match="feature_list.json"):
        sb.brief(tmp_path)
    assert sb.main([str(tmp_path)]) == 2


def test_done_status_counts_as_completed(tmp_path):
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "done")]))
    assert "Last completed: feat-001 name of feat-001" in out


def test_in_progress_overflow_line_reports_exact_remainder(tmp_path):
    detail = "\n".join(f"- d{i}" for i in range(8))
    progress = PROGRESS.replace("- Nothing active (WIP=0, clean state).", detail)
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")], progress))
    assert "... 3 more in PROGRESS.md" in out
    assert "- d4" in out and "- d5" not in out


def test_undecodable_progress_fails_loud(tmp_path):
    (tmp_path / "feature_list.json").write_text(json.dumps({"features": []}))
    (tmp_path / "PROGRESS.md").write_bytes(b"\xff\xfe### What's Next")
    with pytest.raises(sb.StateMissing, match="PROGRESS.md"):
        sb.brief(tmp_path)
    assert sb.main([str(tmp_path)]) == 2


def test_deeply_nested_feature_list_fails_loud(tmp_path):
    (tmp_path / "feature_list.json").write_text("[" * 100000)
    (tmp_path / "PROGRESS.md").write_text(PROGRESS)
    assert sb.main([str(tmp_path)]) == 2


def test_empty_progress_warns_instead_of_silent_success(tmp_path):
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")], ""))
    assert "PROGRESS.md has no In Progress or Next section" in out


def test_long_verification_and_titles_are_truncated(tmp_path):
    long_verify = "x" * 5000
    progress = PROGRESS.replace(
        "Cut the fresh-session context cost: plan is lazy loading.", "T" * 3000
    )
    out = sb.brief(
        _repo(tmp_path, [_feat("feat-001", "active", verification=long_verify)], progress)
    )
    assert max(len(line) for line in out.splitlines()) <= sb.MAX_LINE + 12
    assert "…" in out


def test_many_active_features_and_queue_items_are_capped(tmp_path):
    feats = [_feat(f"feat-{i:03d}", "active", verification="v") for i in range(50)]
    queue = "\n".join(f"{i}. **Item {i}.** detail" for i in range(1, 16))
    progress = "### What's Next\n\n" + queue + "\n\n**Pending Owner Decisions**\n"
    out = sb.brief(_repo(tmp_path, feats, progress))
    assert len(out.splitlines()) <= 25
    assert "more active" in out and "more in PROGRESS.md" in out


def test_nested_bold_in_queue_title_is_kept(tmp_path):
    progress = "### What's Next\n\n1. **Fix `a**b` thing** detail\n"
    out = sb.brief(_repo(tmp_path, [_feat("feat-001", "completed")], progress))
    assert "Fix `a**b` thing" in out
