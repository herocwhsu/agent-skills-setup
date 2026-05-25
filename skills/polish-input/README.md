# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code.

## What it does

```
you> i want add new feature for login
[polish] I want to add a new feature for login.
claude> Sure — let's start by looking at the auth code…
```

Claude receives the original prompt by default. The polish line is purely informational.

## Install

```bash
bash scripts/install.sh --with-hook polish-input
```

This:
1. Installs the skill files (symlinks `skills/polish-input/` → `~/.claude/skills/polish-input/`).
2. Checks for a Java runtime; offers to install OpenJDK via brew (macOS) or apt (Linux) if missing.
3. Installs `language_tool_python` via pip.
4. Merges the `UserPromptSubmit` hook into `~/.claude/settings.json`.

The first prompt after install downloads the LanguageTool JAR (~200MB) and shows `[polish] initializing LanguageTool, this happens once…`.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to Claude instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.claude/state/polish-input/debug.log`. |

Set them in `~/.claude/settings.json` under `env`, or in your shell rc.

## Skip rules

The hook is silent when:
- The prompt starts with `/` (slash command).
- The prompt contains a newline (multi-line).
- The prompt is over 4000 characters.
- `POLISH_DISABLE=1` is set.
- LanguageTool is unavailable (fail open).

## Uninstall

```bash
bash scripts/uninstall.sh --with-hook polish-input
```

Removes the hook entry and unlinks the skill. Java and the pip package are left in place; remove manually if desired.

## Troubleshooting

- **No polish appears on imperfect prompts:** Check `~/.claude/state/polish-input/debug.log`. Most likely cause: Java is missing.
- **First prompt hangs for 30+ seconds:** Expected. LanguageTool is downloading on first use; this only happens once.
- **Windows:** Auto-wiring is not implemented. Install the skill files normally, then manually add the hook from `hook.json` to `%USERPROFILE%\.claude\settings.json`.
