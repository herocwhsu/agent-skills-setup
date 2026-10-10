#!/usr/bin/env python3
"""
Harness Creator Training - Lecture 04: Exercise 3 Follow-up
Position Experiment Scaled to ~10k Tokens Without "Read In Full"

Measures compliance to an incidental rule ('Script Ownership Header')
at Top (15%), Middle (50%), and Bottom (85%) depth within a ~10k-token
monolithic context on Haiku 4.5.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]

RULE_SNIPPET = """
## Script Ownership Header

Every new `*.sh` file must have `# owner: harness-team` as its second line, directly after the shebang.
"""

PROMPT_INCIDENTAL = (
    'Create scripts/export_stats.py that prints JSON {"skills_count": 15}, '
    'and create a companion shell script scripts/export_stats.sh that runs it with python3. '
    'Make scripts/export_stats.sh executable and run it to verify.'
)


@dataclass
class RunResult:
    condition: str
    run_idx: int
    rule_followed: bool
    sh_exists: bool
    sh_executable: bool
    python_valid: bool
    exit_code: int
    duration_s: float
    line2_content: str
    error: str = ""


def build_base_monolithic_text() -> list[str]:
    p_eng = (REPO_ROOT / "agents/engineering-rules.md").read_text(encoding="utf-8")
    p_arch = (REPO_ROOT / "docs/architecture.md").read_text(encoding="utf-8")
    p_agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
    p_skills = (REPO_ROOT / "skills/README.md").read_text(encoding="utf-8")
    p_spec = (REPO_ROOT / "docs/spec-gated-workflow.md").read_text(encoding="utf-8")[:18000]

    combined = p_eng + "\n\n" + p_arch + "\n\n" + p_agents + "\n\n" + p_skills + "\n\n" + p_spec
    return combined.splitlines()


def inject_rule(lines: list[str], depth_ratio: float) -> str:
    insert_idx = int(len(lines) * depth_ratio)
    new_lines = list(lines)
    rule_lines = RULE_SNIPPET.strip().splitlines()
    new_lines[insert_idx:insert_idx] = ["", *rule_lines, ""]
    return "\n".join(new_lines)


def run_one_trial(condition: str, run_idx: int, doc_text: str, sandbox_root: Path) -> RunResult:
    sandbox = sandbox_root / f"{condition}_{run_idx}"
    shutil.rmtree(sandbox, ignore_errors=True)
    sandbox.mkdir(parents=True, exist_ok=True)

    (sandbox / "CLAUDE.md").write_text(doc_text, encoding="utf-8")
    (sandbox / "AGENTS.md").write_text(doc_text, encoding="utf-8")

    cmd = [
        "claude",
        "--model",
        "haiku",
        "--permission-mode",
        "acceptEdits",
        "-p",
        PROMPT_INCIDENTAL,
    ]

    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(sandbox),
            capture_output=True,
            text=True,
            timeout=120,
        )
        duration = round(time.monotonic() - t0, 2)
        rc = proc.returncode
        err_msg = proc.stderr.strip()[:200] if rc != 0 else ""
    except subprocess.TimeoutExpired:
        duration = round(time.monotonic() - t0, 2)
        return RunResult(
            condition=condition,
            run_idx=run_idx,
            rule_followed=False,
            sh_exists=False,
            sh_executable=False,
            python_valid=False,
            exit_code=124,
            duration_s=duration,
            line2_content="",
            error="timeout after 120s",
        )
    except Exception as e:
        duration = round(time.monotonic() - t0, 2)
        return RunResult(
            condition=condition,
            run_idx=run_idx,
            rule_followed=False,
            sh_exists=False,
            sh_executable=False,
            python_valid=False,
            exit_code=1,
            duration_s=duration,
            line2_content="",
            error=str(e),
        )

    # Evaluation
    sh_file = sandbox / "scripts" / "export_stats.sh"
    py_file = sandbox / "scripts" / "export_stats.py"

    sh_exists = sh_file.exists()
    sh_exec = os.access(sh_file, os.X_OK) if sh_exists else False

    line2 = ""
    rule_followed = False
    if sh_exists:
        sh_lines = sh_file.read_text(encoding="utf-8", errors="replace").splitlines()
        if len(sh_lines) >= 2:
            line2 = sh_lines[1].strip()
            rule_followed = line2 == "# owner: harness-team"

    py_valid = False
    if py_file.exists():
        try:
            r = subprocess.run(
                [sys.executable, str(py_file)],
                capture_output=True,
                text=True,
                timeout=5,
            )
            data = json.loads(r.stdout.strip())
            py_valid = data.get("skills_count") == 15
        except Exception:
            py_valid = False

    return RunResult(
        condition=condition,
        run_idx=run_idx,
        rule_followed=rule_followed,
        sh_exists=sh_exists,
        sh_executable=sh_exec,
        python_valid=py_valid,
        exit_code=rc,
        duration_s=duration,
        line2_content=line2,
        error=err_msg,
    )


def main() -> int:
    runs_per_condition = 5
    if len(sys.argv) > 1:
        try:
            runs_per_condition = int(sys.argv[1])
        except ValueError:
            pass

    print("=" * 80)
    print("  HARNESS CREATOR TRAINING — LECTURE 04")
    print("  Position Bias Scaling Experiment (~10k Tokens, Incidental Rule)")
    print("=" * 80)

    base_lines = build_base_monolithic_text()
    raw_chars = sum(len(l) + 1 for l in base_lines)
    est_tokens = raw_chars // 4
    print(f"Base context size: {len(base_lines)} lines, {raw_chars} chars, ~{est_tokens} tokens")
    print(f"Model under test: Haiku 4.5 via claude CLI")
    print(f"Runs per condition: {runs_per_condition} (Total: {runs_per_condition * 3})")
    print("-" * 80)

    conditions = [
        ("top", 0.15),
        ("middle", 0.50),
        ("bottom", 0.85),
    ]

    sandbox_root = Path("/tmp/pos_exp_10k")
    sandbox_root.mkdir(parents=True, exist_ok=True)

    results: list[RunResult] = []

    for name, depth in conditions:
        doc = inject_rule(base_lines, depth)
        print(f"\nEvaluating Condition [{name.upper()}] (depth: {int(depth * 100)}%):")
        for i in range(1, runs_per_condition + 1):
            res = run_one_trial(name, i, doc, sandbox_root)
            results.append(res)
            status = "FOLLOWED" if res.rule_followed else "MISSED"
            line2_disp = f" (line 2: {res.line2_content!r})" if res.line2_content else " (no line 2)"
            print(
                f"  Run {i}/{runs_per_condition}: [{status}] in {res.duration_s}s"
                f"{line2_disp} | sh_exec={res.sh_executable} py_valid={res.python_valid}"
            )

    # Aggregation
    print("\n" + "=" * 80)
    print("EXPERIMENT SUMMARY RESULTS")
    print("=" * 80)
    print(
        f"{'Condition':<10} | {'Depth':<8} | {'Rule Followed':<14} | {'Script Executable':<18} | {'Py Valid':<10} | {'Avg Time':<8}"
    )
    print("-" * 80)

    summary_data: dict[str, Any] = {}
    for name, depth in conditions:
        cond_results = [r for r in results if r.condition == name]
        followed_count = sum(1 for r in cond_results if r.rule_followed)
        exec_count = sum(1 for r in cond_results if r.sh_executable)
        py_count = sum(1 for r in cond_results if r.python_valid)
        avg_dur = sum(r.duration_s for r in cond_results) / len(cond_results)
        pct = (followed_count / len(cond_results)) * 100

        summary_data[name] = {
            "depth_pct": int(depth * 100),
            "followed": followed_count,
            "total": len(cond_results),
            "followed_pct": pct,
            "exec_count": exec_count,
            "py_count": py_count,
            "avg_duration_s": round(avg_dur, 2),
        }

        print(
            f"{name:<10} | {int(depth * 100):>5}%   | {followed_count}/{len(cond_results)} ({pct:>5.1f}%)   | "
            f"{exec_count}/{len(cond_results)} ({exec_count/len(cond_results)*100:>5.1f}%)     | "
            f"{py_count}/{len(cond_results)} ({py_count/len(cond_results)*100:>5.1f}%) | "
            f"{avg_dur:>5.1f}s"
        )

    print("=" * 80)

    # Save results json
    out_json = REPO_ROOT / "docs/harness-creator/lecture-04/position-scaling-results.json"
    out_json.write_text(
        json.dumps(
            {
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "model": "haiku",
                "est_tokens": est_tokens,
                "summary": summary_data,
                "runs": [asdict(r) for r in results],
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\nRaw results saved to {out_json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
