# Handy Fork Phase 2 (S2twp + Language-Mode Hotkey) Implementation Plan

**Status: closed 2026-07-08 (see `docs/backlog.md`).** Both code items landed in the fork. The remaining unchecked boxes were skipped or deferred by explicit decision (full integration-branch build, upstream draft PRs) — they are not outstanding work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the Handy fork (`~/projects/handy`, origin = herocwhsu/Handy, upstream = cjpais/Handy), make ZH output use Taiwan phrase conventions (OpenCC `S2twp`) and add one global hotkey that cycles the dictation mode EN ⇄ ZH-TW (switching STT language and the active post-process prompt together, with the mode visible in the tray menu).

**Architecture:** Two small features on separate branches cut from `upstream/main` so each can become an upstream PR; an integration branch `talkout` merges both for daily use. Feature 1 is a profile switch inside the existing `maybe_convert_chinese_variant` (actions.rs). Feature 2 adds a `cycle_language_mode` entry to the default bindings map (settings.rs) — the existing merge-on-load logic auto-adds it to existing installs — plus a `CycleLanguageModeAction` in `ACTION_MAP` (actions.rs) and a mode label in the tray menu (tray.rs).

**Tech Stack:** Rust (Tauri 2), `ferrous-opencc` 0.2.3 (`BuiltinConfig::S2twp` verified present), inline `#[cfg(test)]` test modules (existing repo style), bun + cargo build.

**Spec:** `agent-skills-setup/docs/superpowers/specs/2026-07-02-local-stt-dictation-design.md` (Phase 2 section, narrowed: Handy already converts to Traditional for `zh-Hant` via `S2tw`; only the phrase-level profile and the mode hotkey are missing).

**Verified codebase facts (2026-07-03, upstream/main):**
- `src-tauri/src/actions.rs:315` `maybe_convert_chinese_variant` picks `BuiltinConfig::S2tw` (line ~343) for `zh-Hant`, `Tw2sp` for `zh-Hans`.
- `src-tauri/src/actions.rs:852` `ACTION_MAP: Lazy<HashMap<String, Arc<dyn ShortcutAction>>>`; trait `ShortcutAction` (line 44) has `start`/`stop`.
- `src-tauri/src/shortcut/handler.rs` dispatches non-transcribe bindings to `ACTION_MAP` on press/release; `"cancel"` is special-cased.
- `src-tauri/src/settings.rs:749` `get_default_settings()` inserts bindings `transcribe`, `transcribe_with_post_process`, `cancel`; `load_or_create_app_settings` (line ~883) merges missing default bindings into existing stores.
- `AppSettings` fields: `selected_language: String` (line 366), `post_process_prompts: Vec<LLMPrompt>` (line 402), `post_process_selected_prompt_id: Option<String>` (line 404). `LLMPrompt` struct at line 90 (has `id` and `name` fields — implementer: confirm exact field names at line 90 before use).
- `src-tauri/src/tray.rs:96` `update_tray_menu` builds the menu; version shown via disabled `version` MenuItem using `version_label()` (line 88); tray handle from `app.state::<TrayIcon>()`.
- Language values used by the frontend: `"en"`, `"zh-Hant"` (src/lib/constants/languages.ts).
- Test style: inline `#[cfg(test)] mod tests` (e.g. actions.rs:875).

---

### Task 1: Branch setup

**Files:** none (git only)

- [x] **Step 1: Sync and create branches**

```bash
cd ~/projects/handy
git fetch upstream
git checkout -b feat/s2twp upstream/main
```

Expected: branch `feat/s2twp` at upstream/main tip.

---

### Task 2: Switch zh-Hant conversion to S2twp (branch `feat/s2twp`)

**Files:**
- Modify: `src-tauri/src/actions.rs` (function `maybe_convert_chinese_variant`, ~line 315, and its test module)

- [x] **Step 1: Extract config selection into a pure helper + write failing tests**

In `actions.rs`, above `maybe_convert_chinese_variant`, add:

```rust
/// OpenCC config for the effective transcription language, if conversion applies.
fn chinese_conversion_config(effective_language: &str) -> Option<BuiltinConfig> {
    match effective_language {
        // Traditional→Simplified with Taiwan phrase handling (unchanged).
        "zh-Hans" => Some(BuiltinConfig::Tw2sp),
        // Simplified→Traditional including Taiwan phrase usage (S2twp, not S2tw):
        // e.g. 软件→軟體, 登录→登入 — matches what a zh-TW user expects to type.
        "zh-Hant" => Some(BuiltinConfig::S2twp),
        _ => None,
    }
}
```

