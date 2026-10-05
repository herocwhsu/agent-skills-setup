# outside-agent selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One installed command, `~/.agent-skills-setup/outside-agent.sh`, that picks a working outside CLI agent per call from a per-machine list, skips usage-limited or logged-out ones, and enforces cross-family review.

**Architecture:** Logic lives in `scripts/outside_agent.py` (stdlib only, Python ≥3.12), split into pure functions (classify, reset time, order, independence) and an I/O shell (pre-checks, run, state, conf). `scripts/outside-agent.sh` is a 3-line wrapper. `install_runtime_dir` copies both to the runtime dir; `install.sh` runs `init` at the end, and `update.sh` reaches it through `install.sh`. A new `runtime-drift-guard.sh` checks that the installed copies match the repo.

**Tech Stack:** Python 3.12+ stdlib (`argparse`, `json`, `subprocess`, `concurrent.futures`, `datetime`, `re`), bash 3.2-compatible shell, pytest.

**Spec:** `docs/superpowers/specs/2026-10-05-outside-agent-design.md`

## Global Constraints

- Python floor: `requires-python = ">=3.12"`; stdlib only, no new dependency in `requirements-dev.txt` or `registry.txt`.
- Shell: bash 3.2 compatible (no `mapfile`, `declare -A`, `;&`); `bash-compat-guard.sh` enforces.
- Tests never touch the real `~`: every test sets `HOME` to a temp dir.
- No comments unless the WHY is non-obvious.
- Default conf order: `claude-kiro, codex-kiro, agy, claude, codex`.
- Rate-limit phrases (case-insensitive), exactly: `usage limit`, `quota`, `limit reached`. Bare `429` / `rate limit` are NOT rate-limit.
- Auth phrases: `Not logged in`, `401`, `Unauthorized`, `/login`.
- Cooldowns: `agy`/`claude`/`codex` 5 hours; quota group `kiro` until 00:00 local on the 1st of next month; auth demotion 7 days.
- Exit codes: 0 success, 2 nothing succeeded / unknown error / bad conf, 3 review same-family only.
- `--from` is required; values `claude|openai|gemini`.
- `install-agents-md.sh` is NOT run by this plan (owner approval required).
- Commit subjects: single line, `type: description`, no trailers.

## Review Focus

1. A candidate that prints an auth phrase inside a *successful* long answer (e.g. a review that quotes "401") must not be misclassified — classification only applies on non-zero exit, or on exit 0 with short output (≤ 200 chars) matching the phrase. Pinned in Task 1.
2. Conf with blank lines, comments, trailing spaces, or CRLF must parse to the same list. Pinned in Task 3.
3. State file missing, empty, or corrupt JSON must behave as "no records", not crash `run`. Pinned in Task 3.
4. A kiro rate-limit recorded in December must reset on 1 January of the next year, not month 13. Pinned in Task 1.
5. `run` with every candidate rate-limited must print the earliest reset time and exit 2, never call any agent. Pinned in Task 4.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/outside_agent.py` | All logic: kinds table, classify, reset, ordering, state, conf, pre-checks, run, CLI |
| `scripts/outside-agent.sh` | Wrapper: `exec python3 "$(dirname "$0")/outside_agent.py" "$@"` |
| `tests/test_outside_agent.py` | Unit tests (pure functions) + CLI tests with stub agents on `PATH` |
| `scripts/_lib.sh` | `install_runtime_dir` also copies the two new files |
| `scripts/install.sh` | Calls `init` after the agent loop, failure-tolerant |
| `.claude/hooks/runtime-drift-guard.sh` | Blocks when installed runtime copies differ from repo |
| `.claude/hooks/tests/test_runtime_drift_guard.sh` | Guard fixture test |
| `scripts/harness-verify.sh`, `.claude/settings.json` | Wire the guard |
| `agents/engineering-rules.md` | The rule lines |
| `scripts/tests/test_engineering_rules_scope.sh` | Rule present and host-neutral |
| `feature_list.json`, `PROGRESS.md` | feat-035 |

---

### Task 1: Pure logic — classify, reset time, ordering, independence

**Files:**
- Create: `scripts/outside_agent.py`
- Create: `tests/test_outside_agent.py`

**Interfaces:**
- Produces:
  - `KINDS: dict[str, Kind]` where `Kind = NamedTuple(name: str, group: str, family: str)`, with entries for `claude-kiro` (kiro, claude), `codex-kiro` (kiro, openai), `agy` (agy, gemini), `claude` (claude, claude), `codex` (codex, openai).
  - `DEFAULT_ORDER: list[str]`
  - `classify(rc: int, output: str, timed_out: bool) -> str` returning `"ok"|"auth"|"rate_limit"|"transient"|"error"`
  - `rate_limit_reset(group: str, now: datetime, output: str) -> datetime` (aware datetimes, local tz)
  - `order_candidates(conf: list[str], records: dict, now: datetime, purpose: str, caller: str) -> tuple[list[str], list[tuple[str, str]]]` returning `(to_try, skipped)` where skipped items are `(name, reason)`
  - `records` shape: `{"groups": {group: {"until": iso}}, "auth": {name: {"until": iso}}}`

- [ ] **Step 1: Write failing tests**

```python
"""Tests for scripts/outside_agent.py."""

import sys
from datetime import datetime, timedelta
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import outside_agent as oa  # noqa: E402

TZ = datetime.now().astimezone().tzinfo
NOW = datetime(2026, 10, 5, 12, 0, tzinfo=TZ)


@pytest.mark.parametrize(
    "rc,out,expected",
    [
        (0, "OK", "ok"),
        (0, "Not logged in · Please run /login", "auth"),
        (1, "ERROR: unexpected status 401 Unauthorized", "auth"),
        (1, "You've hit your usage limit", "rate_limit"),
        (1, "Monthly QUOTA exceeded", "rate_limit"),
        (1, "limit reached, try later", "rate_limit"),
        (1, "HTTP 429 Too Many Requests", "error"),
        (1, "rate limit exceeded", "error"),
        (1, "segfault", "error"),
    ],
)
def test_classify(rc, out, expected):
    assert oa.classify(rc, out, timed_out=False) == expected


def test_classify_timeout_is_transient():
    assert oa.classify(124, "", timed_out=True) == "transient"


def test_long_successful_answer_quoting_401_is_ok():
    answer = "Review: the handler returns 401 Unauthorized when the token is absent. " * 5
    assert oa.classify(0, answer, timed_out=False) == "ok"


