# Local STT Dictation (SuperWhisper Replacement) — Design

**Date:** 2026-07-02
**Status:** Approved
**Context:** SuperWhisper's free tier now blocks usage. Claude Code's built-in voice was
tried and reverted (commits 6ff88da → 5821448). We replace SuperWhisper with a local,
open-source, cross-platform dictation tool with built-in transcript polish for a
non-native English speaker.

## Requirements

- **Platforms:** macOS desktop and the Linux host (i7-920, 8 threads, no GPU, 15 GB RAM).
  Text must land system-wide (any app), not only in Claude Code.
- **Languages:** EN speech → polished English text; ZH (Taiwan) speech → Traditional
  Chinese text. No translation between them. The current language mode is set
  explicitly (no auto-detect in v1).
- **Polish:** happens inside the dictation pipeline (transcript is cleaned before being
  pasted), replacing the informational-only `polish-input` hook for voice input.
- **Activation:** toggle mode — tap a global hotkey to start recording, tap again to stop.
- **No subscriptions:** local STT models; the only network call is the LLM polish step,
  using existing Anthropic/kiro-gateway access.

## Decision

Adopt **[Handy](https://github.com/cjpais/handy)** (MIT, Rust + Tauri, ~20k stars,
actively maintained) instead of building from scratch. Handy already provides:
cross-platform macOS/Linux support, fully local Whisper/Parakeet/Moonshine models,
toggle mode, Chinese language support, and LLM post-processing with multiple named
prompts each bound to its own hotkey.

Alternatives rejected:
- **Own Rust daemon** (whisper-rs + cpal + global-hotkey + enigo): full control but weeks
  of re-solving problems Handy has solved (model management, Wayland/X11 and macOS
  input-injection quirks, permissions).
- **whisper.cpp + per-OS glue scripts:** fastest prototype, worst maintainability,
  duplicated per-OS work.

## Phase 1 — Adopt and configure (no code)

1. Install Handy: macOS build on the Mac; AppImage/deb on the Linux host.
2. Set **toggle mode** with a global hotkey on both machines.
3. Models: Whisper small/medium on the Mac (Apple Silicon). On the Linux host, benchmark
   Whisper base/small (quantized); pick the largest model that transcribes a typical
   sentence in ~2–3 s. The i7-920 lacks AVX, so expectations are modest.
4. Two named post-process prompts, each with its own hotkey (this is the v1 mode switch):
   - **EN polish:** "Fix this transcript into natural, correct English. Remove filler
     words. Keep the meaning. Output only the corrected text."
   - **ZH-TW:** 「將逐字稿轉為台灣正體中文，修正標點並移除贅字，只輸出結果。」
     (the LLM handles Simplified→Traditional in v1)
5. Polish endpoint: OpenAI-compatible endpoint with `claude-haiku-4-5`
   (Anthropic's compatibility endpoint or the kiro-gateway, as `polish-input` uses).
6. Deliverables in this repo: setup/config doc under `docs/`, install steps following
   the `setup-host.sh` pattern, prompt texts checked in.

## Phase 2 — Rust fork for the gaps

Fork `cjpais/Handy` on GitHub under the user's account; clone to `~/projects/handy`.
Two well-bounded features, built as upstream PR candidates:

1. **OpenCC conversion step** (`ferrous-opencc` or `opencc-rust`, `s2twp` profile)
   applied to ZH transcripts after STT — deterministic Traditional Chinese output that
   works offline, instead of relying on the LLM prompt.
2. **Language-mode hotkey:** one shortcut cycles EN ⇄ ZH-TW, switching the Whisper
   language parameter and the active post-process prompt together; current mode shown
   in the tray icon.

If upstream rejects the PRs, maintain the fork and use its CI for release builds.

## Error handling

- LLM polish unreachable or slow → paste the raw transcript (fail open; never lose a
  dictation).
- Linux host too slow for the chosen model → drop to a smaller model.
- Handy is a standalone app; killing it affects nothing else.

## Testing

- **Phase 1 (manual acceptance checklist):** EN dictation into terminal, browser, and
  editor on both OSes; ZH-TW output verified to be Traditional characters; end-to-end
  latency measured on both machines; LLM-down fallback verified (raw transcript pasted).
- **Phase 2:** Rust unit tests for the OpenCC conversion and mode-switch state; same
  manual E2E checklist on both OSes.

## Out of scope (YAGNI)

- Auto language detection; translation modes; Windows support.
- Upgrading the `polish-input` hook — dictation polish replaces it for voice; the hook
  stays as-is for typed input.

## Open items to verify during implementation

- Which local model handles ZH best on the weak Linux CPU (Whisper base/small vs
  Moonshine's Chinese support).
- Whether Handy's post-process step supports a custom base URL pointing at
  Anthropic's OpenAI-compatible endpoint or the kiro-gateway (docs say "any
  OpenAI-compatible LLM").
