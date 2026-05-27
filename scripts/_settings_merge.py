#!/usr/bin/env python3
"""Merge or remove a hook JSON snippet into ~/.claude/settings.json.

Usage:
    _settings_merge.py --merge  hook.json settings.json
    _settings_merge.py --remove hook.json settings.json

Operates only on top-level "hooks.<EventName>" arrays. Preserves all other keys
and other event names. Idempotent. Creates settings.json if missing on --merge.
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
    parser.add_argument("hook_path", type=Path)
    parser.add_argument("settings_path", type=Path)
    args = parser.parse_args()

    hook = json.loads(args.hook_path.read_text())

    if args.remove and not args.settings_path.exists():
        return 0

    settings = load_settings(args.settings_path)
    if args.merge:
        settings = merge(hook, settings)
    else:
        settings = remove(hook, settings)

    save_settings(args.settings_path, settings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