def test_empty_success_is_error():
    assert oa.classify(0, "   ", timed_out=False) == "error"


def test_reset_five_hours_for_subscription_groups():
    for g in ("agy", "claude", "codex"):
        assert oa.rate_limit_reset(g, NOW, "usage limit") == NOW + timedelta(hours=5)


def test_reset_kiro_first_of_next_month():
    assert oa.rate_limit_reset("kiro", NOW, "quota") == datetime(2026, 11, 1, tzinfo=TZ)


def test_reset_kiro_december_rolls_year():
    dec = datetime(2026, 12, 15, 9, 0, tzinfo=TZ)
    assert oa.rate_limit_reset("kiro", dec, "quota") == datetime(2027, 1, 1, tzinfo=TZ)


def test_reset_parses_explicit_time():
    out = "usage limit reached, resets at 2026-10-05T15:30:00"
    assert oa.rate_limit_reset("claude", NOW, out) == datetime(2026, 10, 5, 15, 30, tzinfo=TZ)


def test_reset_ignores_explicit_time_in_past():
    out = "usage limit, resets at 2026-10-01T00:00:00"
    assert oa.rate_limit_reset("claude", NOW, out) == NOW + timedelta(hours=5)


def _until(dt):
    return {"until": dt.isoformat()}


CONF = ["claude-kiro", "codex-kiro", "agy", "claude", "codex"]


def test_order_delegate_keeps_conf_order():
    to_try, skipped = oa.order_candidates(CONF, {}, NOW, "delegate", "claude")
    assert to_try == CONF and skipped == []


def test_kiro_group_skips_both_kinds():
    rec = {"groups": {"kiro": _until(NOW + timedelta(days=3))}}
    to_try, skipped = oa.order_candidates(CONF, rec, NOW, "delegate", "claude")
    assert to_try == ["agy", "claude", "codex"]
    assert [n for n, _ in skipped] == ["claude-kiro", "codex-kiro"]


def test_expired_rate_limit_not_skipped():
    rec = {"groups": {"kiro": _until(NOW - timedelta(seconds=1))}}
    to_try, _ = oa.order_candidates(CONF, rec, NOW, "delegate", "claude")
    assert to_try == CONF


def test_auth_demotes_to_end_not_skipped():
    rec = {"auth": {"claude-kiro": _until(NOW + timedelta(days=2))}}
    to_try, skipped = oa.order_candidates(CONF, rec, NOW, "delegate", "claude")
    assert to_try[-1] == "claude-kiro" and len(to_try) == 5 and skipped == []


def test_review_puts_own_family_last():
    to_try, _ = oa.order_candidates(CONF, {}, NOW, "review", "claude")
    assert to_try == ["codex-kiro", "agy", "codex", "claude-kiro", "claude"]


def test_review_from_gemini():
    to_try, _ = oa.order_candidates(CONF, {}, NOW, "review", "gemini")
    assert to_try[-1] == "agy"
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q`
Expected: FAIL, `ModuleNotFoundError: No module named 'outside_agent'`

- [ ] **Step 3: Implement**

```python
#!/usr/bin/env python3
"""Pick a working outside CLI agent per call. See docs/superpowers/specs/2026-10-05-outside-agent-design.md."""

from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import NamedTuple


class Kind(NamedTuple):
    name: str
    group: str
    family: str


KINDS: dict[str, Kind] = {
    k.name: k
    for k in (
        Kind("claude-kiro", "kiro", "claude"),
        Kind("codex-kiro", "kiro", "openai"),
        Kind("agy", "agy", "gemini"),
        Kind("claude", "claude", "claude"),
        Kind("codex", "codex", "openai"),
    )
}
DEFAULT_ORDER = ["claude-kiro", "codex-kiro", "agy", "claude", "codex"]
FAMILIES = ("claude", "openai", "gemini")

AUTH_RE = re.compile(r"not logged in|\b401\b|unauthorized|/login", re.I)
RATE_RE = re.compile(r"usage limit|quota|limit reached", re.I)
RESET_RE = re.compile(r"(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?)")
# A real answer can quote "401"; only short output is treated as a status message.
SHORT = 200
AUTH_DEMOTE = timedelta(days=7)
SUB_COOLDOWN = timedelta(hours=5)


def classify(rc: int, output: str, timed_out: bool) -> str:
    if timed_out:
        return "transient"
    text = output.strip()
    if rc == 0 and len(text) > SHORT:
        return "ok"
    if RATE_RE.search(text):
        return "rate_limit"
    if AUTH_RE.search(text):
        return "auth"
    if rc == 0 and text:
        return "ok"
    return "error"


def _first_of_next_month(now: datetime) -> datetime:
    y, m = (now.year + 1, 1) if now.month == 12 else (now.year, now.month + 1)
    return now.replace(year=y, month=m, day=1, hour=0, minute=0, second=0, microsecond=0)


def rate_limit_reset(group: str, now: datetime, output: str) -> datetime:
    m = RESET_RE.search(output)
    if m:
        try:
            t = datetime.fromisoformat(m.group(1).replace(" ", "T"))
            t = t if t.tzinfo else t.replace(tzinfo=now.tzinfo)
            if t > now:
                return t
        except ValueError:
            pass
    if group == "kiro":
        return _first_of_next_month(now)
    return now + SUB_COOLDOWN


def _active(entry: dict | None, now: datetime) -> datetime | None:
    if not entry:
        return None
    try:
        until = datetime.fromisoformat(entry["until"])
    except (KeyError, TypeError, ValueError):
        return None
    return until if until > now else None


