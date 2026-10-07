#!/usr/bin/env python3
"""
hidden_accept.py — Independent automated test suite for kvstore CLI.
Tests F1 through F5.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


def run_cmd(cwd: Path, args: list[str]) -> tuple[int, str, str]:
    res = subprocess.run(
        [sys.executable, "kvstore.py"] + args,
        cwd=cwd,
        capture_output=True,
        text=True
    )
    return res.returncode, res.stdout, res.stderr


def test_repo(repo_dir: Path) -> dict[str, bool]:
    results = {
        "F1_put_get": False,
        "F2_delete": False,
        "F3_list_prefix": False,
        "F4_export_json": False,
        "F5_stats": False,
    }

    # Clean store file if present
    store_file = repo_dir / "store.json"
    if store_file.exists():
        store_file.unlink()

    # Test F1
    try:
        rc, out, _ = run_cmd(repo_dir, ["put", "apple", "red"])
        if rc == 0:
            rc, out, _ = run_cmd(repo_dir, ["get", "apple"])
            if rc == 0 and "red" in out:
                rc, _, _ = run_cmd(repo_dir, ["get", "missing_key"])
                if rc == 1:
                    results["F1_put_get"] = True
    except Exception:
        pass

    # Test F2
    try:
        run_cmd(repo_dir, ["put", "banana", "yellow"])
        rc, _, _ = run_cmd(repo_dir, ["delete", "banana"])
        if rc == 0:
            rc, _, _ = run_cmd(repo_dir, ["get", "banana"])
            if rc == 1:
                rc2, _, _ = run_cmd(repo_dir, ["delete", "banana"])
                if rc2 == 1:
                    results["F2_delete"] = True
    except Exception:
        pass

    # Test F3
    try:
        run_cmd(repo_dir, ["put", "user:1", "alice"])
        run_cmd(repo_dir, ["put", "user:2", "bob"])
        run_cmd(repo_dir, ["put", "item:1", "book"])
        rc, out, _ = run_cmd(repo_dir, ["list", "--prefix", "user:"])
        lines = [line.strip() for line in out.strip().splitlines() if line.strip()]
        if rc == 0 and lines == ["user:1", "user:2"]:
            results["F3_list_prefix"] = True
    except Exception:
        pass

    # Test F4
    try:
        rc, out, _ = run_cmd(repo_dir, ["export", "--json"])
        if rc == 0:
            data = json.loads(out)
            if isinstance(data, dict) and data.get("apple") == "red":
                results["F4_export_json"] = True
    except Exception:
        pass

    # Test F5
    try:
        rc, out, _ = run_cmd(repo_dir, ["stats"])
        if rc == 0:
            data = json.loads(out)
            if "count" in data and "size_bytes" in data and isinstance(data["count"], int):
                results["F5_stats"] = True
    except Exception:
        pass

    return results


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    res = test_repo(target)
    passed = sum(1 for v in res.values() if v)
    total = len(res)
    print(f"Results for {target}: {passed}/{total} passed")
    for k, v in res.items():
        print(f"  {k}: {'PASS' if v else 'FAIL'}")
    sys.exit(0 if passed == total else 1)
