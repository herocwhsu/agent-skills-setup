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
   active prompt, or use the fork build's `Ctrl+Shift+L` / `⌥⇧L` mode hotkey
   to flip both at once (see "Fork build (Phase 2)" below).
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

**Fork build additions (once installed on macOS):**
- [ ] Mode hotkey (`⌥⇧L`) flips language + active prompt + tray label
- [ ] ZH dictation of 「我要登录系统」 pastes 「我要登入系統」 (S2twp phrase conversion)

## Fork build (Phase 2)

`~/projects/handy` (fork: `herocwhsu/Handy`, upstream: `cjpais/Handy`) adds
two features on top of stock Handy, merged into the `talkout` integration
branch:

- **S2twp Chinese conversion** — `zh-Hant` output now uses OpenCC's
  phrase-aware `S2twp` profile instead of the stock character-only `S2tw`,
  so dictation gets Taiwan phrasing (登入) not mainland phrasing (登錄).
- **`cycle_language_mode` hotkey** — `Ctrl+Shift+L` (Linux/Windows) /
  `⌥⇧L` (macOS) cycles the transcription language EN ⇄ Chinese
  (Traditional), auto-selects the matching post-process prompt by name
  (`EN polish` / `ZH-TW`), and shows the active mode in the tray menu.

Verified via `cargo check` + `cargo test --no-run` on the dev box (Linux);
this Linux host cannot execute the built binary at all — a pre-existing,
unrelated native-library crash (protobuf global constructor, SIGILL) blocks
running *any* test or build output here, on code predating this fork too.
Runtime behavior (including the two items above) needs verification on
macOS once installed there.

## Known limitations (v1)

- Stock (non-fork) Handy still requires switching language + prompt by hand;
  use the fork build above for the single-hotkey mode switch.
