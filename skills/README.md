# Skills

Custom agent skills managed by this repo. Each skill follows the [agentskills.io](https://agentskills.io) standard and works with Kiro, Claude Code, GitHub Copilot, and Codex.

## Available Skills

| Skill | What it does |
|---|---|
| [fetch-page-to-markdown](fetch-page-to-markdown/README.md) | Fetch Confluence or any web page → dated markdown file |

## How Skills Work

Each skill is a directory containing at minimum a `SKILL.md` file. The agent reads this file automatically when the skill is installed, and uses it to guide its behavior when the task matches.

```
skills/
└── my-skill/
    ├── SKILL.md      ← required: agent instructions + metadata
    ├── README.md     ← recommended: human-readable usage guide
    └── *.py / *.sh   ← optional: supporting tools referenced by SKILL.md
```

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` following the [agentskills.io spec](https://agentskills.io/specification)
2. Add a `README.md` with human-readable usage examples
3. Add `local  <skill-name>` to `../registry.txt`
4. Run `bash ../scripts/install.sh` (or `.\scripts\install.ps1` on Windows) to deploy

**Minimum `SKILL.md` structure:**

```markdown
---
name: your-skill-name
description: Use when [specific triggering conditions]
---

# Your Skill Name

## Overview
What this skill does in 1-2 sentences.

## When to Use
- Bullet list of situations

## How to Use
Steps or examples.
```

## Skill Naming

- Lowercase, hyphens only: `fetch-page-to-markdown` ✓
- Verb-first where possible: `fetch-`, `generate-`, `convert-` ✓
- No spaces, underscores, or special characters

## What This Repo Does NOT Manage

Skills from [superpowers](https://github.com/obra/superpowers) (brainstorming, TDD, systematic-debugging, etc.) are installed via `registry.txt` from the upstream repo. To update them, run `bash scripts/update.sh`.
