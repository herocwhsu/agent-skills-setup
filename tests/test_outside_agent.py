"""Tests for scripts/outside_agent.py."""

import argparse
import json
import os
import re
import signal
import stat
import subprocess
import sys
import time
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
        (0, "LGTM. The quota check in billing.py looks right.", "ok"),
        (0, "No issues. /login redirect is correct.", "ok"),
        (0, "Fine; returns 401 when token missing.", "ok"),
        (1, "401 Unauthorized: usage limit hit", "rate_limit"),
        (0, "usage limit reached", "rate_limit"),
        (0, "Error path checks quota correctly.", "ok"),
        (0, "Usage limit check is fine.", "ok"),
        (0, "Quota exceeded path is handled.", "ok"),
        (0, "Error handling covers the /login redirect.", "ok"),
        (0, "401 is returned correctly.", "ok"),
        (0, "Unauthorized requests get 401.", "ok"),
        (0, "Error handling looks fine.", "ok"),
        (0, "You've hit your usage limit · resets 3pm", "rate_limit"),
        (0, "Monthly quota exceeded.", "rate_limit"),
        (0, "Please run /login", "auth"),
        (0, "Not logged in", "auth"),
        (0, "Not logged in is the status returned by that API.", "ok"),
        (0, "Usage limit reached is logged before the retry.", "ok"),
        (0, "Quota exceeded errors are mapped to 429.", "ok"),
    ],
)
def test_classify(rc, out, expected):
    assert oa.classify(rc, out) == expected


def test_long_successful_answer_quoting_401_is_ok():
    answer = "Review: the handler returns 401 Unauthorized when the token is absent. " * 5
    assert oa.classify(0, answer) == "ok"


def test_empty_success_is_error():
    assert oa.classify(0, "   ") == "error"


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


def test_active_naive_timestamp_does_not_raise():
    naive = (NOW + timedelta(hours=1)).replace(tzinfo=None).isoformat()
    assert oa._active({"until": naive}, NOW) == NOW + timedelta(hours=1)
    past = (NOW - timedelta(hours=1)).replace(tzinfo=None).isoformat()
    assert oa._active({"until": past}, NOW) is None


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
    monkeypatch.chdir(home)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("PATH", f"{bin_}:/usr/bin:/bin")
    monkeypatch.setenv("OUTSIDE_AGENT_GATEWAY", "http://127.0.0.1:9")
    monkeypatch.delenv("ZDOTDIR", raising=False)
    return bin_, home


def test_build_argv_review_is_read_only():
    argv = oa.build_argv("claude", "p", "review", True)
    assert argv[argv.index("--permission-mode") + 1] == "plan"
    assert argv[-1] == "p"
    codex = oa.build_argv("codex", "p", "review", True)
    assert "read-only" in codex and codex[-1] == "p"


def test_build_argv_agy_reviews_at_high_effort():
    review = oa.build_argv("agy", "p", "review", False)
    assert review[review.index("--effort") + 1] == "high"
    assert review.index("--effort") < review.index("-p")
    assert "--effort" not in oa.build_argv("agy", "p", "delegate", False)


def test_build_argv_agy_review_is_held_by_its_allowlist_not_skipped():
    # --mode plan only asks agy to plan and --dangerously-skip-permissions approved every
    # tool, so a "read-only" review ran install.sh; headless agy denies what is not allowed.
    review = oa.build_argv("agy", "p", "review", False)
    assert "--dangerously-skip-permissions" not in review
    assert "--mode" not in review
    assert review[review.index("--model") + 1] == "gemini-3.8-flash-high"
    assert review[-2] == "-p" and review[-1].endswith("\n\np")
    assert "do not run tests" in review[-1]
    assert "inside this repository" in review[-1]
    assert "file viewing and search tools" in review[-1]
    delegate = oa.build_argv("agy", "p", "delegate", True)
    assert "--dangerously-skip-permissions" in delegate and delegate[-1] == "p"


def test_run_one_agy_denial_reports_its_stderr(stubenv):
    bin_, _ = stubenv
    _stub(
        bin_,
        "agy",
        "echo 'jetski: no output produced, a tool required the \"command\" permission' >&2",
    )
    cls, out = oa.run_one("agy", "p", "review", False, 10, None)
    assert cls == "error" and '"command" permission' in out


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
    assert oa.precheck("claude-kiro", dict(os.environ)) == "kiro-gateway not answering"


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
    _stub(
        bin_,
        "claude",
        'if [ -n "$ANTHROPIC_API_KEY" ]; then echo LEAKED; else echo "Not logged in"; fi',
    )
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-inherited")
    assert oa.run_one("claude", "p", "review", False, 10, None) == ("auth", "Not logged in")