def order_candidates(
    conf: list[str], records: dict, now: datetime, purpose: str, caller: str
) -> tuple[list[str], list[tuple[str, str]]]:
    groups = records.get("groups", {})
    auth = records.get("auth", {})
    live: list[str] = []
    skipped: list[tuple[str, str]] = []
    for name in conf:
        until = _active(groups.get(KINDS[name].group), now)
        if until:
            skipped.append((name, f"rate_limit until {until:%Y-%m-%d %H:%M}"))
        else:
            live.append(name)
    fresh = [n for n in live if not _active(auth.get(n), now)]
    demoted = [n for n in live if _active(auth.get(n), now)]
    ordered = fresh + demoted
    if purpose == "review":
        ordered = [n for n in ordered if KINDS[n].family != caller] + [
            n for n in ordered if KINDS[n].family == caller
        ]
    return ordered, skipped
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q`
Expected: all pass (the review-order tests pass because fresh/demoted ordering is applied before the family split).

- [ ] **Step 5: Type-check and commit**

Run: `.venv/bin/mypy .` → `Success`
```bash
git add scripts/outside_agent.py tests/test_outside_agent.py
git commit -m "feat(outside-agent): add classification, reset and ordering logic"
```

---

### Task 2: Pre-checks and the runner

**Files:**
- Modify: `scripts/outside_agent.py`
- Modify: `tests/test_outside_agent.py`

**Interfaces:**
- Consumes: `KINDS`, `classify`.
- Produces:
  - `precheck(name: str, env: dict[str, str]) -> str | None` — `None` = pass, else a reason string.
  - `build_argv(name: str, prompt: str, purpose: str, allow_edits: bool) -> list[str]`
  - `run_one(name: str, prompt: str, purpose: str, allow_edits: bool, timeout: int, cwd: str | None) -> tuple[str, str]` returning `(class, output)`.
  - Env seams (tests only): `OUTSIDE_AGENT_GATEWAY` (default `http://localhost:7788`), `OUTSIDE_AGENT_SHELL` (default `zsh`).

Kiro kinds run through `$OUTSIDE_AGENT_SHELL -i -c '<alias> ...'`. Pre-check for them: `$SHELL -i -c 'alias <name>'` exits 0, and an HTTP GET of `$GATEWAY/openapi.json` returns 200 within 1s. Keychain is not checked separately: the alias reads it, and an empty key surfaces as `auth`. `claude` pre-check: `security find-generic-password -s "Claude Code-credentials"` succeeds (skipped when `security` is absent, so Linux falls through to run-time classification). `codex` pre-check: `~/.codex/auth.json` exists. `agy`: on PATH.

Run env always drops `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_BASE_URL`, `OPENAI_API_KEY` for the plain `claude` and `codex` kinds.

Read-only flags: `claude*` → `--permission-mode plan` (with `--allow-edits` → `acceptEdits`); `codex*` → `-s read-only` (→ `-s workspace-write`); `agy` → `--mode plan` (→ `--mode accept-edits`). Review ignores `--allow-edits`.

- [ ] **Step 1: Write failing tests**

```python
import os
import stat
import subprocess


def _stub(dir_: Path, name: str, body: str) -> None:
    p = dir_ / name
    p.write_text("#!/bin/sh\n" + body + "\n")
    p.chmod(p.stat().st_mode | stat.S_IEXEC)


@pytest.fixture
def stubenv(tmp_path, monkeypatch):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("PATH", f"{bin_}:/usr/bin:/bin")
    monkeypatch.setenv("OUTSIDE_AGENT_GATEWAY", "http://127.0.0.1:9")
    return bin_, home


def test_build_argv_review_is_read_only():
    assert "--permission-mode" in oa.build_argv("claude", "p", "review", True)
    assert oa.build_argv("claude", "p", "review", True)[
        oa.build_argv("claude", "p", "review", True).index("--permission-mode") + 1
    ] == "plan"
    assert oa.build_argv("agy", "p", "review", False)[-3:-1] == ["--mode", "plan"]
    assert "read-only" in oa.build_argv("codex", "p", "review", True)


def test_build_argv_delegate_allow_edits():
    argv = oa.build_argv("claude", "p", "delegate", True)
    assert argv[argv.index("--permission-mode") + 1] == "acceptEdits"
    assert "workspace-write" in oa.build_argv("codex", "p", "delegate", True)


def test_build_argv_kiro_uses_interactive_shell(monkeypatch):
    monkeypatch.setenv("OUTSIDE_AGENT_SHELL", "zsh")
    argv = oa.build_argv("codex-kiro", "say 'hi'", "review", False)
    assert argv[:3] == ["zsh", "-i", "-c"]
    assert argv[3].startswith("codex-kiro exec --skip-git-repo-check")
    assert "'\"'\"'" in argv[3] or "\\'" in argv[3]


def test_precheck_kiro_fails_when_gateway_down(stubenv):
    assert oa.precheck("claude-kiro", dict(os.environ)) is not None


def test_precheck_codex_needs_auth_json(stubenv):
    bin_, home = stubenv
    _stub(bin_, "codex", "echo OK")
    assert oa.precheck("codex", dict(os.environ)) == "no ~/.codex/auth.json"
    (home / ".codex").mkdir()
    (home / ".codex" / "auth.json").write_text("{}")
    assert oa.precheck("codex", dict(os.environ)) is None


def test_precheck_missing_command(stubenv):
    assert oa.precheck("agy", dict(os.environ)) == "agy not on PATH"


def test_run_one_strips_inherited_anthropic_env(stubenv, monkeypatch):
    bin_, _ = stubenv
    _stub(bin_, "claude", 'if [ -n "$ANTHROPIC_API_KEY" ]; then echo LEAKED; else echo "Not logged in"; fi')
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-inherited")
    assert oa.run_one("claude", "p", "review", False, 10, None) == ("auth", "Not logged in")


def test_run_one_strips_escape_sequences(stubenv):
    bin_, _ = stubenv
    _stub(bin_, "agy", r"printf '\033]1337;CurrentDir=/tmp\007OK\n'")
    assert oa.run_one("agy", "p", "review", False, 10, None) == ("ok", "OK")


def test_run_one_timeout_is_transient(stubenv):
    bin_, _ = stubenv
    _stub(bin_, "agy", "sleep 5")
    assert oa.run_one("agy", "p", "review", False, 1, None)[0] == "transient"
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q`
Expected: FAIL, `AttributeError: module 'outside_agent' has no attribute 'build_argv'`

- [ ] **Step 3: Implement** (append to `scripts/outside_agent.py`; add `import os, shlex, shutil, subprocess, urllib.request` and `from pathlib import Path` at the top)

