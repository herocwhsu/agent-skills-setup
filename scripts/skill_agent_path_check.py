#!/usr/bin/env python3
"""Flag shell recipes in skills/ that name one agent's skills directory.

Usage:
    skill_agent_path_check.py [skills-dir]

Every skill is installed under up to four agent dirs (~/.claude/skills,
~/.codex/skills, ~/.kiro/skills, ~/.gemini/antigravity-cli/skills), and only the
agents the user selected have it. A recipe that runs
`bash ~/.claude/skills/infra/ups/lib/ups.sh` therefore works for Claude Code and
fails on the others with "No such file", which reads as a broken skill rather
than a wrong path. A recipe finds its own directory with `find_skill_dir` from
lib.sh instead.

Only fenced shell blocks are checked: prose that says where a skill is installed
is documentation, not something an agent executes. Only the skills directories
are matched: `~/.claude/settings.json` is a real per-agent config file that a
recipe may legitimately address.
"""

import re
import sys
from pathlib import Path

BLOCK = re.compile(r"```(?:bash|sh|shell)\n(.*?)```", re.S)
AGENT_SKILLS_PATH = re.compile(
    r"(?:\$\{?HOME\}?|~)/\.(?:claude|kiro|codex|gemini)/(?:antigravity-cli/)?skills\b"
)


def findings_for(text: str) -> list[str]:
    """Each distinct agent skills path used inside a shell block, in order of first use."""
    hits: list[str] = []
    for block in BLOCK.findall(text):
        for m in AGENT_SKILLS_PATH.finditer(block):
            if m.group(0) not in hits:
                hits.append(m.group(0))
    return hits


def main() -> int:
    root = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parent.parent / "skills"
    )
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 1

    total = 0
    for path in sorted(root.rglob("*.md")):
        for hit in findings_for(path.read_text(encoding="utf-8")):
            total += 1
            print(f"  AGENT-PATH  {path}: {hit} is one agent's skills directory")

    if total:
        print(f"\n{total} agent-specific skills path(s) in skill shell blocks.")
        print('Resolve it: source ~/.agent-skills-setup/lib.sh; DIR=$(find_skill_dir <group>/<sub>) || exit 1')
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