def test_run_one_strips_escape_sequences(stubenv):
    bin_, _ = stubenv
    _stub(bin_, "agy", r"printf '\033]1337;CurrentDir=/tmp\007OK\n'")
    assert oa.run_one("agy", "p", "review", False, 10, None) == ("ok", "OK")


def test_precheck_kiro_missing_shell_returns_reason(stubenv, monkeypatch):
    monkeypatch.setattr(oa, "_gateway_up", lambda: True)
    monkeypatch.setenv("OUTSIDE_AGENT_SHELL", "/nonexistent/zsh")
    assert oa.precheck("claude-kiro", dict(os.environ)) == "/nonexistent/zsh not available"


def test_precheck_kiro_alias_missing(stubenv, monkeypatch):
    monkeypatch.setattr(oa, "_gateway_up", lambda: True)
    assert oa.precheck("claude-kiro", dict(os.environ)) == "alias claude-kiro not defined"


def test_run_one_timeout_kills_grandchildren(stubenv, tmp_path):
    bin_, _ = stubenv
    pidfile = tmp_path / "grandchild.pid"
    _stub(bin_, "agy", f"sleep 30 &\necho $! > {pidfile}\nwait")
    start = time.monotonic()
    assert oa.run_one("agy", "p", "review", False, 1, None) == ("transient", "timed out after 1s")
    assert time.monotonic() - start < 5
    pid = int(pidfile.read_text())
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.01)
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


def test_read_conf_tolerates_comments_blank_crlf(stubenv):
    _, home = stubenv
    d = home / ".agent-skills-setup"
    d.mkdir()
    (d / "outside-agents.conf").write_bytes(
        b"# head\r\n\r\nagy  \r\n# claude  not logged in\r\ncodex-kiro\r\n"
    )
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


def test_write_conf_no_live_agents(stubenv):
    oa.write_conf([], [("agy", "401")], "2026-10-05")
    assert oa.read_conf() == []
    assert "`outside-agent.sh run` will exit 2" in oa.conf_path().read_text()


@pytest.mark.parametrize(
    "content", [None, "", "{not json", "[]", '{"groups": null}', '{"groups": [], "auth": "x"}']
)
def test_load_state_bad_or_missing_is_empty(stubenv, content):
    if content is not None:
        oa.state_path().parent.mkdir(parents=True)
        oa.state_path().write_text(content)
    assert oa.load_state() == {"groups": {}, "auth": {}}


def test_record_rate_limit_group_shared_later_name_wins(stubenv):
    st = oa.load_state()
    oa.record(st, "claude-kiro", "rate_limit", NOW + timedelta(days=1))
    oa.record(st, "codex-kiro", "rate_limit", NOW + timedelta(days=2))
    oa.save_state(st)
    groups = oa.load_state()["groups"]
    assert list(groups) == ["kiro"]
    assert groups["kiro"]["by"] == "codex-kiro"


def test_record_auth_keyed_by_name(stubenv):
    st = oa.load_state()
    oa.record(st, "claude", "auth", NOW + oa.AUTH_DEMOTE)
    assert "claude" in st["auth"]


SCRIPT = REPO_ROOT / "scripts" / "outside-agent.sh"


def cli(*args, env=None):
    # sys.executable, not the wrapper: /usr/bin/python3 on stubenv's PATH is a slow xcrun shim.
    return subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "outside_agent.py"), *args],
        capture_output=True,
        text=True,
        env=env or dict(os.environ),
    )


