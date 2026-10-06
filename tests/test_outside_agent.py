"""Tests for scripts/outside_agent.py."""

import os
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
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("PATH", f"{bin_}:/usr/bin:/bin")
    monkeypatch.setenv("OUTSIDE_AGENT_GATEWAY", "http://127.0.0.1:9")
    monkeypatch.delenv("ZDOTDIR", raising=False)
    return bin_, home


def test_build_argv_review_is_read_only():
    argv = oa.build_argv("claude", "p", "review", True)
    assert argv[argv.index("--permission-mode") + 1] == "plan"
    assert argv[-1] == "p"
    agy = oa.build_argv("agy", "p", "review", False)
    assert agy[-2:] == ["-p", "p"]
    assert agy[agy.index("--mode") + 1] == "plan" and agy.index("--mode") < agy.index("-p")
    codex = oa.build_argv("codex", "p", "review", True)
    assert "read-only" in codex and codex[-1] == "p"


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


def test_cli_review_same_family_only_exits_3(stubenv, monkeypatch):
    bin_, home = stubenv
    monkeypatch.setenv("OUTSIDE_AGENT_SKIP_KEYCHAIN", "1")
    _stub(bin_, "claude", "echo LOOKS-FINE")
    _stub(bin_, "agy", 'echo "Not logged in"')
    _conf(home, "agy", "claude")
    r = cli("run", "--purpose", "review", "--from", "claude", "--", "p")
    assert r.returncode == 3 and r.stdout.strip() == "LOOKS-FINE"
    lines = r.stderr.strip().splitlines()
    assert len(lines) == 1 and "used=claude" in lines[0] and "not independent" in lines[0]


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
    assert r.returncode in (0, 3), r.stderr
    assert "used=" in r.stderr