```python
STRIP_ENV = (
    "ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
    "OPENAI_BASE_URL", "OPENAI_API_KEY",
)
ESC_RE = re.compile(r"\x1b\][^\x07]*\x07|\x1b\[[0-9;?]*[A-Za-z]")


def _shell() -> str:
    return os.environ.get("OUTSIDE_AGENT_SHELL", "zsh")


def _gateway_up() -> bool:
    url = os.environ.get("OUTSIDE_AGENT_GATEWAY", "http://localhost:7788") + "/openapi.json"
    try:
        with urllib.request.urlopen(url, timeout=1) as r:
            return bool(r.status == 200)
    except OSError:
        return False


def precheck(name: str, env: dict[str, str]) -> str | None:
    if KINDS[name].group == "kiro":
        # stdin closed: an interactive zsh with no ~/.zshrc otherwise opens zsh-newuser-install.
        if subprocess.run([_shell(), "-i", "-c", f"alias {name}"], capture_output=True,
                          env=env, timeout=10, stdin=subprocess.DEVNULL).returncode != 0:
            return f"alias {name} not defined"
        return None if _gateway_up() else "kiro-gateway not answering"
    if not shutil.which(name, path=env.get("PATH")):
        return f"{name} not on PATH"
    if name == "claude" and shutil.which("security", path=env.get("PATH")):
        r = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials"],
                           capture_output=True)
        return None if r.returncode == 0 else "no Claude Code login"
    if name == "codex" and not (Path(env.get("HOME", "")) / ".codex" / "auth.json").exists():
        return "no ~/.codex/auth.json"
    return None


def _perm(name: str, purpose: str, allow_edits: bool) -> list[str]:
    edit = allow_edits and purpose == "delegate"
    if name.startswith("claude"):
        return ["--permission-mode", "acceptEdits" if edit else "plan"]
    if name.startswith("codex"):
        return ["-s", "workspace-write" if edit else "read-only"]
    return ["--mode", "accept-edits" if edit else "plan"]


def build_argv(name: str, prompt: str, purpose: str, allow_edits: bool) -> list[str]:
    perm = _perm(name, purpose, allow_edits)
    if name in ("claude", "claude-kiro"):
        argv = [name, "-p", *perm, prompt]
    elif name in ("codex", "codex-kiro"):
        argv = [name, "exec", "--skip-git-repo-check", *perm, prompt]
    else:
        argv = ["agy", "-p", *perm, prompt]
    if KINDS[name].group == "kiro":
        return [_shell(), "-i", "-c", shlex.join(argv)]
    return argv


def run_one(name: str, prompt: str, purpose: str, allow_edits: bool,
            timeout: int, cwd: str | None) -> tuple[str, str]:
    env = dict(os.environ)
    if KINDS[name].group != "kiro":
        for k in STRIP_ENV:
            env.pop(k, None)
    try:
        r = subprocess.run(build_argv(name, prompt, purpose, allow_edits), capture_output=True,
                           text=True, env=env, cwd=cwd, timeout=timeout, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "transient", f"timed out after {timeout}s"
    out = ESC_RE.sub("", (r.stdout or "") + (r.stderr if r.returncode else "")).strip()
    return classify(r.returncode, out, timed_out=False), out
```

Note: for `ok`, only stdout is returned (stderr is merged only on failure so its message reaches `classify`).

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q` → all pass. If `test_run_one_strips_inherited_anthropic_env` prints `LEAKED`, the env strip is wrong; fix before continuing.

- [ ] **Step 5: Type-check and commit**

Run: `.venv/bin/mypy .` → `Success`
```bash
git add scripts/outside_agent.py tests/test_outside_agent.py
git commit -m "feat(outside-agent): add pre-checks and isolated agent runner"
```

---

### Task 3: State and conf files

**Files:**
- Modify: `scripts/outside_agent.py`
- Modify: `tests/test_outside_agent.py`

**Interfaces:**
- Produces:
  - `runtime_dir() -> Path` — `$HOME/.agent-skills-setup` (overridable by `OUTSIDE_AGENT_DIR` for tests that need it; default is the real convention).
  - `conf_path() -> Path`, `state_path() -> Path` (`state/outside-agents.json`)
  - `read_conf() -> list[str]` — raises `ConfError(msg)` on unknown name or missing file.
  - `write_conf(live: list[str], failed: list[tuple[str, str]], today: str) -> None`
  - `load_state() -> dict`, `save_state(d: dict) -> None` (atomic: write tmp + `os.replace`)
  - `record(state: dict, name: str, cls: str, until: datetime) -> None`

- [ ] **Step 1: Write failing tests**

```python
def test_read_conf_tolerates_comments_blank_crlf(stubenv):
    _, home = stubenv
    d = home / ".agent-skills-setup"
    d.mkdir()
    (d / "outside-agents.conf").write_bytes(b"# head\r\n\r\nagy  \r\n# claude  not logged in\r\ncodex-kiro\r\n")
    assert oa.read_conf() == ["agy", "codex-kiro"]


def test_read_conf_unknown_name_fails(stubenv):
    _, home = stubenv
    d = home / ".agent-skills-setup"
    d.mkdir()
    (d / "outside-agents.conf").write_text("gpt-cli\n")
    with pytest.raises(oa.ConfError, match="unknown outside agent 'gpt-cli'"):
        oa.read_conf()


def test_read_conf_missing_fails(stubenv):
    with pytest.raises(oa.ConfError, match="outside-agent.sh init"):
        oa.read_conf()


def test_write_conf_lists_failed_as_comments(stubenv):
    oa.write_conf(["agy"], [("claude", "not logged in")], "2026-10-05")
    text = oa.conf_path().read_text()
    assert "\nagy\n" in "\n" + text
    assert "# claude    not logged in (2026-10-05)" in text
    assert oa.read_conf() == ["agy"]


@pytest.mark.parametrize("content", [None, "", "{not json", "[]"])
def test_load_state_bad_or_missing_is_empty(stubenv, content):
    if content is not None:
        oa.state_path().parent.mkdir(parents=True)
        oa.state_path().write_text(content)
    assert oa.load_state() == {"groups": {}, "auth": {}}


def test_record_rate_limit_keyed_by_group(stubenv):
    st = oa.load_state()
    oa.record(st, "codex-kiro", "rate_limit", NOW + timedelta(days=1))
    oa.save_state(st)
    assert "kiro" in oa.load_state()["groups"]


def test_record_auth_keyed_by_name(stubenv):
    st = oa.load_state()
    oa.record(st, "claude", "auth", NOW + oa.AUTH_DEMOTE)
    assert "claude" in st["auth"]
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q`
Expected: FAIL, `AttributeError: ... 'read_conf'`

- [ ] **Step 3: Implement** (add `import json` at the top)

```python
class ConfError(Exception):
    pass


CONF_HEADER = (
    "# outside-agent candidates for this machine, tried top to bottom.\n"
    "# Generated by `outside-agent.sh init`; edit freely, install/update never rewrites it.\n"
    "# Known: " + " ".join(DEFAULT_ORDER) + "\n"
)


def runtime_dir() -> Path:
    override = os.environ.get("OUTSIDE_AGENT_DIR")
    return Path(override) if override else Path(os.path.expanduser("~/.agent-skills-setup"))


def conf_path() -> Path:
    return runtime_dir() / "outside-agents.conf"


