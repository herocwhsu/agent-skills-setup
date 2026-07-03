# Handy Dictation Setup (SuperWhisper replacement)

Local speech-to-text on Linux host + macOS desktop. Spec:
`docs/superpowers/specs/2026-07-02-local-stt-dictation-design.md`

## Install

**Linux host (this repo's machine):**

```bash
gh release download v0.9.0 -R cjpais/Handy -p 'Handy_0.9.0_amd64.deb' -D /tmp/claude-handy
sudo apt install /tmp/claude-handy/Handy_0.9.0_amd64.deb
```

**macOS desktop:** download the dmg matching your Mac from
https://github.com/cjpais/Handy/releases/tag/v0.9.0 — `Handy_0.9.0_aarch64.dmg`
(Apple Silicon) or `Handy_0.9.0_x64.dmg` (Intel) — open, drag to Applications.
Grant Microphone + Accessibility permissions when prompted
(System Settings → Privacy & Security).

## Configure (both machines — GUI labels approximate)

1. Settings → recording mode: **toggle** (tap to start, tap to stop).
   Hotkey: `Ctrl+Alt+Space` (Linux) / `⌥+Space` (macOS) — adjust to taste.
2. Settings → Model:
   - macOS: **Whisper Small** (upgrade to Medium if latency is fine).
   - Linux: **Whisper Base** first (i7-920, no AVX, no GPU); try Small only
     if Base feels fast enough. Record results in Benchmarks below.
3. Settings → Language: **English** or **Chinese (Traditional)** to match the
   active prompt (v1 has no single-hotkey mode switch; that's Phase 2).
   Picking Chinese (Traditional) (`zh-Hant`) activates Handy's built-in OpenCC
   conversion, so ZH output is Traditional even offline / without the LLM —
   the ZH-TW prompt is then optional cleanup (punctuation, filler words).
4. Settings → Post-Processing — endpoint per machine (both verified by
   `scripts/test-polish-endpoint.sh`):
   - **Linux:** base URL `https://openrouter.ai/api/v1`, model
     `anthropic/claude-haiku-4.5`, API key = `OPENROUTER_API_KEY` from Vault
     (`vault kv get -field=OPENROUTER_API_KEY secret/firstdigital/config`).
   - **macOS:** base URL `https://api.anthropic.com/v1`, model
     `claude-haiku-4-5`, API key = `ANTHROPIC_API_KEY`.

   Two named prompts, each with its own hotkey:
   - **EN polish** — paste `config/handy/prompt-en-polish.txt`
   - **ZH-TW** — paste `config/handy/prompt-zh-tw.txt`

## Benchmarks (fill in during setup)

| Machine | Model | ~10s sentence → text | Verdict |
|---|---|---|---|
| Linux i7-920 | Whisper Base | _measure_ | _keep/drop_ |
| Linux i7-920 | Whisper Small | _measure_ | _keep/drop_ |
| macOS | Whisper Small | _measure_ | _keep/drop_ |
| macOS | Whisper Medium | _measure_ | _keep/drop_ |

## Acceptance checklist (run on BOTH machines)

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
