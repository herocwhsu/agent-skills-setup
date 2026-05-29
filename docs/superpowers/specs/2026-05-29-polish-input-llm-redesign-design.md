# polish-input LLM redesign

**Date:** 2026-05-29
**Status:** Approved (pending implementation)
**Owner:** <user>

## Problem

The current `polish-input` skill uses LanguageTool, which only handles
mechanical fixes (capitalization, punctuation, simple agreement). It cannot
restructure non-native phrasing. Real samples from `~/.claude/state/polish-input/debug.log`:

- `i want add new feature for login` — LT cannot insert "to" or "a"
- `Ok, let surf` — LT does not flag the missing "'s"
- `It's office skill in Claude code` — LT cannot fix "office" → "official"

For an English-learning side channel, this is a near-zero-value tool. The
prompts that need polish most are exactly the ones LT cannot handle.

## Goal

Replace the LanguageTool engine with an LLM call (Claude Haiku 4.5) so the
skill produces real native-sounding rewrites. Keep all surrounding plumbing —
hook protocol, skip rules, display formats, fail-open behavior — unchanged.

## Non-goals

- Changing the hook trigger model (still `UserPromptSubmit`, single-line only).
- Adding teaching features (change explanations, before/after diff narratives).
- Supporting multi-line prompts.
- Local-LLM support.

## Approach

Pure LLM rewrite. Drop LanguageTool entirely. Each non-skipped prompt goes to
Haiku 4.5 with a tight, cacheable system prompt instructing it to return the
rewritten text only.

Why this over the alternatives:

- **Hybrid LT + LLM** was rejected because the heuristics for "needs LLM"
  are unreliable, and the prompts that most need real polish are the ones LT
  most often passes through unchanged. The cost savings are small relative
  to the complexity.
- **Local LLM (Ollama)** was rejected for latency and quality variance. Can
  be revisited if the user later wants offline support.
- **Structured JSON output** was rejected as over-engineering for v1. The
  current `line` / `diff` / `box` formats already give the user choice.

## Architecture

```
stdin (UserPromptSubmit hook JSON)
  → polish.py
    → _parse_hook_payload  (unchanged)
    → _skip_reason         (unchanged: slash, multi-line, MAX_LEN, POLISH_DISABLE)
    → polish_engine.polish(text)         ← NEW
        → anthropic.Anthropic().messages.create(model=POLISH_MODEL, ...)
        → returns rewritten text or None on failure
    → format (line/diff/box) (unchanged)
    → systemMessage stdout + optional additionalContext (unchanged)
```

### File layout

```
skills/polish-input/
├── SKILL.md                  (updated description: removes LT mention)
├── README.md                 (rewritten: install, config, model)
├── hook.json                 (unchanged)
├── lib/
│   ├── polish.py             (engine import swapped, no LT references)
│   └── polish_engine.py      ← NEW: SDK wrapper
└── tests/
    ├── test_polish.py        (mocks polish_engine.polish, no LT mocks)
    └── integration_polish.sh (opt-in real-API test)
```

### What stays the same

- `_parse_hook_payload`, `_run_hook_protocol`, `_run_legacy_text` — all
  unchanged. The hook protocol contract with Claude Code does not change.
- All skip rules (`POLISH_DISABLE`, slash commands, multi-line, `MAX_LEN`).
- All three display formats (`line`, `diff`, `box`).
- `POLISH_REPLACE` semantics: when set, polished text is injected as
  `additionalContext`.
- `POLISH_DEBUG` debug-log behavior and one-shot error-hint pattern (the
  `.lt-error` marker becomes `.engine-error`).
- Fail-open guarantee: any engine failure passes the original prompt through
  untouched.

### What changes

| Area | Before | After |
|---|---|---|
| Engine | `language_tool_python.LanguageTool("en-US").correct(text)` | Anthropic SDK call to Haiku 4.5 |
| Dependencies | Java JRE + `language_tool_python` (~200MB JAR) | `anthropic` Python SDK |
| First-run | Downloads LT JAR, prints "initializing LanguageTool..." | No init step. First call uses cached system prompt. |
| Latency | ~50ms after warmup | ~500ms (network round-trip to gateway) |
| Cost | $0 | ~$0.0001/prompt with prompt caching |
| Quality | Mechanical only | Native phrasing rewrites |

## The LLM call

```python
# lib/polish_engine.py
import os
from typing import Optional

SYSTEM_PROMPT = (
    "Rewrite the user's message as natural, native-sounding English. "
    "Preserve technical terms, code, file paths, URLs, command-line flags, "
    "and the original meaning exactly. Do not answer the message. Do not add "
    "commentary. Output only the rewritten text. If the input is already "
    "fluent, return it unchanged."
)

def polish(text: str) -> Optional[str]:
    """Return rewritten text, or None on any failure (fail open)."""
    try:
        import anthropic
    except ImportError:
        _write_engine_error_hint_once("anthropic SDK not installed")
        return None

    try:
        client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY + ANTHROPIC_BASE_URL
        timeout_s = int(os.environ.get("POLISH_TIMEOUT_MS", "3000")) / 1000
        resp = client.messages.create(
            model=os.environ.get("POLISH_MODEL", "claude-haiku-4-5"),
            max_tokens=1500,
            timeout=timeout_s,
            system=[{
                "type": "text",
                "text": SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{"role": "user", "content": text}],
        )
        return resp.content[0].text.strip()
    except Exception as e:
        _write_engine_error_hint_once(f"Anthropic API call failed: {e}")
        return None
```