In the existing `#[cfg(test)] mod tests` block of `actions.rs`, add:

```rust
    use super::chinese_conversion_config;
    use ferrous_opencc::{config::BuiltinConfig, OpenCC};

    #[test]
    fn zh_hant_uses_taiwan_phrase_profile() {
        assert_eq!(
            chinese_conversion_config("zh-Hant"),
            Some(BuiltinConfig::S2twp)
        );
        assert_eq!(
            chinese_conversion_config("zh-Hans"),
            Some(BuiltinConfig::Tw2sp)
        );
        assert_eq!(chinese_conversion_config("en"), None);
        assert_eq!(chinese_conversion_config("ja"), None);
    }

    #[test]
    fn s2twp_converts_taiwan_phrases() {
        let converter = OpenCC::from_config(BuiltinConfig::S2twp).unwrap();
        assert_eq!(converter.convert("登录"), "登入");
        assert_eq!(converter.convert("软件"), "軟體");
    }
```

Note: `BuiltinConfig` needs `#[derive(PartialEq, Debug)]` support for `assert_eq!`; if the crate's enum lacks them, compare with `matches!` instead:
`assert!(matches!(chinese_conversion_config("zh-Hant"), Some(BuiltinConfig::S2twp)));`

- [x] **Step 2: Run tests — expect the helper test to fail to compile (helper not yet used / not present)**

```bash
cd ~/projects/handy/src-tauri && cargo test chinese_conversion -- --nocapture
```

Expected: FAIL (compile error before helper added; after adding helper, tests pass — the "red" here is the compile gate).

- [x] **Step 3: Rewire `maybe_convert_chinese_variant` to use the helper**

Replace the body section that computes `is_simplified` / `is_traditional` / `config` (lines ~324-344) with:

```rust
    let Some(config) = chinese_conversion_config(effective_language) else {
        debug!("effective language is not Simplified or Traditional Chinese; skipping conversion");
        return None;
    };

    debug!(
        "Starting Chinese variant conversion using OpenCC for language: {}",
        effective_language
    );
```

(keep the existing `match OpenCC::from_config(config)` block below unchanged; preserve the existing comment block about gating on effective language).

- [x] **Step 4: Run tests + full check**

```bash
cd ~/projects/handy/src-tauri && cargo test && cargo check
```

Expected: all tests pass, no warnings introduced.

- [x] **Step 5: Commit**

```bash
cd ~/projects/handy
git add src-tauri/src/actions.rs
git commit -m "feat: use S2twp profile for zh-Hant conversion (Taiwan phrase usage)"
```

---

### Task 3: Language-mode cycle hotkey (branch `feat/language-mode-hotkey`)

**Files:**
- Modify: `src-tauri/src/settings.rs` (`get_default_settings`, ~line 759)
- Modify: `src-tauri/src/actions.rs` (new action + `ACTION_MAP` entry + tests)
- Modify: `src-tauri/src/tray.rs` (mode label in tray menu)

- [x] **Step 1: Create the branch from upstream/main**

```bash
cd ~/projects/handy
git checkout -b feat/language-mode-hotkey upstream/main
```

- [x] **Step 2: Add the default binding in `settings.rs`**

In `get_default_settings()` after the `"cancel"` binding insert (line ~799):

```rust
    #[cfg(target_os = "macos")]
    let default_cycle_language_shortcut = "option+shift+l";
    #[cfg(not(target_os = "macos"))]
    let default_cycle_language_shortcut = "ctrl+shift+l";

    bindings.insert(
        "cycle_language_mode".to_string(),
        ShortcutBinding {
            id: "cycle_language_mode".to_string(),
            name: "Cycle Language Mode".to_string(),
            description: "Switches transcription language between English and Chinese (Traditional), and selects the matching post-processing prompt when one is named accordingly.".to_string(),
            default_binding: default_cycle_language_shortcut.to_string(),
            current_binding: default_cycle_language_shortcut.to_string(),
        },
    );
```

No migration needed: `load_or_create_app_settings` already merges missing default bindings into existing stores (settings.rs ~line 897).

- [x] **Step 3: Write the pure helpers + failing tests in `actions.rs`**

Add near the other free functions:

```rust
/// Languages the cycle_language_mode shortcut rotates through.
const LANGUAGE_MODE_CYCLE: [&str; 2] = ["en", "zh-Hant"];

/// Post-process prompt names auto-selected per language mode. A prompt is
/// only switched when one with the matching name exists; otherwise the
/// current selection is left untouched.
fn prompt_name_for_language(language: &str) -> Option<&'static str> {
    match language {
        "en" => Some("EN polish"),
        "zh-Hant" => Some("ZH-TW"),
        _ => None,
    }
}

fn next_language_mode(current: &str) -> &'static str {
    match LANGUAGE_MODE_CYCLE.iter().position(|l| *l == current) {
        Some(i) => LANGUAGE_MODE_CYCLE[(i + 1) % LANGUAGE_MODE_CYCLE.len()],
        // Any other language (auto, ja, …) enters the cycle at English.
        None => LANGUAGE_MODE_CYCLE[0],
    }
}
```

Tests (same `mod tests`):

```rust
    use super::{next_language_mode, prompt_name_for_language};

    #[test]
    fn language_mode_cycles_en_zh_hant() {
        assert_eq!(next_language_mode("en"), "zh-Hant");
        assert_eq!(next_language_mode("zh-Hant"), "en");
        assert_eq!(next_language_mode("auto"), "en");
        assert_eq!(next_language_mode(""), "en");
    }

    #[test]
    fn prompt_names_map_to_language_modes() {
        assert_eq!(prompt_name_for_language("en"), Some("EN polish"));
        assert_eq!(prompt_name_for_language("zh-Hant"), Some("ZH-TW"));
        assert_eq!(prompt_name_for_language("ja"), None);
    }
```

Run: `cargo test language_mode` → expect compile failure first (red), then pass once helpers exist.

- [x] **Step 4: Add the action and register it**

In `actions.rs` next to `CancelAction`:

```rust
// Cycle Language Mode Action
struct CycleLanguageModeAction;

impl ShortcutAction for CycleLanguageModeAction {
    fn start(&self, app: &AppHandle, _binding_id: &str, _shortcut_str: &str) {
        let mut settings = crate::settings::get_settings(app);
        let new_language = next_language_mode(&settings.selected_language).to_string();

        if let Some(prompt_name) = prompt_name_for_language(&new_language) {
            if let Some(prompt) = settings
                .post_process_prompts
                .iter()
                .find(|p| p.name == prompt_name)
            {
                settings.post_process_selected_prompt_id = Some(prompt.id.clone());
            }
        }

        log::info!(
            "cycle_language_mode: {} -> {}",
            settings.selected_language, new_language
        );
        settings.selected_language = new_language;
        crate::settings::write_settings(app, settings);

        // Refresh tray so the new mode label shows immediately.
        crate::tray::update_tray_menu(app, &crate::tray::TrayIconState::Idle, None);
    }

    fn stop(&self, _app: &AppHandle, _binding_id: &str, _shortcut_str: &str) {
        // Nothing to do on release.
    }
}
```

(Implementer: match the exact import style / paths already used in actions.rs — it already imports settings and tray items; check `LLMPrompt` field names at settings.rs:90 and the exact signature of `write_settings` before wiring.)

In `ACTION_MAP` (line ~852) add:

```rust
    map.insert(
        "cycle_language_mode".to_string(),
        Arc::new(CycleLanguageModeAction) as Arc<dyn ShortcutAction>,
    );
```

Caveat to verify while wiring: `update_tray_menu` takes the current `TrayIconState`; passing `Idle` from the action is correct only when idle — check whether a current-state accessor exists (grep `TrayIconState::` callers) and use it if available; otherwise `Idle` is acceptable since the shortcut is meant to be used between dictations.

- [x] **Step 5: Show the mode in the tray menu (`tray.rs`)**

In `update_tray_menu` (line ~96), change the version item to include the mode:

```rust
    let mode_label = match settings.selected_language.as_str() {
        "zh-Hant" => "ZH-TW",
        "en" => "EN",
        other => other,
    };
    let version_label = format!("{} — {}", version_label(), mode_label);
```

(replacing the existing `let version_label = version_label();`)

- [x] **Step 6: Test, build, run manually**

```bash
cd ~/projects/handy/src-tauri && cargo test && cargo build
```

Expected: tests pass, build succeeds.

Manual check (needs desktop session): `bun run tauri dev`, press `Ctrl+Shift+L` → tray menu's first line flips `… — EN` ⇄ `… — ZH-TW`; Settings UI shows the new "Cycle Language Mode" shortcut in the bindings list (the UI renders the bindings map generically — verify, and report if it does not).

