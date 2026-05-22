# polish-input — Design Spec

**Date:** 2026-05-22
**Status:** Draft, pending user review
**Scope:** Add a new skill `polish-input` to this repo that polishes the user's English prompts in real time as a learning side-channel. Distributed via the existing `registry.txt` + `scripts/install.sh` mechanism, with an opt-in flag that wires the runtime hook into Claude Code.

---

## Goals

- Help an ESL user learn natural English on the fly: every imperfect prompt produces a polished version visible in the terminal, immediately, with zero effort.
- Default behavior must not change what Claude receives — the polish is purely pedagogical unless the user explicitly opts in.
- Distribution rides the existing patterns of this repo (one-line entry in `registry.txt`, one install script).

## Non-goals

- Gemini CLI support. Gemini does not currently expose a per-prompt hook mechanism we can rely on. The skill installs as a standard agentskills.io skill, but the hook-driven runtime is Claude-Code only in this iteration.
- Windows hook auto-wiring. `install.ps1` is unchanged; the skill files deploy on Windows but the hook setup step is manual via README.
- Polishing code, multi-line prompts, or slash commands.
- Translation, tone rewriting, or non-English polish. English grammar/fluency only.

---

## User Experience

### Default mode (out-of-the-box)

```
you> i want add new feature for login
[polish] I want to add a new feature for login.
claude> Sure — let's start by looking at the auth code…
```

- Claude receives the original text (`i want add new feature for login`). The polish is informational only.
- A correctly-written prompt produces no `[polish]` line at all.

### Replace mode (opt-in via `POLISH_REPLACE=1`)

```
you> i want add new feature for login
[polish] I want to add a new feature for login.
claude>  # receives "I want to add a new feature for login."
```

- The polished version goes to Claude in place of the original.
- Documented as a learning trade-off: cleaner prompts may help Claude, but the polish is no longer purely a side-channel.

### Skip rules

The hook is a no-op (original passes through, no `[polish]` line) when:

1. The prompt begins with `/` (slash command).
2. The prompt contains a newline (`\n`) anywhere — multi-line prompts skip entirely.
3. `POLISH_DISABLE=1` is set.

---

## Architecture

### Component layout

```
skills/polish-input/
├── SKILL.md          # agentskills.io metadata + agent-facing instructions
├── README.md         # human-facing usage, install, configuration, examples
├── hook.json         # the UserPromptSubmit JSON snippet, used by install.sh
└── lib/
    └── polish.py     # runtime — called by Claude Code's hook system

# Outside the skill folder
registry.txt          # add line: local polish-input
scripts/install.sh    # add --with-hook <skill> flag
scripts/uninstall.sh  # add un-wire counterpart
```

### Runtime data flow

```
you submit prompt
       │
       ▼
Claude Code UserPromptSubmit hook
       │
       ▼
python3 ~/.claude/skills/polish-input/lib/polish.py
       │   stdin:  full prompt text
       │   env:    POLISH_REPLACE, POLISH_DISPLAY,
       │           POLISH_DISABLE, POLISH_DEBUG
       │
       ├── skip rules apply  ──────────────► stdout = original, stderr empty
       │
       ├── language_tool_python.LanguageTool().correct(text)
       │       (lazy-initialized, cached in module-level singleton)
       │
       ├── if corrected == original ───────► stdout = original, stderr empty
       │
       └── if corrected ≠ original
              ├── stderr: formatted polish line per POLISH_DISPLAY
              └── stdout: corrected if POLISH_REPLACE=1 else original
       ▼
Claude receives stdout
User sees stderr in their terminal
```

### Why a hook, not a slash command

- The user picked "auto, only show when changed" — that requires intercepting every prompt, which only `UserPromptSubmit` provides.
- Slash commands are explicit-invocation only (`/polish ...`), which contradicts the "always learning, zero effort" requirement.
- The hook lives in the user's `~/.claude/settings.json`, so it does not interfere with other skills' loading or behavior.

---

## Configuration Surface

All optional, sane defaults mean zero-config works.

