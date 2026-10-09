"""resolve_test_targets.py — Map changed files to target test suites.

Given a list of changed file paths, resolves the minimal set of corresponding
test files that must be executed. Triggers a full fallback ("ALL") whenever
shared repository infrastructure or manifests are modified.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Changes to these shared files affect everything and require running the full suite
INFRA_FILES = {
    "scripts/_lib.sh",
    "scripts/run-tests.sh",
    "scripts/harness-verify.sh",
    "scripts/coverage-check.sh",
    "init.sh",
    ".python-version",
    "requirements-dev.txt",
    "mypy.ini",
    "registry.txt",
}

# Directories whose changes trigger full suite
INFRA_PREFIXES = (
    ".github/",
    ".claude/settings.json",
    ".agents/hooks.json",
    ".codex/hooks.json",
)


def is_infra_file(path_str: str) -> bool:
    clean = path_str.strip().removeprefix("./")
    if clean in INFRA_FILES:
        return True
    return any(clean.startswith(prefix) for prefix in INFRA_PREFIXES)


def resolve_targets_for_file(path_str: str, repo_root: Path) -> set[str]:
    """Map a single changed file to candidate test files."""
    clean = path_str.strip().removeprefix("./")
    if not clean:
        return set()

    # Documentation and metadata only -> no test needed
    if clean.endswith((".md", ".txt", ".json")) and not clean.startswith("skills/"):
        return set()

    # 1. If the changed file is itself a test file, run it
    if "/tests/" in clean or os.path.basename(clean).startswith("test_"):
        return {clean}

    targets: set[str] = set()

    # 2. Hook files: .claude/hooks/<name>.sh -> .claude/hooks/tests/test_<name>.sh
    if clean.startswith(".claude/hooks/"):
        name = os.path.basename(clean)
        hook_test = f".claude/hooks/tests/test_{name}"
        if (repo_root / hook_test).exists():
            targets.add(hook_test)
        # Also check underscore variant: e.g. sh-check.sh -> test_sh_check.sh
        alt_test = f".claude/hooks/tests/test_{name.replace('-', '_')}"
        if (repo_root / alt_test).exists():
            targets.add(alt_test)
        return targets

    # 3. Scripts: scripts/<name>.sh -> scripts/tests/test_<name>.sh
    if clean.startswith("scripts/"):
        name = os.path.basename(clean)
        script_test = f"scripts/tests/test_{name}"
        if (repo_root / script_test).exists():
            targets.add(script_test)
        alt_test = f"scripts/tests/test_{name.replace('-', '_')}"
        if (repo_root / alt_test).exists():
            targets.add(alt_test)
        # Python scripts in scripts/ -> tests/test_<name>.py
        if clean.endswith(".py"):
            py_name = os.path.splitext(name)[0]
            py_test = f"tests/test_{py_name}.py"
            if (repo_root / py_test).exists():
                targets.add(py_test)
        return targets

    # 4. Lecture code: docs/harness-creator/lecture-<N>/code/<file>.py -> .../test_<file>.py
    if "docs/harness-creator/" in clean and "/code/" in clean:
        dir_path = os.path.dirname(clean)
        base_name = os.path.basename(clean)
        lecture_test = f"{dir_path}/test_{base_name}"
        if (repo_root / lecture_test).exists():
            targets.add(lecture_test)
        return targets

    # 5. Skills: walk directory hierarchy for enclosing or sibling tests/ directory
    if clean.startswith("skills/"):
        file_path = repo_root / clean
        cur = file_path.parent
        found_tests: set[str] = set()
        # Search parent directories up to repo_root / "skills"
        while cur != repo_root and cur != repo_root / "skills" and len(cur.relative_to(repo_root).parts) > 1:
            tests_dir = cur / "tests"
            if tests_dir.is_dir():
                for test_file in tests_dir.glob("test_*"):
                    found_tests.add(str(test_file.relative_to(repo_root)))
            cur = cur.parent

        if found_tests:
            return found_tests

        # If executable script under skills/ has no resolved tests, fall back to ALL
        if clean.endswith((".sh", ".py")):
            return {"ALL"}
        return targets

    # 6. Top-level python modules -> tests/test_<name>.py
    if clean.endswith(".py"):
        py_name = os.path.splitext(os.path.basename(clean))[0]
        py_test = f"tests/test_{py_name}.py"
        if (repo_root / py_test).exists():
            targets.add(py_test)
            return targets

    # Unknown code file -> triggers full suite
    return {"ALL"}


def resolve_all_targets(files: list[str], repo_root: Path | None = None) -> list[str]:
    """Resolve test targets across all changed files."""
    if repo_root is None:
        custom_root = os.environ.get("RESOLVE_REPO_DIR")
        if custom_root:
            repo_root = Path(custom_root).resolve()
        else:
            repo_root = Path(__file__).resolve().parent.parent

    all_targets: set[str] = set()

    for f in files:
        f = f.strip()
        if not f:
            continue
        if is_infra_file(f):
            return ["ALL"]

        file_targets = resolve_targets_for_file(f, repo_root)
        if "ALL" in file_targets:
            return ["ALL"]
        all_targets.update(file_targets)

    return sorted(all_targets)


def main() -> int:
    if len(sys.argv) > 1:
        files = sys.argv[1:]
    else:
        files = [line.strip() for line in sys.stdin if line.strip()]

    targets = resolve_all_targets(files)
    for t in targets:
        print(t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
