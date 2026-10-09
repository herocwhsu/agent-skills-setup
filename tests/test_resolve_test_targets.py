"""Tests for scripts/resolve_test_targets.py."""

from __future__ import annotations

import sys
from pathlib import Path

# Add scripts directory to path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from resolve_test_targets import is_infra_file, resolve_all_targets


def test_infra_files_trigger_all():
    assert is_infra_file("scripts/_lib.sh") is True
    assert is_infra_file("scripts/run-tests.sh") is True
    assert is_infra_file(".python-version") is True
    assert is_infra_file("requirements-dev.txt") is True
    assert is_infra_file("mypy.ini") is True
    assert is_infra_file(".github/workflows/ci.yml") is True
    assert is_infra_file(".claude/settings.json") is True

    targets = resolve_all_targets(["scripts/_lib.sh", "scripts/setup-git-hooks.sh"])
    assert targets == ["ALL"]


def test_docs_trigger_no_tests():
    targets = resolve_all_targets(["README.md", "PROGRESS.md", "docs/architecture.md"])
    assert targets == []


def test_script_resolves_to_script_test():
    targets = resolve_all_targets(["scripts/setup-git-hooks.sh"])
    assert "scripts/tests/test_setup_git_hooks.sh" in targets


def test_hook_resolves_to_hook_test():
    targets = resolve_all_targets([".claude/hooks/sh-check.sh"])
    assert ".claude/hooks/tests/test_sh_check.sh" in targets


def test_test_file_resolves_to_itself():
    targets = resolve_all_targets(["scripts/tests/test_setup_git_hooks.sh"])
    assert targets == ["scripts/tests/test_setup_git_hooks.sh"]


def test_lecture_code_resolves_to_lecture_test():
    targets = resolve_all_targets(["docs/harness-creator/lecture-10/code/e2e_runner.py"])
    assert "docs/harness-creator/lecture-10/code/test_e2e_runner.py" in targets


def test_empty_input_returns_empty():
    assert resolve_all_targets([]) == []
    assert resolve_all_targets(["   ", ""]) == []


def test_nested_subcommand_skill_resolves_tests():
    targets = resolve_all_targets(["skills/infra/host-optimization/scripts/check-linux.sh"])
    assert "skills/infra/host-optimization/tests/test_check_linux.sh" in targets

    polish_targets = resolve_all_targets(["skills/utils/polish-input/lib/polish.py"])
    assert "skills/utils/polish-input/tests/test_polish.py" in polish_targets


def test_unknown_skill_script_falls_back_to_all():
    targets = resolve_all_targets(["skills/unknown-tool/do_magic.sh"])
    assert targets == ["ALL"]