| Env var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op (instant escape hatch). |
| `POLISH_REPLACE` | unset | If `1`, replace Claude's prompt with the polished text. |
| `POLISH_DISPLAY` | `line` | Format: `line` (single stderr line), `diff` (word-level diff with insertions/deletions highlighted), `box` (boxed block). |
| `POLISH_DEBUG` | unset | If `1`, append diagnostic info to `~/.claude/skills/polish-input/debug.log`. |

Set in `~/.claude/settings.json` under the top-level `env` map, or in shell rc.

---

## Polish Engine

### Choice: local LanguageTool via `language_tool_python`

- **Pros:** runs offline, fully private, fast after warmup (~50ms per check), broad ESL coverage including article/plural/tense rules and many fluency hints.
- **Cons:** requires a JRE; first invocation downloads ~200MB and takes 30+ seconds.

### Java setup

The runtime requires a JRE. Handling:

- `scripts/install.sh --with-hook polish-input` checks `java -version`.
  - **Present:** continue.
  - **Missing on macOS with Homebrew:** prompt `Install OpenJDK 17 via brew? [y/N]`. On consent, run `brew install openjdk@17`.
  - **Missing on Linux with apt:** prompt `Install default-jre via apt? [y/N]`. On consent, run `sudo apt-get install default-jre`.
  - **Other / declined:** print a setup hint pointing to README install steps; continue installing the skill files. The hook is wired regardless; if Java is later missing at runtime, the hook fails open (see below).

### First-run behavior

`language_tool_python` downloads the LT JAR (~200MB) on first construction. The runtime:

- Creates a singleton `LanguageTool` instance lazily (first prompt that survives skip rules).
- On the first construction, prints `[polish] initializing LanguageTool, this happens once…` to stderr before blocking on the download.
- Caches a marker file (`~/.claude/skills/polish-input/.initialized`) so the message is suppressed afterward.

### Failure modes

| Condition | Behavior |
|---|---|
| Java missing at runtime | Fail open (stdout = original, no stderr line). On the first failure (detected via the marker file `~/.claude/skills/polish-input/.lt-error`), append a diagnostic line and a setup hint to `debug.log` regardless of `POLISH_DEBUG`. |
| LT download fails (network) | Fail open. Same one-time hint mechanism. |
| LT raises an exception mid-check | Fail open. Log to debug.log. Never block the user's prompt. |
| `polish.py` itself crashes | Hook exit code is non-zero, but Claude Code falls back to the raw prompt; user sees an error line. Recovery: `POLISH_DISABLE=1`. |

The principle: **polish never blocks the user's conversation with Claude.**

---

## Distribution

### `registry.txt`

```
local  polish-input
```

One additional line, follows the existing pattern.

### `scripts/install.sh` changes

Add a new flag `--with-hook <skill-name>` that:

1. Performs the normal skill install for `<skill-name>`.
2. If the skill ships a `hook.json`, runs the hook-wiring steps:
   - Java check + optional install (per OS, see "Java setup" above).
   - `pip install --user language_tool_python`.
   - Merges `hook.json` into `~/.claude/settings.json`. Uses `jq` if available; otherwise a small Python merge helper at `scripts/_settings_merge.py` (new file, added in this work).
3. Prints a summary of what was wired.

Example invocations:

```bash
# Normal install of all registry skills (does not wire the hook)
bash scripts/install.sh

# Install everything plus wire the polish-input hook
bash scripts/install.sh --with-hook polish-input
```

### `scripts/uninstall.sh` changes

Mirror: `--with-hook polish-input` un-wires the hook from `~/.claude/settings.json` and unlinks the skill. Java and the pip package are left in place; the user can remove them manually if desired (documented in README).

### `hook.json` contents

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "command": "python3 ~/.claude/skills/polish-input/lib/polish.py"
      }
    ]
  }
}
```

The merge logic adds these entries without overwriting existing hook entries.

---

## Skill Files

### `SKILL.md`

agentskills.io-compliant frontmatter so the file is valid for any host. Body documents what the skill does and points the agent at the README. The agent itself does not invoke the skill — it runs as a hook — so the SKILL.md mostly exists for discoverability and for hosts that scan the directory.

```markdown
---
name: polish-input
description: Auto-polish single-line English prompts via a UserPromptSubmit hook. Runtime side-channel for ESL learning; does not change Claude's input by default.
---

