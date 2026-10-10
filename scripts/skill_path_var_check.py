#!/usr/bin/env python3
"""Flag shell recipes in skills/ that build a repo path from an undefined variable.

Usage:
    skill-path-var-check.py [skills-dir]

A SKILL.md/IMPL.md shell block runs in whatever shell the agent has, with only
what `lib.sh` and `config.sh` provide. A variable the block never defines
expands to the empty string, so `"$REPO_DIR/scripts/foo.py"` silently becomes
`/scripts/foo.py` -- a path that cannot exist. That is not a typo the agent can
recover from: the recipe reads as if it works, and the failure surfaces as a
missing file somewhere else.

Why this checks *paths* and not every undefined variable
--------------------------------------------------------
A general undefined-variable check was measured against this tree first: it
reported 12 names, and every one was correct as written --

  JIRA_HOST, JIRA_USER, CONFLUENCE_HOST, CONFLUENCE_USER, JIRA_PROJECT_KEY,
  APIDOG_PROJECT_ID   arrive via load_config sourcing ~/.agent-skills-setup/config.sh
  SHARE_URL, STORY_ID, SUBTASK_ID, BUG_TITLE, CONTRACT_PATH_PREFIX
                      deliberate fill-in placeholders the operator supplies
  head                a jq --arg binding, not a shell variable at all

Shipping that would have meant a gate whose every finding is noise, and a gate
born suppressed blocks nothing -- the failure mode AGENTS.md records for
sh-check.sh. So the rule is narrowed to the shape that was a real defect: an
undefined variable used to build a filesystem path into one of this repo's own
directories. config.sh values are hostnames and ids, never repo paths, so they
cannot collide with it.

Definitions are collected across every block in a file before uses are checked,
so a variable defined in an earlier or later block counts. That errs toward
silence: this gate exists to catch an unreachable path, not to enforce that
each block is standalone.
"""

import re
import sys
from pathlib import Path

# Directories that only exist inside this repo. A path built into one of these
# is addressing the setup tree, so its root variable has to resolve.
REPO_SUBDIRS = ("scripts", "skills", "lib", "hooks", "agents", "prompts", "config", "tests")

BLOCK = re.compile(r"```(?:bash|sh|shell)\n(.*?)```", re.S)
ASSIGN = re.compile(
    r"(?:^|\s|\||;|&&|\|\||\()(?:local\s+|export\s+|declare\s+)?([A-Za-z_][A-Za-z0-9_]*)="
)
FOR_VAR = re.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b")
READ_VAR = re.compile(r"\bread\s+(?:-[A-Za-z]+\s+)*((?:[A-Za-z_][A-Za-z0-9_]*\s*)+)")
PATH_USE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/(" + "|".join(REPO_SUBDIRS) + r")/")

# $HOME is always set by the shell; a path under it is the runtime dir, not the repo.
ALWAYS_SET = frozenset({"HOME"})


def defined_names(blocks: list[str]) -> set[str]:
    """Every variable the file's shell blocks assign, loop over, or read into."""
    names: set[str] = set()
    for block in blocks:
        names.update(m.group(1) for m in ASSIGN.finditer(block))
        names.update(m.group(1) for m in FOR_VAR.finditer(block))
        for m in READ_VAR.finditer(block):
            names.update(m.group(1).split())
    return names


def findings_for(text: str) -> list[tuple[str, str]]:
    """(variable, repo-subdir) for each undefined variable used as a repo path."""
    blocks = BLOCK.findall(text)
    if not blocks:
        return []
    defined = defined_names(blocks) | ALWAYS_SET
    hits: list[tuple[str, str]] = []
    for block in blocks:
        for m in PATH_USE.finditer(block):
            if m.group(1) not in defined:
                hits.append((m.group(1), m.group(2)))
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
        seen: set[tuple[str, str]] = set()
        for var, subdir in findings_for(path.read_text(encoding="utf-8")):
            if (var, subdir) in seen:
                continue
            seen.add((var, subdir))
            total += 1
            print(f"  UNDEFINED  {path}: ${var}/{subdir}/ — ${var} is never defined in this file")

    if total:
        print(f"\n{total} unresolvable repo path(s) in skill shell blocks.")
        print("Define the variable in the block, or resolve it with setup_repo_dir from lib.sh.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