Design notes:

- `anthropic.Anthropic()` reads `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL`
  from the environment. In Kiro mode these are already set to point at the
  Kiro gateway, so the polish hook routes through the same gateway as the
  parent Claude Code session. **No second API key needed.**
- `cache_control: ephemeral` on the system prompt drops cost ~90% on
  subsequent calls within the 5-minute cache window.
- 3-second timeout: anything beyond that and the user is typing again.
- `max_tokens=1500`: covers `MAX_LEN=4000` chars worst case (~1000 tokens)
  with headroom.

## Configuration

| Var | Default | Effect | New? |
|---|---|---|---|
| `POLISH_DISABLE` | unset | `1` = no-op | no |
| `POLISH_REPLACE` | unset | `1` = inject polished into context | no |
| `POLISH_DISPLAY` | `line` | `line` / `diff` / `box` | no |
| `POLISH_DEBUG` | unset | `1` = log to debug.log | no |
| `POLISH_MODEL` | `claude-haiku-4-5` | Override the polish model | **yes** |
| `POLISH_TIMEOUT_MS` | `3000` | API timeout in milliseconds | **yes** |

`POLISH_TEST_FAKE_LT` is renamed to `POLISH_TEST_FAKE_RESPONSE` (same JSON
mapping semantics). `POLISH_TEST_NO_LT` is renamed to `POLISH_TEST_NO_ENGINE`.

## Install / uninstall

`scripts/install.sh --with-hook polish-input` changes:

- **Remove** Java check + brew/apt offer
- **Remove** `pip install --user language_tool_python`
- **Add** `pip install --user anthropic`
- Hook merge into `~/.claude/settings.json` is unchanged

`scripts/uninstall.sh --with-hook polish-input`: removes the hook entry and
unlinks. The `anthropic` package is left in place (likely used by other
skills); user can remove manually.

## Migration for existing users

- Existing `~/.claude/state/polish-input/.initialized` (LT JAR-download
  marker) is now meaningless. Leave the file in place; ignore it.
- Existing `~/.claude/state/polish-input/.lt-error` is left in place
  (harmless). New errors are written to a new `.engine-error` marker, so the
  one-shot hint pattern still works after upgrade.
- If the user upgrades and forgets to install `anthropic`, the hook fails
  open and writes a one-shot hint to `debug.log` (same pattern as today's
  LT-missing hint).
- Java and `language_tool_python` are not removed automatically. The README
  notes that they can be removed manually.

## Error handling

Fail-open is preserved end-to-end:

| Failure | Behavior |
|---|---|
| `anthropic` not installed | Log hint once, pass original prompt through |
| `ANTHROPIC_API_KEY` not set | SDK raises; caught, logged, original passed through |
| API timeout | Caught, logged, original passed through |
| API error (rate limit, 5xx) | Caught, logged, original passed through |
| Model returns empty / identical text | `corrected == text` check, no display |

The user never sees a broken hook. Worst case they see no `[polish]` line.

## Testing

### Unit tests (`tests/test_polish.py`)

- Mock `polish_engine.polish` with a function returning canned strings.
- Cover: skip rules (slash, multi-line, MAX_LEN, POLISH_DISABLE), display
  formats (line, diff, box), POLISH_REPLACE on/off, hook-protocol JSON
  parsing, legacy raw-text mode, engine-failure fail-open path,
  no-change suppression.
- Drop LanguageTool-specific tests.

### Integration test (`tests/integration_polish.sh`)

- Opt-in via `RUN_INTEGRATION=1` env var so CI does not burn tokens.
- Sends three known-bad prompts through the real API, asserts each output
  differs from input and contains expected words.

### Manual verification

- Send a known-bad prompt via the hook, confirm `[polish]` line shows on
  stderr with a real rewrite.
- Set `POLISH_DISABLE=1`, confirm no polish line.
- Set `POLISH_DEBUG=1`, confirm log entries.
- Unset `ANTHROPIC_API_KEY`, confirm hook fails open with a hint.

## Rollout

This is a private user skill, no staged rollout needed. Single PR:

1. Add `lib/polish_engine.py`
2. Update `lib/polish.py` to call the new engine
3. Update tests
4. Update `README.md` and `SKILL.md` description
5. Update `scripts/install.sh` and `scripts/uninstall.sh`
6. Smoke-test locally with a few real prompts

## Open questions

None. All decisions captured above.
