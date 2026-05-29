# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code.
Uses Claude Haiku 4.5 via the Anthropic SDK.

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
2. Installs the `anthropic` Python SDK via pip.
3. Merges the `UserPromptSubmit` hook into `~/.claude/settings.json`.

The hook reads `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` from the
environment Claude Code runs in. In Kiro mode these are already set to point
at the Kiro gateway; no second API key is required.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to Claude instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.claude/state/polish-input/debug.log`. |
| `POLISH_MODEL` | `claude-haiku-4-5` | Override the polish model. |
| `POLISH_TIMEOUT_MS` | `3000` | API timeout in milliseconds. |

Set them in `~/.claude/settings.json` under `env`, or in your shell rc.

## Skip rules

The hook is silent when:
- The prompt starts with `/` (slash command).
- The prompt contains a newline (multi-line).
- The prompt is over 4000 characters.
- `POLISH_DISABLE=1` is set.
- The polish engine is unavailable (fail open).

## Uninstall

```bash
bash scripts/uninstall.sh --with-hook polish-input
```

Removes the hook entry and unlinks the skill. The `anthropic` package is
left in place; remove manually with `pip uninstall anthropic` if desired.

## Troubleshooting

- **No polish appears:** Check `~/.claude/state/polish-input/debug.log`.
  Common causes: `anthropic` not installed, or `ANTHROPIC_API_KEY` not set in
  the environment Claude Code runs in.
- **Polish is slow (>3s):** The hook times out at 3s by default. Bump
  `POLISH_TIMEOUT_MS` if your gateway is slower.
- **Wrong model used:** Set `POLISH_MODEL` to an alias your gateway exposes.
- **Windows:** Auto-wiring is not implemented. Install the skill files
  normally, then manually add the hook from `hook.json` to
  `%USERPROFILE%\.claude\settings.json`.
