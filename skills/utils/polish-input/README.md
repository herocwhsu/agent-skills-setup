# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code, Kiro, and Antigravity CLI (`agy`).
Uses Claude Haiku 4.5 via the Anthropic SDK, or Gemini session OAuth credentials.

## What it does

```
you> i want add new feature for login
[polish] I want to add a new feature for login.
agent> Sure — let's start by looking at the auth code…
```

The agent receives the original prompt by default. The polish line is purely informational.

## Install

Wired automatically by `bash scripts/install.sh` — no separate flag needed.
Use `POLISH_DISABLE=1` (see below) to turn it off without uninstalling.

Installing it does this:
1. Installs the skill files (symlinks `skills/polish-input/` → `~/.<agent>/skills/polish-input/`).
2. Installs the `anthropic` Python SDK via pip.
3. Merges the `UserPromptSubmit` hook into the selected agent's settings (e.g. `~/.gemini/antigravity-cli/settings.json`).

The hook resolves OAuth session tokens automatically from macOS Keychain (`security`), Linux Secret Service (`secret-tool`), or fallback session files, and also reads `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` if present in the environment.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to the agent instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.agent-skills-setup/state/polish-input/debug.log`. |
| `POLISH_MODEL` | `claude-haiku-4-5` | Override the polish model. |
| `POLISH_TIMEOUT_MS` | `3000` | API timeout in milliseconds. |

Set them in your agent's settings file (e.g. `~/.gemini/settings.json`) under `env`, or in your shell rc.

## Skip rules

The hook is silent when:
- The prompt starts with `/` (slash command).
- The prompt contains a newline (multi-line).
- The prompt is over 4000 characters.
- `POLISH_DISABLE=1` is set.
- The polish engine is unavailable (fail open).

## Uninstall

`bash scripts/uninstall.sh` removes the hook entry and unlinks the skill
along with everything else. The `anthropic` package is left in place;
remove manually with `pip uninstall anthropic` if desired.

## Troubleshooting

- **No polish appears:** Check `~/.agent-skills-setup/state/polish-input/debug.log`.
  Common causes: `anthropic` not installed, or `ANTHROPIC_API_KEY` not set in
  the environment the agent runs in.
- **Polish is slow (>3s):** The hook times out at 3s by default. Bump
  `POLISH_TIMEOUT_MS` if your gateway is slower.
- **Wrong model used:** Set `POLISH_MODEL` to an alias your gateway exposes.
