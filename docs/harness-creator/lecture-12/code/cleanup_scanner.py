#!/usr/bin/env python3
"""Cleanup scanner: Scans a project directory for stale artifacts, dead code markers,

structural violations, and uncommitted debug files to ensure clean state
at the end of every agent session. Ported from TypeScript cleanup-scanner.ts.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Literal

Severity = Literal["critical", "warning", "info"]


@dataclass
class ScanResult:
    category: str
    check: str
    severity: Severity
    found: list[str]
    description: str


@dataclass
class ScannerCheck:
    category: str
    name: str
    severity: Severity
    description: str
    scan: Callable[[Path], list[str]]


def find_files_with_extensions(
    root: Path, extensions: tuple[str, ...], max_depth: int | None = None
) -> list[str]:
    found: list[str] = []
    ignored_dirs = {"node_modules", ".git", "dist", "build", ".next", "coverage", ".venv", "__pycache__"}

    def walk(current: Path, depth: int) -> None:
        if max_depth is not None and depth > max_depth:
            return
        try:
            for entry in os.scandir(current):
                if entry.is_dir(follow_symlinks=False):
                    if entry.name not in ignored_dirs:
                        walk(Path(entry.path), depth + 1)
                elif entry.is_file(follow_symlinks=False) and any(
                    entry.name.endswith(ext) for ext in extensions
                ):
                    try:
                        rel = Path(entry.path).relative_to(root)
                        found.append(str(rel))
                    except ValueError:
                        found.append(entry.path)
        except (PermissionError, OSError):
            pass

    walk(root, 0)
    return sorted(found)


def scan_for_patterns(
    root: Path, target_dir: Path, patterns: list[str], extensions: tuple[str, ...] = (".py", ".ts", ".js", ".sh")
) -> list[str]:
    found: list[str] = []
    if not target_dir.exists():
        return found

    ignored_dirs = {"node_modules", ".git", "dist", "build", ".venv", "__pycache__"}

    for dirpath, dirnames, filenames in os.walk(target_dir):
        dirnames[:] = [d for d in dirnames if d not in ignored_dirs]
        for f in filenames:
            if not any(f.endswith(ext) for ext in extensions):
                continue
            p = Path(dirpath) / f
            try:
                lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
                for idx, line in enumerate(lines, start=1):
                    for pat in patterns:
                        if pat in line:
                            try:
                                rel = p.relative_to(root)
                                found.append(f"{rel}:{idx} contains {pat}")
                            except ValueError:
                                found.append(f"{p}:{idx} contains {pat}")
            except (OSError, UnicodeDecodeError):
                continue

    return sorted(found)


def find_empty_directories(root: Path) -> list[str]:
    empty: list[str] = []
    ignored_dirs = {"node_modules", ".git", "dist", "build", ".next", "coverage", ".venv", "__pycache__"}
    for base in ("src", "lib", "app", "test", "tests", "docs"):
        base_path = root / base
        if not base_path.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base_path):
            dirnames[:] = [d for d in dirnames if d not in ignored_dirs]
            dp = Path(dirpath)
            if not dirnames and not filenames:
                try:
                    rel = dp.relative_to(root)
                    empty.append(f"{rel}/")
                except ValueError:
                    empty.append(f"{dp}/")
    return sorted(empty)


def default_checks() -> list[ScannerCheck]:
    return [
        ScannerCheck(
            category="Stale Artifacts",
            name="Temporary files (*.tmp, *.bak, *.swp, ~)",
            severity="warning",
            description="Leftover temp files from editing or processing",
            scan=lambda root: find_files_with_extensions(root, (".tmp", ".bak", ".swp", "~")),
        ),
        ScannerCheck(
            category="Stale Artifacts",
            name="Debug/log files in source",
            severity="warning",
            description="Log files that should not be in source directories",
            scan=lambda root: [
                p
                for p in find_files_with_extensions(root, (".log",))
                if any(part in p.split(os.sep) for part in ("src", "lib", "app", "scripts", "skills"))
            ],
        ),
        ScannerCheck(
            category="Dead Code",
            name="Unfinished code markers (TODO, FIXME, HACK, XXX)",
            severity="info",
            description="Source code containing unfinished debt or fix markers",
            scan=lambda root: (
                scan_for_patterns(root, root / "src", ["TODO:", "FIXME:", "HACK:", "XXX:"])
                + scan_for_patterns(root, root / "scripts", ["FIXME:", "HACK:"])
                + scan_for_patterns(root, root / "lib", ["TODO:", "FIXME:"])
            ),
        ),
        ScannerCheck(
            category="Structural Violations",
            name="Missing .gitignore",
            severity="warning",
            description="No .gitignore file found -- risk of committing build artifacts",
            scan=lambda root: [] if (root / ".gitignore").exists() else [".gitignore (MISSING)"],
        ),
        ScannerCheck(
            category="Structural Violations",
            name="Build artifacts in source tree",
            severity="critical",
            description="Build outputs (dist/ or build/) nested inside source directories",
            scan=lambda root: [
                d
                for d in ("src/dist", "src/build", "lib/dist", "lib/build")
                if (root / d).exists() and (root / d).is_dir()
            ],
        ),
        ScannerCheck(
            category="Structural Violations",
            name="node_modules in source tree",
            severity="critical",
            description="node_modules directory found outside repository root",
            scan=lambda root: [
                f"{d}/node_modules/"
                for d in ("src", "lib", "app", "test", "tests")
                if (root / d / "node_modules").exists() and (root / d / "node_modules").is_dir()
            ],
        ),
        ScannerCheck(
            category="Session Cleanliness",
            name="Uncommitted WIP or scratch markers",
            severity="info",
            description="Common artifacts left behind by incomplete agent sessions",
            scan=lambda root: [
                f
                for f in (
                    "WIP.md",
                    "IN_PROGRESS.md",
                    "scratch.ts",
                    "scratch.js",
                    "scratch.py",
                    "debug.ts",
                    "debug.py",
                    "test-manual.ts",
                    "temp.ts",
                    "temp.py",
                )
                if (root / f).exists()
            ],
        ),
        ScannerCheck(
            category="Session Cleanliness",
            name="Empty directories",
            severity="info",
            description="Empty directories leftover from incomplete operations",
            scan=find_empty_directories,
        ),
        ScannerCheck(
            category="Configuration",
            name="Environment files in source",
            severity="critical",
            description=".env files that may leak confidential secrets or keys",
            scan=lambda root: [
                f
                for f in (".env", ".env.local", ".env.production", ".env.staging")
                if (root / f).exists()
            ],
        ),
    ]


def run_cleanup_scan(target_dir: Path, checks: list[ScannerCheck] | None = None) -> list[ScanResult]:
    resolved_root = target_dir.resolve()
    active_checks = checks if checks is not None else default_checks()
    results: list[ScanResult] = []

    for c in active_checks:
        found_items = c.scan(resolved_root)
        results.append(
            ScanResult(
                category=c.category,
                check=c.name,
                severity=c.severity,
                found=found_items,
                description=c.description,
            )
        )

    return results


def format_scan_report(results: list[ScanResult], target_dir: Path) -> str:
    lines: list[str] = [
        "=" * 90,
        "  CLEANUP SCANNER -- Stale Artifact & Violation Report",
        "=" * 90,
        f"  Scanning: {target_dir.resolve()}\n",
        f"| {'Category':<20}| {'Check':<40}| {'Severity':<10}| {'Count':<6}| Details",
        f"|{'-' * 21}|{'-' * 41}|{'-' * 11}|{'-' * 7}|{'-' * 30}",
    ]

    for r in results:
        count = len(r.found)
        detail = ", ".join(r.found[:2]) if count > 0 else "(clean)"
        marker = ">>" if count > 0 and r.severity == "critical" else " * " if count > 0 else "  "
        lines.append(
            f"{marker}| {r.category:<20}| {r.check:<40}| {r.severity:<10}| {count:<6}| {detail}"
        )

    criticals = [r for r in results if r.severity == "critical" and len(r.found) > 0]
    warnings = [r for r in results if r.severity == "warning" and len(r.found) > 0]
    infos = [r for r in results if r.severity == "info" and len(r.found) > 0]
    clean = [r for r in results if len(r.found) == 0]
    total_issues = sum(len(r.found) for r in results)

    lines.extend([
        "\n" + "=" * 90,
        "  CLEANUP SUMMARY",
        "=" * 90 + "\n",
        f"  Critical issues:    {len(criticals)}",
        f"  Warnings:           {len(warnings)}",
        f"  Info items:         {len(infos)}",
        f"  Clean checks:       {len(clean)}/{len(results)}",
    ])

    if criticals:
        lines.append("\n  ACTION REQUIRED (Critical):")
        for c in criticals:
            lines.append(f"    - {c.check}: {len(c.found)} item(s) found")
            lines.append(f"      {c.description}")

    if total_issues == 0:
        lines.append("\n  Project is in a clean state. No issues found.\n")
    else:
        lines.append(
            f"\n  Total issues found: {total_issues}. Run this scanner at the end of every session to maintain clean state.\n"
        )

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Cleanup Scanner: Enforce clean state across agent sessions")
    parser.add_argument("path", nargs="?", default=".", help="Project path to scan (defaults to current dir)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--strict", action="store_true", help="Fail with exit 1 on warnings as well as critical issues")
    args = parser.parse_args(argv)

    target_path = Path(args.path)
    if not target_path.exists():
        sys.stderr.write(f"Error: Target path does not exist: {target_path}\n")
        return 2

    results = run_cleanup_scan(target_path)

    if args.json:
        payload = {
            "target": str(target_path.resolve()),
            "total_issues": sum(len(r.found) for r in results),
            "results": [asdict(r) for r in results],
        }
        print(json.dumps(payload, indent=2))
    else:
        print(format_scan_report(results, target_path))

    has_critical = any(r.severity == "critical" and len(r.found) > 0 for r in results)
    has_warning = any(r.severity == "warning" and len(r.found) > 0 for r in results)
    if has_critical or (args.strict and has_warning):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
