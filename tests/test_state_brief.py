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
