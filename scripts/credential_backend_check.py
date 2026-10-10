#!/usr/bin/env python3
"""Check that every credential dispatch handles every backend _os() can return.

_store.sh picks a storage backend with `case "$(_os)" in`. Each such dispatch is
a separate switch, so a backend added to _os() -- or simply forgotten in one
function -- fails silently: the case falls through, the function returns 0, and
the caller sees success with nothing done. That is how list_credentials and
delete_credential shipped without a linux-file branch, printing an empty listing
and reporting a delete that never happened, green on macOS and red on CI.

Usage: credential-backend-check.py <path-to-_store.sh>
Exit 0 when every dispatch is complete, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# `unknown` is _os()'s unsupported-platform sentinel, not a storage backend:
# there is no keychain to dispatch to, so a missing branch is not the bug this
# check is about. Kept out of the required set deliberately.
SENTINELS = {"unknown"}

_FUNC_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")
_CASE_OPEN_RE = re.compile(r'case\s+"\$\(_os\)"\s+in')
_LABEL_RE = re.compile(r"^\s*([A-Za-z0-9_|*\-]+)\)")


def _os_emitted(lines: list[str]) -> set[str]:
    """Values _os() can echo."""
    out: set[str] = set()
    inside = False
    for line in lines:
        if _FUNC_RE.match(line) and line.startswith("_os"):
            inside = True
            continue
        if inside:
            if line.startswith("}"):
                break
            for m in re.finditer(r'echo\s+"([a-z0-9\-]+)"', line):
                out.add(m.group(1))
    return out


def _dispatches(lines: list[str]) -> list[tuple[str, int, set[str]]]:
    """Every `case "$(_os)"` block: (enclosing function, line number, labels)."""
    found: list[tuple[str, int, set[str]]] = []
    func = "<top level>"
    for i, line in enumerate(lines):
        fm = _FUNC_RE.match(line)
        if fm:
            func = fm.group(1)
        if not _CASE_OPEN_RE.search(line):
            continue
        labels: set[str] = set()
        depth = 0
        for body in lines[i + 1 :]:
            if _CASE_OPEN_RE.search(body):
                depth += 1
                continue
            if body.strip().startswith("esac"):
                if depth == 0:
                    break
                depth -= 1
                continue
            if depth:
                continue
            lm = _LABEL_RE.match(body)
            if lm:
                labels.update(lm.group(1).split("|"))
        found.append((func, i + 1, labels))
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {Path(argv[0]).name} <path-to-_store.sh>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    if not path.is_file():
        print(f"not a file: {path}", file=sys.stderr)
        return 2

    lines = path.read_text().split("\n")
    emitted = _os_emitted(lines)
    if not emitted:
        print(f"{path}: could not find _os() or it echoes nothing", file=sys.stderr)
        return 2
    required = emitted - SENTINELS

    problems: list[str] = []
    notes: list[str] = []
    for func, lineno, labels in _dispatches(lines):
        if "*" in labels:
            continue  # a catch-all cannot fall through
        missing = sorted(required - labels)
        if missing:
            problems.append(
                f"{path}:{lineno}: {func} does not handle: {', '.join(missing)}"
            )
        unreachable = sorted(labels - emitted - {"*"})
        if unreachable:
            notes.append(
                f"{path}:{lineno}: {func} handles a value _os() never returns: "
                f"{', '.join(unreachable)}"
            )

    for note in notes:
        print(f"note: {note}")

    if problems:
        print(
            f"_os() can return: {', '.join(sorted(required))}"
            f"  (sentinels excluded: {', '.join(sorted(SENTINELS))})",
            file=sys.stderr,
        )
        for p in problems:
            print(p, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