def state_path() -> Path:
    return runtime_dir() / "state" / "outside-agents.json"


def read_conf() -> list[str]:
    p = conf_path()
    if not p.exists():
        raise ConfError(f"no {p}; run: outside-agent.sh init")
    names = []
    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line not in KINDS:
            raise ConfError(f"unknown outside agent '{line}' in {p}; known: {' '.join(DEFAULT_ORDER)}")
        names.append(line)
    return names


def write_conf(live: list[str], failed: list[tuple[str, str]], today: str) -> None:
    p = conf_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    body = [CONF_HEADER]
    body += [f"{n}\n" for n in live]
    body += [f"# {n:<9} {why} ({today})\n" for n, why in failed]
    if not live:
        body.append("# no outside agent answered; `outside-agent.sh run` will exit 2\n")
    p.write_text("".join(body))


def load_state() -> dict:
    try:
        d = json.loads(state_path().read_text())
    except (OSError, ValueError):
        d = None
    if not isinstance(d, dict):
        d = {}
    d.setdefault("groups", {})
    d.setdefault("auth", {})
    return d


def save_state(d: dict) -> None:
    p = state_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, indent=2))
    os.replace(tmp, p)


def record(state: dict, name: str, cls: str, until: datetime) -> None:
    if cls == "rate_limit":
        state["groups"][KINDS[name].group] = {"until": until.isoformat(), "by": name}
    elif cls == "auth":
        state["auth"][name] = {"until": until.isoformat()}
```

- [ ] **Step 4: Run to verify pass**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q` → all pass.

- [ ] **Step 5: Type-check and commit**

```bash
.venv/bin/mypy .
git add scripts/outside_agent.py tests/test_outside_agent.py
git commit -m "feat(outside-agent): add per-machine conf and failure state"
```

---

### Task 4: CLI — run, init, status, reset, and the shell wrapper

**Files:**
- Modify: `scripts/outside_agent.py`
- Create: `scripts/outside-agent.sh`
- Modify: `tests/test_outside_agent.py`

**Interfaces:**
- Consumes: everything from Tasks 1–3.
- Produces: `main(argv: list[str]) -> int`; CLI exactly as the spec's Interface section. `init` probe prompt: `Reply with exactly: OK`, 60s, in parallel (`ThreadPoolExecutor`), a candidate counts as live only when classified `ok`. `init` on an existing conf prints `[outside-agent] detected but not listed: …; listed but not found: …` (or `[outside-agent] conf matches detection`) and returns 0 without writing. `init` always returns 0 (install must not fail); errors are printed as warnings.

- [ ] **Step 1: Write failing CLI tests** (run the real script as a subprocess so exit codes and stderr are tested)

```python
SCRIPT = REPO_ROOT / "scripts" / "outside-agent.sh"


def cli(*args, env=None):
    return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True,
                          env=env or dict(os.environ))


def _conf(home: Path, *names: str) -> None:
    d = home / ".agent-skills-setup"
    d.mkdir(exist_ok=True)
    (d / "outside-agents.conf").write_text("\n".join(names) + "\n")


def test_cli_requires_from(stubenv):
    r = cli("run", "--purpose", "review", "--", "p")
    assert r.returncode == 2 and "--from" in r.stderr


def test_cli_falls_through_auth_to_next(stubenv):
    bin_, home = stubenv
    (home / ".codex").mkdir()
    (home / ".codex" / "auth.json").write_text("{}")
    _stub(bin_, "codex", 'echo "401 Unauthorized" >&2; exit 1')
    _stub(bin_, "agy", "echo REVIEWED")
    _conf(home, "codex", "agy")
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--", "p")
    assert r.returncode == 0 and r.stdout.strip() == "REVIEWED"
    assert "used=agy" in r.stderr and "codex(auth)" in r.stderr
    assert "codex" in oa.load_state()["auth"]


def test_cli_rate_limit_skips_next_call(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", 'echo "usage limit reached" >&2; exit 1')
    _conf(home, "agy")
    assert cli("run", "--purpose", "delegate", "--from", "claude", "--", "p").returncode == 2
    _stub(bin_, "agy", "touch " + str(home / "called") + "; echo OK")
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--", "p")
    assert r.returncode == 2 and not (home / "called").exists()
    assert "earliest reset" in r.stderr


def test_cli_unknown_error_stops(stubenv):
    bin_, home = stubenv
    (home / ".codex").mkdir()
    (home / ".codex" / "auth.json").write_text("{}")
    _stub(bin_, "codex", 'echo "HTTP 429 Too Many Requests" >&2; exit 1')
    _stub(bin_, "agy", "touch " + str(home / "called") + "; echo OK")
    _conf(home, "codex", "agy")
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--", "p")
    assert r.returncode == 2 and "429" in r.stderr and not (home / "called").exists()


def test_cli_review_same_family_only_exits_3(stubenv, monkeypatch):
    bin_, home = stubenv
    monkeypatch.setenv("OUTSIDE_AGENT_SKIP_KEYCHAIN", "1")
    _stub(bin_, "claude", "echo LOOKS-FINE")
    _stub(bin_, "agy", 'echo "Not logged in"')
    _conf(home, "agy", "claude")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 3 and r.stdout.strip() == "LOOKS-FINE"
    assert "not independent" in r.stderr


def test_cli_bad_conf_exits_2(stubenv):
    _, home = stubenv
    _conf(home, "nope")
    assert cli("run", "--purpose", "delegate", "--from", "claude", "--", "p").returncode == 2


def test_init_generates_when_missing(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    r = cli("init")
    assert r.returncode == 0
    text = oa.conf_path().read_text()
    assert oa.read_conf() == ["agy"]
    assert "# claude-kiro" in text and "# codex" in text


def test_init_keeps_existing_and_prints_diff(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "codex")
    before = oa.conf_path().read_text()
    r = cli("init")
    assert r.returncode == 0 and oa.conf_path().read_text() == before
    assert "detected but not listed: agy" in r.stdout
    assert "listed but not found: codex" in r.stdout


def test_init_force_rewrites(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "codex")
    cli("init", "--force")
    assert oa.read_conf() == ["agy"]


def test_status_and_reset(stubenv):
    _, home = stubenv
    _conf(home, "agy")
    st = oa.load_state()
    oa.record(st, "codex-kiro", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    assert "kiro: rate_limit until 2099-01-01 00:00" in cli("status").stdout
    cli("reset", "kiro")
    assert oa.load_state()["groups"] == {}
```