- [x] **Step 7: Commit**

```bash
cd ~/projects/handy
git add src-tauri/src/settings.rs src-tauri/src/actions.rs src-tauri/src/tray.rs
git commit -m "feat: add cycle_language_mode shortcut (EN <-> zh-Hant, prompt + tray label)"
```

---

### Task 4: Integration branch and daily-use build

**Files:** none (git + build)

- [x] **Step 1: Create `talkout` integration branch and merge both features**

```bash
cd ~/projects/handy
git checkout -b talkout upstream/main
git merge --no-ff feat/s2twp -m "merge: feat/s2twp"
git merge --no-ff feat/language-mode-hotkey -m "merge: feat/language-mode-hotkey"
```

Expected: clean merges (features touch disjoint line ranges except ACTION_MAP/actions.rs region — resolve trivially if needed).

- [ ] **Step 2: Full build + tests on the integration branch — SKIPPED (2026-07-03)**

```bash
cd ~/projects/handy/src-tauri && cargo test && cd ~/projects/handy && bun run tauri build 2>&1 | tail -20
```

Decided not to run this: `cargo test` cannot execute here regardless (see
Step 3), and the full bun/tauri bundle would only produce a Linux artifact
this host won't run. Verified instead via `cargo check` + `cargo test --no-run`
(clean compile, both features present after merge). The bundled build's
correctness (frontend + full Tauri bundle) is unverified on this host —
rely on upstream CI or a macOS build for that.

- [x] **Step 3: Verify via `cargo test`/`cargo check` only (Linux is dev-only — see below), then re-run the runbook acceptance checklist on macOS**

Linux host is decided (2026-07-03) not to run Handy day-to-day, so skip
installing the `.deb` here; this box is the fork's dev/build environment
only. Ship the `talkout` branch's changes to macOS via the upstream PR
(once merged) or a manual macOS build, then re-run
`agent-skills-setup/docs/dictation-handy.md` acceptance checklist plus two
new items: mode hotkey flips language+prompt+tray label; ZH dictation of
「我要登录系统」 pastes 「我要登入系統」 (S2twp phrase conversion).

- [x] **Step 4: Update the runbook**

In `agent-skills-setup/docs/dictation-handy.md`: remove the two Phase-2 items from "Known limitations", add a "Fork build (Phase 2)" section noting the mode hotkey default (`Ctrl+Shift+L` / `⌥⇧L`) and that ZH now uses S2twp. Commit in agent-skills-setup:

```bash
cd ~/projects/agent-skills-setup
git add docs/dictation-handy.md
git commit -m "docs: update dictation runbook for phase 2 fork build"
```

---

### Task 5: Push branches and open upstream PRs

**Files:** none (git/GitHub)

- [x] **Step 1: Push all branches to the fork**

```bash
cd ~/projects/handy
git push origin feat/s2twp feat/language-mode-hotkey talkout
```

- [ ] **Step 2: Open two upstream draft PRs — DEFERRED (2026-07-03, by choice)**

```bash
gh pr create -R cjpais/Handy --draft --head herocwhsu:feat/s2twp \
  -t "Use S2twp profile for zh-Hant conversion (Taiwan phrase usage)" \
  -b "Currently zh-Hant output uses OpenCC S2tw, which converts characters but keeps mainland phrasing (e.g. 登录→登錄). S2twp additionally applies Taiwan phrase conventions (登录→登入, 软件→軟體), which is what zh-Hant (labelled Chinese (Traditional)) users type in practice. Includes unit tests. Happy to gate this behind a setting if you'd prefer the current behaviour as default."
gh pr create -R cjpais/Handy --draft --head herocwhsu:feat/language-mode-hotkey \
  -t "Add cycle_language_mode shortcut" \
  -b "Adds an optional global shortcut that cycles the transcription language EN ⇄ zh-Hant, auto-selects a matching post-process prompt by name when present, and surfaces the active mode in the tray menu. Motivated by bilingual dictation where switching language via the settings page each time is slow. Includes unit tests; binding is merged into existing installs by the existing defaults-merge logic."
```

Expected: two draft PR URLs.

- [ ] **Step 3: Record PR links in the backlog — N/A until Step 2 happens**

Append the two PR URLs to the "Handy fork — Phase 2" section of `agent-skills-setup/docs/backlog.md`; commit with `docs: record Handy phase 2 upstream PR links` and push.
