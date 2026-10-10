#!/usr/bin/env python3
"""Fail if a SKILL.md frontmatter scalar would not parse as strict YAML.

An unquoted value containing ': ' or ' #' is a YAML error. Claude Code accepts it;
agy's parser drops the whole skill ("mapping values are not allowed"). No PyYAML
dependency: this repo pins none, so the check is the one rule that bit us.
Usage: skill-frontmatter-check.py <skills-dir>
"""
import re
import sys
from pathlib import Path

bad = []
for f in sorted(Path(sys.argv[1]).rglob("SKILL.md")):
    m = re.match(r"---\n(.*?)\n---", f.read_text(), re.S)
    if not m:
        continue
    for line in m.group(1).split("\n"):
        kv = re.match(r"([A-Za-z][\w-]*):\s+(.*)", line)
        if not kv:
            continue
        val = kv.group(2)
        if val and val[0] not in "\"'>|[{" and re.search(r": | #|:$", val):
            bad.append(f"{f}: {kv.group(1)} has an unquoted ': ' or ' #'; wrap the value in double quotes")
if bad:
    print("\n".join(bad))
    sys.exit(1)
