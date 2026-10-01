# polish-input

Auto-polish single-line English prompts as a learning side-channel for Claude Code, Codex CLI, and Antigravity CLI (`agy`). Kiro has no hook mechanism, so it is skipped.
Uses Claude Haiku 4.5 via the Anthropic SDK, or Gemini via the `google-genai` SDK with an API key.

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
2. Installs the Python SDK via pip: `anthropic`, or `google-genai` for Antigravity.
3. Merges the hook into the selected agent's hook file:
   - Claude Code: `~/.claude/settings.json` (`UserPromptSubmit`)
   - Codex CLI: `~/.codex/hooks.json`, or `$CODEX_HOME/hooks.json`
   - Antigravity CLI: `~/.gemini/config/hooks.json` (`PreInvocation`)

Antigravity also gets a prompt polish rule in `~/.gemini/GEMINI.md` (from `agents/antigravity-rules.md`), so the model itself prints the `[polish]` line. No other agent gets that rule.

The hook resolves Claude session tokens and stored API keys automatically from macOS Keychain (`security`), Linux Secret Service (`secret-tool`), or fallback session files, and also reads `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` if present in the environment. Gemini needs an API key: `google-genai` does not accept the Antigravity OAuth session for the Gemini API.

## Configuration

All env vars are optional.

| Var | Default | Effect |
|---|---|---|
| `POLISH_DISABLE` | unset | If `1`, hook is a no-op. Instant escape hatch. |
| `POLISH_REPLACE` | unset | If `1`, send the polished text to the agent instead of the original. |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box`. |
| `POLISH_DEBUG` | unset | If `1`, log diagnostics to `~/.agent-skills-setup/state/polish-input/debug.log`. |
| `POLISH_MODEL` | `claude-haiku-4-5` (Gemini: `gemini-3.5-flash-lite`) | Override the polish model. |
| `POLISH_TIMEOUT_MS` | `3000` | API timeout in milliseconds. |

Set them in your shell rc, or for Claude Code under `env` in `~/.claude/settings.json`.

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
