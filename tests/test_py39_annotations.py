"""Shipped Python must import on macOS system Python 3.9.

`X | None` in an annotation is evaluated at import time on 3.9 and raises TypeError
unless the module has `from __future__ import annotations`. CI runs 3.12+, where it
works, so this is checked statically: _settings_merge.py broke install.sh's hook
wiring on 3.9 that way, unnoticed.
"""

from __future__ import annotations

import ast
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SHIPPED = ("scripts", "harness", "lib", "templates", "skills")


def _union_annotations(tree: ast.Module) -> list[int]:
    lines: list[int] = []
    for node in ast.walk(tree):
        anns: list[ast.expr | None] = []
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            a = node.args
            anns += [x.annotation for x in a.posonlyargs + a.args + a.kwonlyargs]
            anns += [a.vararg.annotation if a.vararg else None]
            anns += [a.kwarg.annotation if a.kwarg else None, node.returns]
        elif isinstance(node, ast.AnnAssign):
            anns.append(node.annotation)
        for ann in anns:
            if ann is not None and any(
                isinstance(n, ast.BinOp) and isinstance(n.op, ast.BitOr) for n in ast.walk(ann)
            ):
                lines.append(ann.lineno)
    return lines


def _has_future_annotations(tree: ast.Module) -> bool:
    return any(
        isinstance(n, ast.ImportFrom)
        and n.module == "__future__"
        and any(a.name == "annotations" for a in n.names)
        for n in tree.body
    )


def test_union_annotations_have_the_future_import() -> None:
    bad = []
    for top in SHIPPED:
        for path in sorted((REPO_ROOT / top).rglob("*.py")):
            if "/tests/" in str(path) or "__pycache__" in str(path):
                continue
            tree = ast.parse(path.read_text(encoding="utf-8"))
            lines = _union_annotations(tree)
            if lines and not _has_future_annotations(tree):
                bad.append(f"{path.relative_to(REPO_ROOT)}:{lines[0]}")
    assert bad == [], "add `from __future__ import annotations`: " + ", ".join(bad)
