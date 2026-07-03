# Handy Dictation Setup (SuperWhisper replacement)

Local speech-to-text on macOS desktop. Spec:
`docs/superpowers/specs/2026-07-02-local-stt-dictation-design.md`

> **Linux host:** decided (2026-07-03) not to run Handy here — the `handy`
> 0.9.0 deb was installed but never launched/configured, and has been
> removed (`sudo apt remove handy`). Dictation is macOS-only for now. The
> `~/projects/handy` fork still lives on this host as the dev environment
> for the Phase 2 OpenCC/hotkey work (see backlog); that work targets the
> macOS build.

## Install

**macOS desktop:** download the dmg matching your Mac from
https://github.com/cjpais/Handy/releases/tag/v0.9.0 — `Handy_0.9.0_aarch64.dmg`
(Apple Silicon) or `Handy_0.9.0_x64.dmg` (Intel) — open, drag to Applications.
Grant Microphone + Accessibility permissions when prompted
(System Settings → Privacy & Security).

## Configure (GUI labels approximate)

1. Settings → recording mode: **toggle** (tap to start, tap to stop).
   Hotkey: `⌥+Space` — adjust to taste.
2. Settings → Model: **Whisper Small** (upgrade to Medium if latency is fine).
3. Settings → Language: **English** or **Chinese (Traditional)** to match the
   active prompt (v1 has no single-hotkey mode switch; that's Phase 2).
   Picking Chinese (Traditional) (`zh-Hant`) activates Handy's built-in OpenCC
   conversion, so ZH output is Traditional even offline / without the LLM —
   the ZH-TW prompt is then optional cleanup (punctuation, filler words).
4. Settings → Post-Processing — base URL `https://api.anthropic.com/v1`,
   model `claude-haiku-4-5`, API key = `ANTHROPIC_API_KEY` (verified by
   `scripts/test-polish-endpoint.sh`).

   Two named prompts, each with its own hotkey:
   - **EN polish** — paste `config/handy/prompt-en-polish.txt`
   - **ZH-TW** — paste `config/handy/prompt-zh-tw.txt`

## Benchmarks (fill in during setup)

| Machine | Model | ~10s sentence → text | Verdict |
|---|---|---|---|
| macOS | Whisper Small | _measure_ | _keep/drop_ |
| macOS | Whisper Medium | _measure_ | _keep/drop_ |

## Acceptance checklist

- [ ] EN dictation lands polished English in: terminal, browser, editor
- [ ] ZH dictation lands **Traditional** Chinese (說/會/讓, not 说/会/让)
- [ ] Toggle hotkey starts/stops reliably; tray shows recording state
- [ ] LLM-down fallback: disconnect network mid-test (or set a bad API key),
      dictate — raw transcript is pasted, nothing is lost
- [ ] End-to-end latency acceptable (target ≤ ~5s for a short sentence)

## Known limitations (v1)

- Language + prompt must be switched together by hand (Phase 2 adds one hotkey).
- Handy's built-in OpenCC uses the character-level `S2tw` profile: Traditional
  characters are always correct, but non-Taiwan phrasing can remain
  (e.g. 登錄 instead of 登入). Phase 2 switches to the `S2twp` profile,
  which also converts Taiwan phrase usage.