`OUTSIDE_AGENT_SKIP_KEYCHAIN=1` is a test seam that makes the `claude` pre-check skip the `security` lookup; add it to `precheck` (`if name == "claude" and not env.get("OUTSIDE_AGENT_SKIP_KEYCHAIN") and shutil.which("security", ...)`).

- [ ] **Step 2: Run to verify failure**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q`
Expected: CLI tests FAIL (`No such file or directory: scripts/outside-agent.sh`).

- [ ] **Step 3: Implement the wrapper**

`scripts/outside-agent.sh`:
```bash
#!/usr/bin/env bash
# Runtime copy lives in ~/.agent-skills-setup next to outside_agent.py (install_runtime_dir).
exec python3 "$(cd "$(dirname "$0")" && pwd)/outside_agent.py" "$@"
```
`chmod +x scripts/outside-agent.sh`

- [ ] **Step 4: Implement `main`** (append; add `import argparse, sys`, `from concurrent.futures import ThreadPoolExecutor`, and `NoReturn` to the `typing` import)

```python
def _now() -> datetime:
    return datetime.now().astimezone()


def _say(msg: str) -> None:
    print(f"[outside-agent] {msg}", file=sys.stderr)


def cmd_run(a: argparse.Namespace) -> int:
    try:
        conf = read_conf()
    except ConfError as e:
        _say(str(e))
        return 2
    state = load_state()
    now = _now()
    order, skipped = order_candidates(conf, state, now, a.purpose, a.from_)
    notes = [f"{n}({why})" for n, why in skipped]
    if not order:
        resets = [v["until"] for v in state["groups"].values() if _active(v, now)]
        _say(f"no candidate available; skipped={','.join(notes)}; earliest reset {min(resets) if resets else 'n/a'}")
        return 2
    env = dict(os.environ)
    limited: set[str] = set()
    for name in order:
        if KINDS[name].group in limited:
            notes.append(f"{name}(rate_limit, shared quota)")
            continue
        why = precheck(name, env)
        if why:
            notes.append(f"{name}(precheck: {why})")
            continue
        cls, out = run_one(name, a.prompt, a.purpose, a.allow_edits, a.timeout, a.cwd)
        if cls == "ok":
            print(out)
            same = KINDS[name].family == a.from_
            _say(f"used={name} skipped={','.join(notes) or '-'}")
            if a.purpose == "review" and same:
                _say(f"{name} is the caller's own model family: review is not independent")
                return 3
            return 0
        if cls == "rate_limit":
            record(state, name, cls, rate_limit_reset(KINDS[name].group, now, out))
        elif cls == "auth":
            record(state, name, cls, now + AUTH_DEMOTE)
        save_state(state)
        notes.append(f"{name}({cls})")
        if cls == "error":
            _say(f"{name} failed with an unclassified error, stopping:\n{out}")
            return 2
        if cls == "rate_limit":
            limited.add(KINDS[name].group)
    resets = [v["until"] for v in state["groups"].values() if _active(v, now)]
    tail = f"; earliest reset {min(resets)}" if resets else ""
    _say(f"no candidate succeeded; tried={','.join(notes)}{tail}")
    return 2


def _probe(name: str) -> tuple[str, str]:
    why = precheck(name, dict(os.environ))
    if why:
        return name, why
    cls, out = run_one(name, "Reply with exactly: OK", "review", False, 60, None)
    return name, ("ok" if cls == "ok" else (out.splitlines() or [cls])[-1][:60])


def cmd_init(a: argparse.Namespace) -> int:
    try:
        with ThreadPoolExecutor(max_workers=len(DEFAULT_ORDER)) as ex:
            results = dict(ex.map(_probe, DEFAULT_ORDER))
    except Exception as e:  # install must not fail on detection
        print(f"[outside-agent] WARNING: detection failed: {e}")
        results = {}
    live = [n for n in DEFAULT_ORDER if results.get(n) == "ok"]
    failed = [(n, results.get(n, "not probed")) for n in DEFAULT_ORDER if n not in live]
    if conf_path().exists() and not a.force:
        try:
            listed = read_conf()
        except ConfError as e:
            print(f"[outside-agent] WARNING: {e}")
            return 0
        add = [n for n in live if n not in listed]
        gone = [n for n in listed if n not in live]
        if add or gone:
            print(f"[outside-agent] detected but not listed: {' '.join(add) or '-'}; "
                  f"listed but not found: {' '.join(gone) or '-'}")
        else:
            print("[outside-agent] conf matches detection")
        return 0
    write_conf(live, failed, _now().strftime("%Y-%m-%d"))
    print(f"[outside-agent] wrote {conf_path()}: {' '.join(live) or '(none)'}")
    return 0


def cmd_status(a: argparse.Namespace) -> int:
    now = _now()
    try:
        print("conf: " + " ".join(read_conf()))
    except ConfError as e:
        print(f"conf: {e}")
    st = load_state()
    for g, v in st["groups"].items():
        u = _active(v, now)
        if u:
            print(f"{g}: rate_limit until {u:%Y-%m-%d %H:%M}")
    for n, v in st["auth"].items():
        u = _active(v, now)
        if u:
            print(f"{n}: auth failure, demoted until {u:%Y-%m-%d %H:%M}")
    return 0


def cmd_reset(a: argparse.Namespace) -> int:
    st = load_state()
    if a.target:
        st["groups"].pop(a.target, None)
        st["auth"].pop(a.target, None)
        if a.target in KINDS:
            st["groups"].pop(KINDS[a.target].group, None)
    else:
        st = {"groups": {}, "auth": {}}
    save_state(st)
    return 0


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        self.print_usage(sys.stderr)
        _say(message)
        sys.exit(2)


def main(argv: list[str]) -> int:
    p = _Parser(prog="outside-agent.sh")
    sub = p.add_subparsers(dest="cmd", required=True, parser_class=_Parser)
    r = sub.add_parser("run")
    r.add_argument("--purpose", choices=("delegate", "review"), required=True)
    r.add_argument("--from", dest="from_", choices=FAMILIES, required=True)
    r.add_argument("--timeout", type=int, default=300)
    r.add_argument("--cwd")
    r.add_argument("--allow-edits", action="store_true")
    r.add_argument("prompt")
    i = sub.add_parser("init")
    i.add_argument("--force", action="store_true")
    sub.add_parser("status")
    s = sub.add_parser("reset")
    s.add_argument("target", nargs="?")
    a = p.parse_args(argv)
    return {"run": cmd_run, "init": cmd_init, "status": cmd_status, "reset": cmd_reset}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