# polish-input

This skill installs a runtime hook for Claude Code. The agent itself does not need to do anything — see README.md for setup and configuration.
```

### `README.md`

Sections:

1. What it does (one paragraph + the "default mode" example block).
2. Install: `bash scripts/install.sh --with-hook polish-input`. Note Java requirement.
3. Configuration table (the env-var table from this spec).
4. Disable: `POLISH_DISABLE=1` or remove the hook from `settings.json`.
5. Troubleshooting: where to find `debug.log`, common Java errors, manual hook setup for Windows.

### `lib/polish.py`

- Reads stdin, applies skip rules, calls LanguageTool, writes stdout/stderr per spec.
- Module-level singleton for the `LanguageTool` instance.
- All env vars read once at module load.
- Compatible with Python 3.8+ (`language_tool_python` itself requires 3.8).

---

## Testing

### Unit tests (`skills/polish-input/tests/test_polish.py`)

Mock `language_tool_python.LanguageTool` to return controlled corrections.

| Case | Stdin | Expected stdout | Expected stderr |
|---|---|---|---|
| Single-line, change | `i want add login` | `i want add login` | `[polish] I want to add login.` |
| Single-line, no change | `Read the auth file.` | `Read the auth file.` | empty |
| Multi-line | `line1\nline2` | `line1\nline2` | empty |
| Slash command | `/help` | `/help` | empty |
| `POLISH_REPLACE=1` + change | `i want add login` | `I want to add a login.` | `[polish] …` |
| `POLISH_DISABLE=1` | any | unchanged | empty (LT not called) |
| LT raises | any single-line | unchanged | empty |

### Integration test (`skills/polish-input/tests/integration_polish.sh`)

Pipes a known-bad sentence through `polish.py`, asserts the stderr line contains an expected substring. Skipped if Java is unavailable.

### Lint

`ruff` on `lib/polish.py`, `shellcheck` on `scripts/install.sh` and `scripts/uninstall.sh` changes.

---

## Edge Cases & Decisions Already Made

| Edge case | Decision |
|---|---|
| Slash commands | Skip entirely. |
| Multi-line prompts | Skip entirely (do not polish line-by-line). |
| Code blocks / pasted code | Caught by the multi-line rule in practice. |
| Prompt over (say) 4000 chars | Skip — covered implicitly by the multi-line rule for most pastes; we add an explicit `len(text) > 4000` skip as a safety net. |
| First-run JVM download | Lazy-init with one-time stderr message. |
| Java missing at runtime | Fail open + log hint. |
| User wants to undo | `POLISH_DISABLE=1` for instant; `bash scripts/uninstall.sh --with-hook polish-input` for permanent. |
| Other skills in the repo | Untouched. The hook only inspects raw prompt text. |

---

## Out of Scope

- Gemini CLI support.
- Windows hook auto-wiring (skill files install; hook setup is manual).
- Languages other than English.
- Translation or tone rewriting.
- Public LanguageTool API mode.
- Multi-line polish.
- Telemetry / metrics.

---

## Acceptance Criteria

The implementation is complete when:

1. `bash scripts/install.sh --with-hook polish-input` on a fresh macOS or Linux machine installs the skill, optionally installs Java if needed, and wires the hook.
2. With the hook active, typing `i want add login` in Claude Code shows `[polish] I want to add a login.` (or similar) on stderr, and Claude receives `i want add login`.
3. Setting `POLISH_REPLACE=1` causes Claude to receive the polished version instead.
4. `POLISH_DISABLE=1` makes the hook a no-op.
5. Multi-line and slash-command prompts pass through silently.
6. `bash scripts/uninstall.sh --with-hook polish-input` removes the hook entry from `settings.json` and unlinks the skill.
7. Unit tests pass on a machine without Java (using mocks).