def test_wrapper_execs_the_python_cli(stubenv):
    r = subprocess.run(["bash", str(SCRIPT), "status"], capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.startswith("conf: ")


def _conf(home: Path, *names: str) -> None:
    oa.runtime_dir().mkdir(exist_ok=True)
    oa.conf_path().write_text("\n".join(names) + "\n")


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


def test_cli_review_by_the_callers_own_family_counts_as_independent(stubenv, monkeypatch):
    # Owner decision 2026-10-20: a fresh context makes a reviewer independent, whatever its model.
    bin_, home = stubenv
    monkeypatch.setenv("OUTSIDE_AGENT_SKIP_KEYCHAIN", "1")
    _stub(bin_, "claude", "echo LOOKS-FINE")
    _stub(bin_, "agy", 'echo "Not logged in"')
    _conf(home, "agy", "claude")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 0 and r.stdout.strip() == "LOOKS-FINE"
    lines = r.stderr.strip().splitlines()
    assert len(lines) == 1 and "used=claude" in lines[0] and "not independent" not in lines[0]
    rows = [
        json.loads(x)
        for x in (home / ".agent-skills-setup/state/outside-agent-runs.jsonl")
        .read_text()
        .splitlines()
    ]
    run = [x for x in rows if not x.get("attempt")][-1]
    assert run["independent"] is True and run["exit_code"] == 0


def test_cli_ok_clears_auth_demotion(stubenv):
    bin_, home = stubenv
    st = oa.load_state()
    oa.record(st, "agy", "auth", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    _stub(bin_, "agy", "echo ANSWER")
    _conf(home, "agy")
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--", "p")
    assert r.returncode == 0 and r.stdout.strip() == "ANSWER"
    assert "agy" not in oa.load_state()["auth"]


def test_cli_sigterm_kills_agent_process_group(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", 'sleep 30 & echo $! > "$HOME/agent.pid"; wait')
    _conf(home, "agy")
    proc = subprocess.Popen(
        ["bash", str(SCRIPT), "run", "--purpose", "delegate", "--from", "claude", "--", "p"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=dict(os.environ),
    )
    pidfile = home / "agent.pid"
    deadline = time.monotonic() + 10
    while not (pidfile.exists() and pidfile.read_text().strip()):
        assert time.monotonic() < deadline, "agent never started"
        time.sleep(0.05)
    pid = int(pidfile.read_text())
    try:
        proc.send_signal(signal.SIGTERM)
        deadline = time.monotonic() + 5
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            assert time.monotonic() < deadline, f"agent grandchild {pid} still alive"
            time.sleep(0.05)
        assert proc.wait(timeout=5) == 128 + signal.SIGTERM
    finally:
        proc.kill()
        proc.communicate()
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


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


def test_status_and_reset(stubenv):
    _, home = stubenv
    _conf(home, "agy")
    st = oa.load_state()
    oa.record(st, "codex-kiro", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    assert "kiro: rate_limit until 2099-01-01 00:00" in cli("status").stdout
    cli("reset", "kiro")
    assert oa.load_state()["groups"] == {}


def test_cli_missing_cwd_exits_2_without_traceback(stubenv, tmp_path):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "agy")
    r = cli(
        "run",
        "--purpose",
        "delegate",
        "--from",
        "claude",
        "--cwd",
        str(tmp_path / "nope"),
        "--",
        "p",
    )
    assert r.returncode == 2 and "Traceback" not in r.stderr
    assert "is not a directory" in r.stderr


def test_run_one_start_failure_is_error(stubenv):
    cls, out = oa.run_one("agy", "p", "review", False, 5, None)
    assert cls == "error" and "failed to start agy" in out


def test_cli_timeout_zero_exits_2(stubenv):
    _, home = stubenv
    _conf(home, "agy")
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--timeout", "0", "--", "p")
    assert r.returncode == 2 and "Traceback" not in r.stderr and "--timeout" in r.stderr


def test_reset_unknown_target_exits_2_and_keeps_state(stubenv):
    st = oa.load_state()
    oa.record(st, "codex-kiro", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    r = cli("reset", "kirro")
    assert r.returncode == 2 and "unknown target" in r.stderr
    assert "kiro" in oa.load_state()["groups"]


def test_reset_kind_clears_its_group(stubenv):
    st = oa.load_state()
    oa.record(st, "codex-kiro", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.record(st, "agy", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    assert cli("reset", "codex-kiro").returncode == 0
    assert list(oa.load_state()["groups"]) == ["agy"]


def test_reset_all_clears_everything(stubenv):
    st = oa.load_state()
    oa.record(st, "agy", "rate_limit", datetime(2099, 1, 1, tzinfo=TZ))
    oa.record(st, "codex", "auth", datetime(2099, 1, 1, tzinfo=TZ))
    oa.save_state(st)
    assert cli("reset").returncode == 0
    assert oa.load_state() == {"groups": {}, "auth": {}}


def test_init_force_writes_failed_as_comments(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "codex")
    r = cli("init", "--force")
    assert r.returncode == 0
    text = oa.conf_path().read_text()
    assert oa.read_conf() == ["agy"]
    assert "# codex" in text and "not on PATH" in text and "# claude-kiro" in text


def test_init_probes_from_runtime_dir_not_caller_cwd(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", 'pwd > "$HOME/probe-cwd"; echo OK')
    assert cli("init").returncode == 0
    recorded = Path((home / "probe-cwd").read_text().strip()).resolve()
    assert recorded == oa.runtime_dir().resolve()
    assert recorded != Path.cwd().resolve()


def test_init_unwritable_dir_still_exits_0(stubenv, tmp_path, monkeypatch):
    blocker = tmp_path / "blocker"
    blocker.write_text("")
    monkeypatch.setenv("OUTSIDE_AGENT_DIR", str(blocker))
    r = cli("init")
    assert r.returncode == 0 and "Traceback" not in r.stderr
    assert "WARNING: could not write" in r.stdout


def test_apply_rubric_structure():
    base = "Review this pull request."
    formatted = oa.apply_rubric(base)
    assert formatted.startswith(base)
    assert "## Evaluator Rubric (Score each dimension 1-5):" in formatted
    assert "1. Rule Conformance (1-5)" in formatted
    assert "2. Surgical Precision (1-5)" in formatted
    assert "3. Test Verifiability (1-5)" in formatted
    assert "4. Evidence Grounding (1-5)" in formatted
    assert "Required Evaluation Output:" in formatted
    assert "Concrete Failure Scenarios" in formatted
    assert "Final Verdict: PASS, CONDITIONAL, or REJECT" in formatted


def test_cli_rubric_rejected_for_non_review_purpose(stubenv):
    r = cli("run", "--purpose", "delegate", "--from", "claude", "--rubric", "--", "p")
    assert r.returncode == 2
    assert "--rubric is only supported when --purpose is review" in r.stderr


def test_cli_rubric_augments_prompt_to_agent(stubenv):
    bin_, home = stubenv
    argsfile = home / "args.txt"
    _stub(bin_, "agy", f'printf "%s\\n" "$@" > "{argsfile}"\necho OK')
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--rubric", "--", "Review feature X")
    assert r.returncode == 0
    passed_args = argsfile.read_text()
    assert "Review feature X" in passed_args
    assert "## Evaluator Rubric (Score each dimension 1-5):" in passed_args
    assert "Rule Conformance (1-5)" in passed_args
    assert "Surgical Precision (1-5)" in passed_args
    assert "Test Verifiability (1-5)" in passed_args
    assert "Evidence Grounding (1-5)" in passed_args
    assert "Concrete Failure Scenarios" in passed_args


def test_cli_review_without_rubric_leaves_prompt_unmodified(stubenv):
    bin_, home = stubenv
    argsfile = home / "args.txt"
    _stub(bin_, "agy", f'printf "%s\\n" "$@" > "{argsfile}"\necho OK')
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "Review feature X")
    assert r.returncode == 0
    passed_args = argsfile.read_text()
    assert "Review feature X" in passed_args
    assert "## Evaluator Rubric" not in passed_args


def test_outside_agent_logs_run_to_jsonl(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 0
    rt_log = oa.runtime_dir() / "state" / "outside-agent-runs.jsonl"
    assert rt_log.is_file()
    lines = [json.loads(line) for line in rt_log.read_text().splitlines() if line]
    lines = [r for r in lines if r.get("attempt") is not True]
    assert len(lines) == 1
    rec = lines[0]
    assert rec["agent"] == "agy"
    assert rec["purpose"] == "review"
    assert rec["caller_family"] == "claude"
    assert rec["exit_code"] == 0
    assert rec["independent"] is True
    assert "repo" in rec


def test_timeout_is_named_in_the_final_message(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "sleep 30")
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--timeout", "1", "--", "p")
    assert r.returncode == 2
    assert "agy(timeout after 1s)" in r.stderr


def test_empty_reply_is_named_not_unclassified(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "exit 0")
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 2
    assert "agy returned no output" in r.stderr
    assert "unclassified" not in r.stderr


@pytest.mark.skipif(
    os.environ.get("RUN_INTEGRATION") != "1", reason="live agents; RUN_INTEGRATION=1"
)
def test_outside_agent_live_review():
    r = subprocess.run(
        [
            "bash",
            str(SCRIPT),
            "run",
            "--purpose",
            "review",
            "--from",
            "claude",
            "--timeout",
            "120",
            "--",
            "Reply with exactly: OK",
        ],
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert r.returncode == 0, r.stderr
    assert "used=" in r.stderr


def _attempts(home: Path) -> list[dict]:
    log = oa.runtime_dir() / "state" / "outside-agent-runs.jsonl"
    if not log.is_file():
        return []
    rows = [json.loads(line) for line in log.read_text().splitlines() if line]
    return [r for r in rows if r.get("attempt") is True]


def _run_agy(stubenv, body: str, *extra: str):
    bin_, home = stubenv
    _stub(bin_, "agy", body)
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", *extra, "--", "p")
    return r, _attempts(home)


def test_attempt_logged_for_success_with_duration(stubenv):
    r, att = _run_agy(stubenv, "echo OK")
    assert r.returncode == 0
    assert [(a["agent"], a["result"]) for a in att] == [("agy", "ok")]
    assert isinstance(att[0]["duration_ms"], int) and att[0]["duration_ms"] >= 0


def test_rows_name_the_session_and_attempts_name_the_repo(stubenv, monkeypatch):
    monkeypatch.setenv("CLAUDE_CODE_SESSION_ID", "5a0ad1e4-6613-4db6-a27f-8e54a547759f")
    r, att = _run_agy(stubenv, "echo OK", "--cwd", str(REPO_ROOT))
    assert r.returncode == 0
    rows = [
        json.loads(x)
        for x in (oa.runtime_dir() / "state" / "outside-agent-runs.jsonl").read_text().splitlines()
    ]
    assert {x["session_id"] for x in rows} == {"5a0ad1e4-6613-4db6-a27f-8e54a547759f"}
    assert att[0]["repo"] == str(REPO_ROOT.resolve())


def test_rows_without_a_session_say_null(stubenv, monkeypatch):
    monkeypatch.delenv("CLAUDE_CODE_SESSION_ID", raising=False)
    r, att = _run_agy(stubenv, "echo OK")
    assert r.returncode == 0
    assert att[0]["session_id"] is None


def test_attempt_logged_for_timeout(stubenv):
    r, att = _run_agy(stubenv, "sleep 30", "--timeout", "1")
    assert r.returncode == 2
    assert [(a["agent"], a["result"]) for a in att] == [("agy", "timeout")]
    assert att[0]["duration_ms"] >= 900


def test_attempt_logged_for_rate_limit_and_auth_and_empty_and_error(stubenv):
    cases = {
        'echo "usage limit reached" >&2; exit 1': "rate_limit",
        'echo "not logged in" >&2; exit 1': "auth",
        "exit 0": "empty",
        'echo "segfault" >&2; exit 1': "error",
    }
    for body, expected in cases.items():
        oa.state_path().unlink(missing_ok=True)
        (oa.runtime_dir() / "state" / "outside-agent-runs.jsonl").unlink(missing_ok=True)
        r, att = _run_agy(stubenv, body)
        assert r.returncode == 2, body
        assert [a["result"] for a in att] == [expected], body


def test_attempt_logged_for_precheck_skip_without_running_the_agent(stubenv):
    bin_, home = stubenv
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 2
    att = _attempts(home)
    assert [(a["agent"], a["result"]) for a in att] == [("agy", "skipped")]
    assert att[0]["duration_ms"] == 0 and "agy not on PATH" in att[0]["reason"]


def test_attempt_logging_leaves_exit_codes_and_order_unchanged(stubenv):
    bin_, home = stubenv
    (home / ".codex").mkdir()
    (home / ".codex" / "auth.json").write_text("{}")
    _stub(bin_, "codex", 'echo "usage limit reached" >&2; exit 1')
    _stub(bin_, "agy", "echo second-ok")
    _conf(home, "codex", "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 0 and "second-ok" in r.stdout
    assert [(a["agent"], a["result"]) for a in _attempts(home)] == [
        ("codex", "rate_limit"),
        ("agy", "ok"),
    ]


def test_attempt_logged_when_interrupted_by_sigterm(stubenv):
    import signal
    import time as _time

    bin_, home = stubenv
    _stub(bin_, "agy", "sleep 30")
    _conf(home, "agy")
    proc = subprocess.Popen(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "outside_agent.py"),
            "run",
            "--purpose",
            "review",
            "--from",
            "claude",
            "--timeout",
            "60",
            "--",
            "p",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    _time.sleep(1.5)
    proc.send_signal(signal.SIGTERM)
    proc.communicate(timeout=15)
    assert proc.returncode == 128 + signal.SIGTERM
    att = _attempts(home)
    assert [(a["agent"], a["result"]) for a in att] == [("agy", "interrupted")]


def test_attempt_logging_failure_never_changes_the_result(stubenv, monkeypatch):
    bin_, home = stubenv
    _stub(bin_, "agy", "echo OK")
    _conf(home, "agy")
    (oa.runtime_dir() / "state").mkdir(parents=True, exist_ok=True)
    (oa.runtime_dir() / "state" / "outside-agent-runs.jsonl").mkdir()
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 0 and "OK" in r.stdout


def test_attempt_logged_for_shared_quota_skip(stubenv, monkeypatch):
    bin_, home = stubenv
    _conf(home, "claude-kiro", "codex-kiro")
    monkeypatch.setattr(oa, "precheck", lambda name, env: None)
    calls: list[str] = []

    def fake_run_one(name, prompt, purpose, allow_edits, timeout, cwd):
        calls.append(name)
        return "rate_limit", "usage limit reached"

    monkeypatch.setattr(oa, "run_one", fake_run_one)
    args = argparse.Namespace(
        purpose="delegate",
        from_="gemini",
        prompt="p",
        timeout=5,
        cwd=None,
        allow_edits=False,
        rubric=False,
    )
    assert oa.cmd_run(args) == 2
    assert calls == ["claude-kiro"]
    assert [(a["agent"], a["result"]) for a in _attempts(home)] == [
        ("claude-kiro", "rate_limit"),
        ("codex-kiro", "skipped"),
    ]


def test_error_attempt_records_a_bounded_scrubbed_reason(stubenv):
    r, att = _run_agy(
        stubenv,
        "echo 'HTTP 429 Too Many Requests at /Users/bob/secret/x using sk-abcdefghijkl123' >&2; exit 1",
    )
    assert r.returncode == 2
    assert [a["result"] for a in att] == ["error"]
    reason = att[0]["reason"]
    assert "429" in reason
    assert "/Users/bob" not in reason and "sk-abcdefghijkl123" not in reason
    assert len(reason) <= 200


def test_empty_output_error_has_no_reason_but_keeps_its_result(stubenv):
    r, att = _run_agy(stubenv, "exit 1")
    assert [a["result"] for a in att] == ["empty"] and "reason" not in att[0]


def test_reason_does_not_change_return_code_or_stderr_message(stubenv):
    r, att = _run_agy(stubenv, "echo 'boom 429' >&2; exit 1")
    assert r.returncode == 2 and "unclassified error" in r.stderr and "boom 429" in r.stderr


@pytest.mark.parametrize(
    "junk", ["\x1b[31mred\x1b[0m 429", "a" * 5000, "line1\nline2\n429", "tab\t429"]
)
def test_reason_is_single_line_and_bounded(stubenv, junk):
    body = "printf '%s' " + json.dumps(junk) + " >&2; exit 1"
    r, att = _run_agy(stubenv, body)
    reason = att[0].get("reason", "")
    assert "\n" not in reason and "\x1b" not in reason and len(reason) <= 200


def test_review_default_timeout_is_longer_than_delegate(stubenv):
    assert oa.default_timeout("review") > oa.default_timeout("delegate") == 110
    assert oa.default_timeout("review") == 1200


def test_explicit_timeout_wins_over_the_purpose_default(stubenv):
    bin_, home = stubenv
    _stub(bin_, "agy", "sleep 30")
    _conf(home, "agy")
    r = cli("run", "--purpose", "review", "--from", "claude", "--timeout", "1", "--", "p")
    assert "agy(timeout after 1s)" in r.stderr


_REASON_SHAPE = re.compile(
    r"(?:http [45][0-9]{2}|[a-z][a-z ]*[a-z]|unrecognized, [0-9]+ chars)(?:; (?:http [45][0-9]{2}|[a-z][a-z ]*[a-z]))*"
)
_HOSTILE = [
    'password="hunter 2 xyz"',
    '{"password":"x y"}',
    "DB_PASS=hunter2",
    "api key: hunter2value",
    "Cookie: theme=dark; session=abc123; csrf=xyz789; id=44",
    "to" + "ken%3D" + "".join(["ab", "cd", "ef", "12", "34", "56"]),
    "/Users/bob/My Documents/secret project/x",
    "C:\\Users\\bob\\secret.txt",
    "user:pass@host",
    "-----begin private key----- QUJDREVGR0hJ",
    "failed at /home/bob/.ssh/id_rsa with sk-abcdefghijkl123456",
    "api_key-429-secret",
    "/build/503/output",
    "request-id=402-test",
    "connect localhost:500",
    "10.0.0.1:443 refused",
    "SyntaxError at line 404",
    "tokens used 450 of 500",
    "sk-ant-api03-AAAA_429_BBBB",
    "id=503",
    "Enjoy some time outdoors",
    "Filename too long",
    "request took too long",
    "line too long (E501)",
    "uptime out of range",
    "cannot find module 'timeout'",
    "method unavailable in this build",
]


@pytest.mark.parametrize("text", _HOSTILE, ids=lambda v: "case")
def test_error_reason_output_has_only_the_allowed_shape(text):
    out = oa.error_reason(text)
    assert _REASON_SHAPE.fullmatch(out), out
    assert len(out) <= oa.REASON_MAX and "\n" not in out


@pytest.mark.parametrize("text", _HOSTILE, ids=lambda v: "case")
def test_error_reason_never_reports_a_status_for_digits_that_are_not_a_status(text):
    if text in ("SyntaxError at line 404",):
        assert "http" not in oa.error_reason(text)
    for fragment in ("429", "503", "402", "500", "443", "404", "450"):
        if fragment in text and not re.search(
            r"(?i)\b(http|status|error|code|returned)\b[^0-9]{0,12}" + fragment, text
        ):
            assert "http " + fragment not in oa.error_reason(text), (text, oa.error_reason(text))


@pytest.mark.parametrize(
    "text,expected",
    [
        ("HTTP 429 Too Many Requests: slow down", ["http 429", "too many requests"]),
        ("Error: 429.", ["http 429"]),
        ("status code 503.\n", ["http 503"]),
        ("request failed with status 502", ["http 502"]),
        ("rate_limit_error: overloaded", ["rate limit"]),
        ("ratelimit hit", ["rate limit"]),
        ("TooManyRequestsException", ["too many requests"]),
        ("context_length_exceeded", ["context too long"]),
        ("Request too large for model", ["request too large"]),
        ("402 payment required", ["payment required"]),
        ("insufficient credits", ["insufficient credits"]),
        ("getaddrinfo ENOTFOUND api.example.com", ["host not found"]),
        ("socket hang up", ["connection reset"]),
        ("connection reset by peer", ["connection reset"]),
        ("Error: ECONNREFUSED 127.0.0.1:443", ["connection refused"]),
        ("certificate verify failed", ["certificate"]),
        ("Invalid API key", ["invalid api key"]),
        ("Internal Server Error", ["server error"]),
        ("the command timed out after 110s", ["timed out"]),
    ],
)
def test_error_reason_names_the_kinds_that_reach_it(text, expected):
    got = oa.error_reason(text)
    for part in expected:
        assert part in got, (text, got)


def test_a_status_at_the_end_of_a_very_long_output_is_still_found():
    out = oa.error_reason(("x" * 200_000) + "\nHTTP 429 Too Many Requests")
    assert "http 429" in out and "too many requests" in out


def test_unrecognized_output_is_logged_by_size_only():
    out = oa.error_reason("some completely unexpected failure text " * 10)
    assert out.startswith("unrecognized") and "chars" in out
    assert "unexpected" not in out


def test_error_reason_is_linear_on_huge_single_line_output():
    start = time.perf_counter()
    for text in (
        "a" * 10_000_000,
        "/" * 10_000_000,
        "token=" * 2_000_000,
        "429 " * 2_000_000,
        "HTTP 4" * 1_000_000,
    ):
        oa.error_reason(text)
    assert time.perf_counter() - start < 3.0


def test_error_reason_handles_empty_and_odd_input():
    assert oa.error_reason("") == ""
    assert oa.error_reason("   \n\t ") == ""
    assert oa.error_reason("\x00\x1b[0m") is not None
    assert oa.error_reason("\ud800" * 1000) is not None


@pytest.mark.parametrize(
    "result_body",
    [
        "echo 'HTTP 429 Too Many Requests' >&2; exit 1",
        "echo 'You have hit your usage limit' >&2; exit 1",
        "echo '401 Unauthorized' >&2; exit 1",
        "exit 1",
    ],
)
def test_reason_is_set_only_when_the_result_is_a_plain_error(stubenv, result_body):
    r, att = _run_agy(stubenv, result_body)
    has_reason = "reason" in att[0]
    assert has_reason == (att[0]["result"] == "error")


def test_error_attempt_records_a_kind_not_the_text(stubenv):
    r, att = _run_agy(
        stubenv, "echo 'HTTP 429 at /Users/bob/secret/x using sk-abcdefghijkl123' >&2; exit 1"
    )
    assert r.returncode == 2
    reason = att[0]["reason"]
    assert "429" in reason and "bob" not in reason and "sk-" not in reason and len(reason) <= 200


def test_logging_never_raises_when_the_working_directory_is_gone(stubenv, monkeypatch):
    def gone(*_a, **_k):
        raise FileNotFoundError("cwd removed")

    monkeypatch.setattr(oa.Path, "cwd", gone)
    oa._log_attempt("agy", "review", "claude", "skipped", 0, "precheck")
    oa._log_outside_run("agy", "gemini", "review", "claude", 0, True)
    rows = (oa.runtime_dir() / "state" / "outside-agent-runs.jsonl").read_text().splitlines()
    assert [json.loads(r)["repo"] for r in rows] == [None, None]


def _agy_settings(home):
    return home / ".gemini" / "antigravity-cli" / "settings.json"


def test_allow_agy_merges_the_review_allowlist_and_keeps_other_settings(stubenv):
    _, home = stubenv
    f = _agy_settings(home)
    f.parent.mkdir(parents=True)
    f.write_text(
        json.dumps(
            {"colorScheme": "dark", "permissions": {"allow": ["command(cat)", "command(mine)"]}}
        )
    )
    assert cli("allow-agy").returncode == 0
    assert cli("allow-agy").returncode == 0
    d = json.loads(f.read_text())
    allow = d["permissions"]["allow"]
    assert d["colorScheme"] == "dark" and "command(mine)" in allow
    assert set(oa.AGY_REVIEW_ALLOW) <= set(allow) and len(allow) == len(set(allow))


def test_allow_agy_keeps_the_settings_file_private(stubenv):
    _, home = stubenv
    f = _agy_settings(home)
    f.parent.mkdir(parents=True)
    f.write_text("{}")
    f.chmod(0o600)
    old = os.umask(0o022)
    try:
        assert cli("allow-agy").returncode == 0
    finally:
        os.umask(old)
    assert f.stat().st_mode & 0o777 == 0o600


def test_allow_agy_does_nothing_without_agy_settings_dir(stubenv):
    _, home = stubenv
    r = cli("allow-agy")
    assert r.returncode == 0 and not (home / ".gemini").exists()


def test_allow_agy_leaves_unreadable_settings_alone(stubenv):
    _, home = stubenv
    f = _agy_settings(home)
    f.parent.mkdir(parents=True)
    f.write_text("{not json")
    r = cli("allow-agy")
    assert r.returncode == 2 and f.read_text() == "{not json" and "settings.json" in r.stderr


def test_agy_git_rule_refuses_output_files_and_chained_commands():
    rule = next(x for x in oa.AGY_REVIEW_ALLOW if x.startswith("command(regex:"))
    pat = re.compile(rule[len("command(regex:") : -1])
    for ok in (
        "git log -1 --oneline",
        "git diff HEAD~1 --stat",
        "git show abc123 --name-only",
        "git diff HEAD -- scripts/x.py",
        "git log -p -- f",
        "git log --format=%H -3",
        "git log --pretty=oneline",
        "git diff --unified=5",
        "git ls-files scripts",
        "git blame -L 10,20 scripts/install.sh",
    ):
        assert pat.match(ok), ok
    for bad in (
        "git diff --output=x",
        "git log -1 > x",
        "git diff; rm x",
        "git show $(rm x)",
        "git log --output x",
        'git ls-files "* *"',
        "git grep -Ovim x",
    ):
        assert not pat.match(bad), bad


def test_agy_review_note_names_every_allowed_command():
    for rule in oa.AGY_REVIEW_ALLOW:
        if not rule.startswith("command(regex:"):
            assert rule[len("command(") : -1] in oa.AGY_REVIEW_NOTE, rule