`argparse` treats `--` correctly: `run ... -- "prompt"` makes the prompt positional even if it starts with `-`.

- [ ] **Step 5: Run to verify pass**

Run: `.venv/bin/python3 -m pytest tests/test_outside_agent.py -q` → all pass.
Run: `/bin/bash scripts/outside-agent.sh status` (with `HOME=$(mktemp -d)`) → prints `conf: no …; run: outside-agent.sh init`, exit 0.

- [ ] **Step 6: Type-check, ruff format, commit**

```bash
.venv/bin/mypy . && .venv/bin/ruff format scripts/outside_agent.py tests/test_outside_agent.py
git add scripts/outside_agent.py scripts/outside-agent.sh tests/test_outside_agent.py
git commit -m "feat(outside-agent): add run, init, status and reset commands"
```

---

### Task 5: Install wiring and runtime drift guard

**Files:**
- Modify: `scripts/_lib.sh:530-536` (`install_runtime_dir`)
- Modify: `scripts/install.sh` (after the `update-agents.sh` block, before the OpenSpec hint)
- Create: `.claude/hooks/runtime-drift-guard.sh`
- Create: `.claude/hooks/tests/test_runtime_drift_guard.sh`
- Modify: `scripts/harness-verify.sh` (add `run_gate` line), `.claude/settings.json` (Stop + SubagentStop), `scripts/tests/test_harness_verify.sh:28` (stub list)
- Modify: `scripts/tests/test_lib_setup_repo_dir.sh` (`full_src`/`fake_src` create the two new files)
- Modify: `scripts/tests/test_install_source_guard.sh` (`OUTSIDE_AGENT_INIT=0` seam)

**Interfaces:**
- Consumes: `scripts/outside-agent.sh init`.
- Produces: runtime files `~/.agent-skills-setup/outside-agent.sh` and `outside_agent.py`; guard `runtime-drift-guard.sh` honoring `RUNTIME_DRIFT_GUARD_RUNTIME_DIR` (test seam), exit 2 on drift, prints `SKIP  runtime not installed` and exits 0 when the runtime dir does not exist (CI before install, fresh clone).

- [ ] **Step 1: Write the failing guard test**

`.claude/hooks/tests/test_runtime_drift_guard.sh`:
```bash
#!/usr/bin/env bash
# Installed runtime files are copies, not symlinks; lib.sh and _store.sh drifted
# from the repo once without anything noticing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
GUARD="$REPO_DIR/.claude/hooks/runtime-drift-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
check() {
  if [[ "$2" == "$3" ]]; then echo "OK: $1"; else echo "FAIL: $1 (expected $2, got $3)"; fails=$((fails + 1)); fi
}
rc() { set +e; RUNTIME_DRIFT_GUARD_RUNTIME_DIR="$1" bash "$GUARD" >"$TMP/out" 2>&1; echo $?; set -e; }

check "absent runtime is a skip" 0 "$(rc "$TMP/none")"
check "skip says SKIP" yes "$(grep -q 'SKIP' "$TMP/out" && echo yes || echo no)"

RT="$TMP/rt"; mkdir -p "$RT"
cp "$REPO_DIR/lib/lib.sh" "$RT/lib.sh"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$RT/_store.sh"
cp "$REPO_DIR/scripts/outside-agent.sh" "$RT/outside-agent.sh"
cp "$REPO_DIR/scripts/outside_agent.py" "$RT/outside_agent.py"
check "identical copies pass" 0 "$(rc "$RT")"

echo "# drift" >> "$RT/_store.sh"
check "drifted _store.sh blocks" 2 "$(rc "$RT")"
check "names the drifted file" yes "$(grep -q '_store.sh' "$TMP/out" && echo yes || echo no)"
cp "$REPO_DIR/scripts/credentials/_store.sh" "$RT/_store.sh"

rm "$RT/outside_agent.py"
check "missing copy blocks" 2 "$(rc "$RT")"

[[ $fails -eq 0 ]]
```

- [ ] **Step 2: Run to verify failure**

Run: `bash .claude/hooks/tests/test_runtime_drift_guard.sh` → FAIL (guard missing).

- [ ] **Step 3: Write the guard**

`.claude/hooks/runtime-drift-guard.sh`:
```bash
#!/usr/bin/env bash
# runtime-drift-guard.sh — Stop/SubagentStop hook: block when the flat runtime
# copies install_runtime_dir makes under ~/.agent-skills-setup differ from the
# repo. They are copies, not symlinks, so a repo edit never reaches them until
# install_runtime_dir runs again; lib.sh and _store.sh drifted that way once.
# Exit 2 blocks; exit 0 allows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RT="${RUNTIME_DRIFT_GUARD_RUNTIME_DIR:-$HOME/.agent-skills-setup}"

if [[ ! -d "$RT" ]]; then
  echo "  SKIP  runtime not installed at $RT"
  exit 0
fi

drift=""
while read -r src dst; do
  if ! cmp -s "$REPO_DIR/$src" "$RT/$dst"; then
    drift="$drift $dst"
  fi
done <<'EOF'
lib/lib.sh lib.sh
scripts/credentials/_store.sh _store.sh
scripts/outside-agent.sh outside-agent.sh
scripts/outside_agent.py outside_agent.py
EOF

if [[ -n "$drift" ]]; then
  echo "Blocked: installed runtime copies differ from the repo:$drift" >&2
  echo "Sync: source scripts/_lib.sh && install_runtime_dir \"\$PWD\"" >&2
  exit 2
fi
```

- [ ] **Step 4: Copy the new files in `install_runtime_dir`** — after line 536 (`cp -f "$repo_dir/scripts/credentials/_store.sh" ...`) add:

```bash
  cp -f "$repo_dir/scripts/outside-agent.sh" "$rtdir/outside-agent.sh"
  cp -f "$repo_dir/scripts/outside_agent.py" "$rtdir/outside_agent.py"
```

In `scripts/tests/test_lib_setup_repo_dir.sh`, `fake_src` and `full_src` must create both files, or `install_runtime_dir` under `set -e` fails there. Add to each, after the `_store.sh` line:

```bash
  : > "$d/scripts/outside-agent.sh"
  : > "$d/scripts/outside_agent.py"
```

- [ ] **Step 5: Run `init` from `install.sh`** — insert before `# Print post-install hints when openspec is registered.`:

