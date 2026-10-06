#!/usr/bin/env python3
"""Pick a working outside CLI agent per call. See docs/superpowers/specs/2026-10-05-outside-agent-design.md."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, NamedTuple, NoReturn


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
# On rc 0 a real answer can mention "quota" or "401", so only a short output that
# is itself a known status message counts; keywords elsewhere in it never do.
RC0_AUTH_RE = re.compile(r"^(not logged in(\W+please run /login)?|please run /login)\W*$", re.I)
RC0_RATE_RE = re.compile(
    r"^(you've hit your usage limit|usage limit reached|monthly quota exceeded|quota exceeded)"
    r"(\W*$|\W+(resets|try again|retry)\b)",
    re.I,
)
SHORT = 80
AUTH_DEMOTE = timedelta(days=7)
SUB_COOLDOWN = timedelta(hours=5)


def classify(rc: int, output: str) -> str:
    text = output.strip()
    if rc == 0 and text:
        if len(text) <= SHORT:
            if RC0_RATE_RE.match(text):
                return "rate_limit"
            if RC0_AUTH_RE.match(text):
                return "auth"
        return "ok"
    if RATE_RE.search(text):
        return "rate_limit"
    if AUTH_RE.search(text):
        return "auth"
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
    if until.tzinfo is None:
        until = until.replace(tzinfo=now.tzinfo)
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
    # Stable sorts: demoted after fresh, then (for review) the caller's family last.
    live.sort(key=lambda n: _active(auth.get(n), now) is not None)
    if purpose == "review":
        live.sort(key=lambda n: KINDS[n].family == caller)
    return live, skipped


STRIP_ENV = (
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "OPENAI_BASE_URL",
    "OPENAI_API_KEY",
)
ESC_RE = re.compile(r"\x1b\][^\x07]*\x07|\x1b\[[0-9;?]*[A-Za-z]")


def _shell() -> str:
    return os.environ.get("OUTSIDE_AGENT_SHELL", "zsh")


def _gateway_up() -> bool:
    import urllib.request

    url = os.environ.get("OUTSIDE_AGENT_GATEWAY", "http://localhost:7788") + "/openapi.json"
    try:
        with urllib.request.urlopen(url, timeout=1) as r:
            return bool(r.status == 200)
    except OSError:
        return False


def precheck(name: str, env: dict[str, str]) -> str | None:
    if KINDS[name].group == "kiro":
        # The HTTP probe takes milliseconds; check it before paying for an interactive shell.
        if not _gateway_up():
            return "kiro-gateway not answering"
        # stdin closed: an interactive zsh with no ~/.zshrc otherwise opens zsh-newuser-install.
        try:
            rc = subprocess.run(
                [_shell(), "-i", "-c", f"alias {name}"],
                capture_output=True,
                env=env,
                timeout=10,
                stdin=subprocess.DEVNULL,
            ).returncode
        except subprocess.TimeoutExpired:
            return "alias check timed out"
        except OSError:
            return f"{_shell()} not available"
        return None if rc == 0 else f"alias {name} not defined"
    if not shutil.which(name, path=env.get("PATH")):
        return f"{name} not on PATH"
    if (
        name == "claude"
        and not env.get("OUTSIDE_AGENT_SKIP_KEYCHAIN")
        and shutil.which("security", path=env.get("PATH"))
    ):
        try:
            r = subprocess.run(
                ["security", "find-generic-password", "-s", "Claude Code-credentials"],
                capture_output=True,
                timeout=10,
                stdin=subprocess.DEVNULL,
            )
        except (subprocess.TimeoutExpired, OSError):
            return "keychain check failed"
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
        argv = ["agy", *perm, "-p", prompt]
    if KINDS[name].group == "kiro":
        return [_shell(), "-i", "-c", shlex.join(argv)]
    return argv


def run_one(
    name: str, prompt: str, purpose: str, allow_edits: bool, timeout: int, cwd: str | None
) -> tuple[str, str]:
    env = dict(os.environ)
    if KINDS[name].group != "kiro":
        for k in STRIP_ENV:
            env.pop(k, None)
    # Own session so a timeout can kill grandchildren that would otherwise hold the pipes open.
    try:
        proc = subprocess.Popen(
            build_argv(name, prompt, purpose, allow_edits),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            text=True,
            env=env,
            cwd=cwd,
            start_new_session=True,
        )
    except OSError as e:
        return "error", f"failed to start {name}: {e}"

    def kill_group() -> None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        # macOS returns EPERM, not ESRCH, when the group holds only unreaped zombies.
        except (ProcessLookupError, PermissionError):
            pass

    def on_signal(signum: int, frame: object) -> None:
        kill_group()
        sys.exit(128 + signum)

    # signal.signal raises off the main thread; init probes run in a thread pool.
    prev: dict[int, Any] = {}
    if threading.current_thread() is threading.main_thread():
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            prev[sig] = signal.signal(sig, on_signal)
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_group()
        proc.communicate()
        return "transient", f"timed out after {timeout}s"
    except BaseException:
        if proc.poll() is None:
            kill_group()
        raise
    finally:
        for signum, h in prev.items():
            signal.signal(signum, h)
    out = ESC_RE.sub("", (stdout or "") + (stderr if proc.returncode else "")).strip()
    return classify(proc.returncode, out), out


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
            raise ConfError(
                f"unknown outside agent '{line}' in {p}; known: {' '.join(DEFAULT_ORDER)}"
            )
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
    for key in ("groups", "auth"):
        if not isinstance(d.get(key), dict):
            d[key] = {}
    return d


def save_state(d: dict) -> None:
    p = state_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(d, indent=2))
    os.replace(tmp, p)


def record(state: dict, name: str, cls: str, until: datetime) -> None:
    if cls == "rate_limit":
        state["groups"][KINDS[name].group] = {"until": until.isoformat(), "by": name}
    elif cls == "auth":
        state["auth"][name] = {"until": until.isoformat()}


def _now() -> datetime:
    return datetime.now().astimezone()


def _say(msg: str, out: Any = None) -> None:
    print(f"[outside-agent] {msg}", file=out or sys.stderr)


def _earliest_reset(state: dict, now: datetime) -> str | None:
    return min((v["until"] for v in state["groups"].values() if _active(v, now)), default=None)


def cmd_run(a: argparse.Namespace) -> int:
    if a.cwd and not os.path.isdir(a.cwd):
        _say(f"--cwd {a.cwd} is not a directory")
        return 2
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
        reset = _earliest_reset(state, now) or "n/a"
        _say(f"no candidate available; skipped={','.join(notes)}; earliest reset {reset}")
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
            if state["auth"].pop(name, None) is not None:
                save_state(state)
            used = f"used={name} skipped={','.join(notes) or '-'}"
            if a.purpose == "review" and KINDS[name].family == a.from_:
                _say(f"{used} (not independent: same model family as caller)")
                return 3
            _say(used)
            return 0
        notes.append(f"{name}({cls})")
        if cls == "rate_limit":
            record(state, name, cls, rate_limit_reset(KINDS[name].group, now, out))
            limited.add(KINDS[name].group)
            save_state(state)
        elif cls == "auth":
            record(state, name, cls, now + AUTH_DEMOTE)
            save_state(state)
        elif cls == "error":
            _say(f"{name} failed with an unclassified error, stopping:\n{out}")
            return 2
    earliest = _earliest_reset(state, now)
    tail = f"; earliest reset {earliest}" if earliest else ""
    _say(f"no candidate succeeded; tried={','.join(notes)}{tail}")
    return 2


def _probe_cwd() -> str:
    d = runtime_dir()
    try:
        d.mkdir(parents=True, exist_ok=True)
    except OSError:
        return tempfile.gettempdir()
    return str(d)


def _probe(name: str, cwd: str) -> tuple[str, str]:
    why = precheck(name, dict(os.environ))
    if why:
        return name, why
    cls, out = run_one(name, "Reply with exactly: OK", "review", False, 60, cwd)
    return name, ("ok" if cls == "ok" else (out.splitlines() or [cls])[-1][:60])


def cmd_init(a: argparse.Namespace) -> int:
    from concurrent.futures import ThreadPoolExecutor

    # A repo's agent Stop hooks (e.g. a harness gate) would run after every probe answer.
    cwd = _probe_cwd()
    try:
        with ThreadPoolExecutor(max_workers=len(DEFAULT_ORDER)) as ex:
            results = dict(ex.map(lambda n: _probe(n, cwd), DEFAULT_ORDER))
    except Exception as e:  # install must not fail on detection
        _say(f"WARNING: detection failed: {e}", sys.stdout)
        results = {}
    live = [n for n in DEFAULT_ORDER if results.get(n) == "ok"]
    failed = [(n, results.get(n, "not probed")) for n in DEFAULT_ORDER if n not in live]
    if conf_path().exists() and not a.force:
        try:
            listed = read_conf()
        except ConfError as e:
            _say(f"WARNING: {e}", sys.stdout)
            return 0
        add = [n for n in live if n not in listed]
        gone = [n for n in listed if n not in live]
        if add or gone:
            _say(
                f"detected but not listed: {' '.join(add) or '-'}; "
                f"listed but not found: {' '.join(gone) or '-'}",
                sys.stdout,
            )
        else:
            _say("conf matches detection", sys.stdout)
        return 0
    try:
        write_conf(live, failed, _now().strftime("%Y-%m-%d"))
    except OSError as e:
        _say(f"WARNING: could not write {conf_path()}: {e}", sys.stdout)
        return 0
    _say(f"wrote {conf_path()}: {' '.join(live) or '(none)'}", sys.stdout)
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
    if a.target and a.target not in KINDS and a.target not in {k.group for k in KINDS.values()}:
        _say(f"unknown target '{a.target}'; known: {' '.join(DEFAULT_ORDER)} or a group")
        return 2
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


def _positive_int(s: str) -> int:
    try:
        n = int(s)
    except ValueError:
        n = 0
    if n < 1:
        raise argparse.ArgumentTypeError(f"must be an integer >= 1, got {s!r}")
    return n


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
    r.add_argument("--timeout", type=_positive_int, default=110)
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
