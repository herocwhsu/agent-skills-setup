#!/usr/bin/env python3
"""Check every shipped hook.json, and any wired copy of it, is still valid.

Usage:
    hook-wiring-check.py <repo_dir> [settings.json ...]

Two classes of failure, both of which otherwise present as a hook that simply
stops firing with nothing logged anywhere:

Repo side (always checked)
  - hook.json is unreadable or declares no event
  - a command hardcodes a path instead of using ${AGENT_SKILLS_DIR}, so it only
    works on the machine it was written on
  - a command's target file does not exist in the tree

Machine side (checked only for settings files that exist)
  - a hook IS wired under an agent skills dir but its target no longer resolves.
    Judged by the path alone, NOT by whether this repo ships a matching hook.json:
    switching between skills repos repoints the skills symlinks, so the surviving
    wired command can name a skill the newly-installed repo does not carry. Keying
    the check off this repo's own hook.json files missed exactly that case -- the
    repo ships none, so there was nothing to match against and the stale wiring
    read as clean. Absence is still never a failure: wiring is opt-in via
    install.sh --with-hook, so a hook the user never asked for is correctly
    missing.

Exit 0 clean, 1 on any failure. Findings go to stdout.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

PLACEHOLDER = "${AGENT_SKILLS_DIR}"

# Claude Code's hook events. A typo here is silent: an unknown event name is
# never dispatched, so the hook is dead while the JSON still looks correct.
KNOWN_EVENTS = {
    "PreToolUse",
    "PostToolUse",
    "UserPromptSubmit",
    "Notification",
    "Stop",
    "SubagentStop",
    "SessionStart",
    "SessionEnd",
    "PreCompact",
}


def _commands(entry: dict) -> list[str]:
    """Commands an entry holds, in either the flat or the wrapped shape."""
    out = []
    if "command" in entry:
        out.append(entry["command"])
    for inner in entry.get("hooks", []) or []:
        if "command" in inner:
            out.append(inner["command"])
    return out


def _target(command: str) -> str:
    """The script path a command runs, dropping any interpreter prefix."""
    parts = command.split()
    for p in parts:
        if p.startswith("${") or "/" in p:
            return p
    return parts[-1] if parts else ""


def check_repo(repo_dir: Path) -> tuple[list[str], dict[str, str]]:
    """Validate shipped hook.json files. Returns (findings, suffix -> hook path)."""
    findings: list[str] = []
    shipped: dict[str, str] = {}
    skills = repo_dir / "skills"
    if not skills.is_dir():
        return [f"{skills} does not exist"], shipped

    for hook_path in sorted(skills.glob("*/*/hook.json")) + sorted(skills.glob("*/hook.json")):
        rel = hook_path.relative_to(repo_dir)
        try:
            data = json.loads(hook_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            findings.append(f"{rel}: unreadable ({e})")
            continue

        events = data.get("hooks")
        if not isinstance(events, dict) or not events:
            findings.append(f"{rel}: declares no hooks")
            continue

        for event, entries in events.items():
            if event not in KNOWN_EVENTS:
                findings.append(
                    f"{rel}: unknown event {event!r} is never dispatched "
                    f"(known: {', '.join(sorted(KNOWN_EVENTS))})"
                )
            for entry in entries or []:
                cmds = _commands(entry)
                if not cmds:
                    findings.append(f"{rel}: {event} entry carries no command")
                for cmd in cmds:
                    target = _target(cmd)
                    if PLACEHOLDER not in target:
                        findings.append(
                            f"{rel}: {event} command does not use {PLACEHOLDER}, so it "
                            f"cannot survive installation: {cmd}"
                        )
                        continue
                    suffix = target.split(PLACEHOLDER, 1)[1]
                    resolved = repo_dir / "skills" / suffix.lstrip("/")
                    if not resolved.is_file():
                        findings.append(
                            f"{rel}: {event} command target does not exist: {suffix.lstrip('/')}"
                        )
                    shipped[suffix] = str(rel)
    return findings, shipped


def _under_skills_dir(target: str) -> bool:
    """Is this target inside an agent's skills tree?

    Every agent skills dir ends in /skills (~/.claude/skills, ~/.kiro/skills,
    ~/.gemini/antigravity-cli/skills, ~/.codex/skills), so one path-segment test
    covers all of them without enumerating agents here. The scope matters: a hook
    may legitimately run an interpreter flag, a binary on PATH or a project-local
    script, and existence-checking those would report breakage that isn't there.
    """
    return "/skills/" in target


def check_settings(settings_path: Path, shipped: dict[str, str]) -> list[str]:
    """A hook wired to a path that no longer resolves. Absence is not a failure."""
    findings: list[str] = []
    if not settings_path.is_file():
        return findings
    try:
        data = json.loads(settings_path.read_text() or "{}")
    except (OSError, json.JSONDecodeError) as e:
        return [f"{settings_path}: unreadable ({e})"]

    for event, entries in (data.get("hooks") or {}).items():
        for entry in entries or []:
            for cmd in _commands(entry):
                target = _target(cmd)
                if not target or "$" in target:
                    # An unexpanded variable (e.g. $CLAUDE_PROJECT_DIR) resolves
                    # at run time, so this check cannot judge it either way.
                    continue
                if not _under_skills_dir(target):
                    continue
                if Path(target).expanduser().is_file():
                    continue

                hook_src = next(
                    (src for suffix, src in shipped.items() if target.endswith(suffix)),
                    None,
                )
                if hook_src:
                    fix = "bash scripts/update.sh (refreshes wired hook paths)"
                    why = f"{hook_src} ships this hook, but the wired path is stale"
                else:
                    fix = (
                        "unwire it: python3 scripts/_settings_merge.py --remove <hook.json> "
                        f"{settings_path}\n         or install the skills repo that provides it"
                    )
                    why = "no hook.json in this repo provides it, so it may be left over from another skills repo"
                findings.append(
                    f"{settings_path}: {event} is wired to a path that no longer resolves, "
                    f"so the hook silently never fires: {target}\n"
                    f"    {why}\n"
                    f"    fix: {fix}"
                )
    return findings


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: hook-wiring-check.py <repo_dir> [settings.json ...]", file=sys.stderr)
        return 2
    repo_dir = Path(sys.argv[1]).resolve()
    findings, shipped = check_repo(repo_dir)
    for raw in sys.argv[2:]:
        findings.extend(check_settings(Path(raw).expanduser(), shipped))
    for f in findings:
        print(f"  {f}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
