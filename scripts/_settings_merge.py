#!/usr/bin/env python3
"""Merge or remove a hook JSON snippet into ~/.claude/settings.json.

Usage:
    _settings_merge.py --merge  hook.json settings.json
    _settings_merge.py --remove hook.json settings.json
    _settings_merge.py --rewire hook.json settings.json --skills-dir DIR

Operates only on top-level "hooks.<EventName>" arrays. Preserves all other keys
and other event names. Idempotent. Creates settings.json if missing on --merge.

--rewire refreshes an entry that is *already* present, and adds nothing. A hook
command embeds an absolute skills path, so moving the skills tree leaves the
wired command pointing at a path that no longer resolves; the hook then fails
silently because nothing re-runs the wiring. Rewire matches an existing entry by
its skill-relative suffix, so a stale prefix is recognised and replaced. Absence
means the user never opted in, and stays absence.
"""

import argparse
import json
import sys
from pathlib import Path


def load_settings(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as e:
        print(f"error: {path} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)


def save_settings(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def _entry_commands(entry: dict) -> set:
    """Extract command strings an entry represents.

    Hook entries come in two shapes:
      flat:    {"command": "..."}
      wrapped: {"matcher": "...", "hooks": [{"command": "..."}, ...]}
    Claude Code rewrites flat entries to wrapped form, so dedup must
    compare commands across both shapes.
    """
    cmds = set()
    if "command" in entry:
        cmds.add(entry["command"])
    for inner in entry.get("hooks", []) or []:
        if "command" in inner:
            cmds.add(inner["command"])
    return cmds


def merge(hook: dict, settings: dict) -> dict:
    settings.setdefault("hooks", {})
    for event, entries in hook.get("hooks", {}).items():
        existing = settings["hooks"].setdefault(event, [])
        existing_cmds = set().union(*(_entry_commands(h) for h in existing)) if existing else set()
        for entry in entries:
            if not _entry_commands(entry) & existing_cmds:
                existing.append(entry)
                existing_cmds |= _entry_commands(entry)
    return settings


def _suffix(command: str, skills_dir: str) -> str | None:
    """The skill-relative tail of a hook command, e.g. /utils/polish-input/lib/polish.py.

    This is the part that survives the skills tree moving, so it is what
    identifies "the same hook" across a path change.
    """
    i = command.find(skills_dir)
    if i == -1:
        return None
    return command[i + len(skills_dir):]


def rewire(hook: dict, settings: dict, skills_dir: str) -> tuple[dict, list]:
    """Replace already-present entries whose path drifted. Never adds."""
    changed = []
    if "hooks" not in settings:
        return settings, changed
    skills_dir = skills_dir.rstrip("/")
    for event, entries in hook.get("hooks", {}).items():
        existing = settings["hooks"].get(event)
        if not existing:
            continue
        for entry in entries:
            for fresh in sorted(_entry_commands(entry)):
                suffix = _suffix(fresh, skills_dir)
                if not suffix:
                    continue
                for slot in existing:
                    for stale in sorted(_entry_commands(slot)):
                        if stale == fresh or not stale.endswith(suffix):
                            continue
                        # Same hook, different prefix: refresh in place so the
                        # surrounding matcher and any sibling hooks are kept.
                        if slot.get("command") == stale:
                            slot["command"] = fresh
                        for inner in slot.get("hooks", []) or []:
                            if inner.get("command") == stale:
                                inner["command"] = fresh
                        changed.append((event, stale, fresh))
    return settings, changed


def remove(hook: dict, settings: dict) -> dict:
    if "hooks" not in settings:
        return settings
    for event, entries in hook.get("hooks", {}).items():
        if event not in settings["hooks"]:
            continue
        cmds_to_drop = set().union(*(_entry_commands(e) for e in entries)) if entries else set()
        settings["hooks"][event] = [
            h for h in settings["hooks"][event] if not (_entry_commands(h) & cmds_to_drop)
        ]
        if not settings["hooks"][event]:
            del settings["hooks"][event]
    if not settings["hooks"]:
        del settings["hooks"]
    return settings


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--merge", action="store_true")
    group.add_argument("--remove", action="store_true")
    group.add_argument("--rewire", action="store_true")
    parser.add_argument("hook_path", type=Path)
    parser.add_argument("settings_path", type=Path)
    parser.add_argument("--skills-dir", default="")
    args = parser.parse_args()

    if args.rewire and not args.skills_dir:
        print("error: --rewire requires --skills-dir", file=sys.stderr)
        return 2

    hook = json.loads(args.hook_path.read_text())

    if (args.remove or args.rewire) and not args.settings_path.exists():
        return 0

    settings = load_settings(args.settings_path)
    if args.merge:
        settings = merge(hook, settings)
    elif args.rewire:
        settings, changed = rewire(hook, settings, args.skills_dir)
        if not changed:
            return 0
        for event, stale, fresh in changed:
            print(f"  rewired {event}: {stale} -> {fresh}")
    else:
        settings = remove(hook, settings)

    save_settings(args.settings_path, settings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