```bash
echo ""
echo "==> Detecting outside agents..."
# Failure-tolerant: a missing outside agent must never block installing skills.
# OUTSIDE_AGENT_INIT=0 lets tests run install.sh without live agent probes.
if [[ "${OUTSIDE_AGENT_INIT:-1}" == "0" ]]; then
  echo "  skipped (OUTSIDE_AGENT_INIT=0)"
else
  bash "$(skills_runtime_dir "$REPO_DIR")/outside-agent.sh" init || echo "  WARNING: outside-agent init failed"
fi
```

`update.sh` runs `install.sh`, so it needs no change.

`scripts/tests/test_install_source_guard.sh` runs the real `install.sh` with the real `PATH` behind its stubs. Without the seam, `init` would make a live `agy` call (agy logs in from the macOS keyring, not `HOME`). In that file's `run_install`, change `HOME="$home" PATH=...` to `HOME="$home" OUTSIDE_AGENT_INIT=0 PATH=...`, and add:

```bash
check "install skips outside-agent init when asked" yes \
  "$(grep -q 'skipped (OUTSIDE_AGENT_INIT=0)' "$TMP/h1.out" && echo yes || echo no)"
```

- [ ] **Step 6: Wire the guard**

- `scripts/harness-verify.sh`, after the `state layer` line: `run_gate "runtime drift" "$HOOKS/runtime-drift-guard.sh"`
- `.claude/settings.json`: add `{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/runtime-drift-guard.sh\""}` to both the `Stop` and `SubagentStop` hook arrays, next to `state-layer-guard.sh`.
- `scripts/tests/test_harness_verify.sh:28`: append `runtime-drift-guard` to the `for g in ...` stub list.

- [ ] **Step 7: Verify**

```bash
bash .claude/hooks/tests/test_runtime_drift_guard.sh      # all OK
/bin/bash .claude/hooks/tests/test_runtime_drift_guard.sh # bash 3.2
bash scripts/tests/test_lib_setup_repo_dir.sh
bash scripts/tests/test_harness_verify.sh
bash scripts/tests/test_install_source_guard.sh          # install.sh still exits 0 in a temp HOME
source scripts/_lib.sh && install_runtime_dir "$PWD"      # sync this machine
bash .claude/hooks/runtime-drift-guard.sh; echo "rc=$?"   # rc=0
```

Expected: every test passes, and the guard returns rc=0 after the sync. `test_install_source_guard.sh` runs the real `install.sh` with a temp `HOME` and stubbed agents on `PATH`. `init` then finds no working agents, writes an empty conf, and must not change install's exit code.

- [ ] **Step 8: Commit**

```bash
git add scripts/_lib.sh scripts/install.sh scripts/harness-verify.sh .claude/settings.json \
  .claude/hooks/runtime-drift-guard.sh .claude/hooks/tests/test_runtime_drift_guard.sh \
  scripts/tests/test_harness_verify.sh scripts/tests/test_lib_setup_repo_dir.sh \
  scripts/tests/test_install_source_guard.sh
git commit -m "feat(outside-agent): install runtime copy, run init, and guard copy drift"
```

---

### Task 6: Rule, live check, state files

**Files:**
- Modify: `agents/engineering-rules.md` (Part III, after `### Subagent verification`)
- Modify: `scripts/tests/test_engineering_rules_scope.sh`
- Modify: `tests/test_outside_agent.py` (integration case)
- Modify: `feature_list.json`, `PROGRESS.md`

- [ ] **Step 1: Write the failing rule test** — append to `scripts/tests/test_engineering_rules_scope.sh` before its final result line, using that file's existing `ok`/`bad` helpers:

```bash
grep -q 'outside-agent.sh run --purpose review' "$RULES" \
  && ok "outside-agent rule present" || bad "outside-agent rule present" "missing"
grep -q 'not independent' "$RULES" \
  && ok "outside-agent rule names exit 3" || bad "outside-agent rule names exit 3" "missing"
```

Run: `bash scripts/tests/test_engineering_rules_scope.sh` → 2 new FAILs.

- [ ] **Step 2: Add the rule** — insert after the two `### Subagent verification` bullets:

```markdown

### Outside agents
- Delegating: use your own subagent first. For an outside agent, run `~/.agent-skills-setup/outside-agent.sh run --purpose delegate --from <your family> -- "<prompt>"`.
- Reviewing: get at least one answer from a different model family with `outside-agent.sh run --purpose review`. Report exit 3 as "not independent", never as a pass.
- Exit 2 means no outside agent worked: report its stderr line and do not work around it.
```

Run the scope test again → all pass (the text names no `.claude/` path and no slash command).

- [ ] **Step 3: Add the live check** — append to `tests/test_outside_agent.py`:

```python
@pytest.mark.skipif(os.environ.get("RUN_INTEGRATION") != "1", reason="live agents; RUN_INTEGRATION=1")
def test_outside_agent_live_review():
    r = subprocess.run(["bash", str(SCRIPT), "run", "--purpose", "review", "--from", "claude",
                        "--timeout", "120", "--", "Reply with exactly: OK"],
                       capture_output=True, text=True)
    assert r.returncode in (0, 3), r.stderr
    assert "used=" in r.stderr
```

pytest's `skipif` already keeps this out of `--fast`, so `run-tests.sh` needs no change.

- [ ] **Step 4: Run the live check on this machine**

```bash
RUN_INTEGRATION=1 .venv/bin/python3 -m pytest tests/test_outside_agent.py -q -k live
~/.agent-skills-setup/outside-agent.sh init --force
~/.agent-skills-setup/outside-agent.sh status
```

Expected: the live test passes with `used=codex-kiro` (the first non-Claude candidate). `init --force` writes `claude-kiro codex-kiro agy`, with `claude` and `codex` commented out. Paste the actual output into the feat-035 evidence. If it doesn't match, record what happened instead.

- [ ] **Step 5: Record state** — add `feat-035` to `feature_list.json`, with `dependencies: []`, `status: done`, and evidence listing the test counts, the live result, and `harness-verify` gates. Add a `PROGRESS.md` entry. Also list these open items:
  - `install-agents-md.sh` has not been run, so host rule files don't have the rule yet. This needs owner approval.
  - Real usage-limit messages have not been observed yet.
  - There is no cheap login signal for `agy`.

- [ ] **Step 6: Full verification and commit**

```bash
bash scripts/harness-verify.sh   # all gates, including "runtime drift"
git add agents/engineering-rules.md scripts/tests/test_engineering_rules_scope.sh \
  tests/test_outside_agent.py feature_list.json PROGRESS.md
git commit -m "feat(outside-agent): add the outside-agent rule and record feat-035"
```
