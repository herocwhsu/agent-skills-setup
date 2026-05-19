# Portable Skills Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate hardcoded user values from shipped skills, dedupe slug + html2md detection helpers, collapse credential scripts, and enable offline uninstall.

**Architecture:** Introduce `~/.agent-skills-setup/` as a cross-agent runtime layer holding `lib.sh` (shared helpers), `_store.sh` (keychain primitives), and a generated `config.sh` (user values). Skills source these at runtime. Migrate keychain prefix from `agent-skills:` to `agent-skills-setup:` automatically. Collapse three near-identical credential scripts into one parameterized `service.sh`.

**Tech Stack:** bash 3.2+ (macOS-compatible), zsh, PowerShell 5.1+, `security`/`secret-tool`/`cmdkey` for keychain, Python 3 only at skill-runtime (unchanged).

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `lib/lib.sh` | Create | Shared runtime helpers (slugify, find_html2md, load_config, read_secret, require_secret, migrate_keychain) |
| `scripts/credentials/_store.sh` | Modify | Change `_KEYCHAIN_PREFIX` to `agent-skills-setup` |
| `scripts/_lib.sh` | Modify | Add `install_runtime_dir`, `install_kiro_prompts` helpers |
| `scripts/install.sh` | Modify | Copy lib files, run migration, write installed.txt, accept `--agent` flag |
| `scripts/install.ps1` | Modify | Mirror bash changes (lib copy, migration, installed.txt, kiro prompts) |
| `scripts/uninstall.sh` | Modify | Read `installed.txt` for offline uninstall |
| `scripts/credentials/service.sh` | Create | Unified credential + config.sh writer |
| `scripts/credentials/confluence.sh` | Modify | Thin shim → service.sh |
| `scripts/credentials/jira.sh` | Modify | Thin shim → service.sh |
| `scripts/credentials/apidog.sh` | Modify | Thin shim → service.sh |
| `skills/fetch-jira-story/SKILL.md` | Modify | Use lib.sh helpers; remove hardcoded values |
| `skills/fetch-page-to-markdown/SKILL.md` | Modify | Use lib.sh helpers; remove hardcoded values |
| `skills/create-story-tasks/SKILL.md` | Modify | Use lib.sh helpers; remove hardcoded values |

---

### Task 1: Create lib.sh with slug helpers

The slug rule is duplicated 8+ times. Extract once, into a runtime lib that gets copied to `~/.agent-skills-setup/lib.sh` at install time.

**Files:**
- Create: `lib/lib.sh`

- [ ] **Step 1: Create the lib directory**

```bash
mkdir -p lib
```

- [ ] **Step 2: Write the initial lib.sh with slug helpers**

Create `lib/lib.sh`:

```bash
#!/usr/bin/env bash
# lib.sh — runtime helpers for agent-skills-setup
# Installed at ~/.agent-skills-setup/lib.sh by install.sh.
# Source this from a SKILL.md:
#   source ~/.agent-skills-setup/lib.sh

# ---------------------------------------------------------------------------
# slugify_url <url>
#   Convert any URL to a deterministic slug suitable for keychain service IDs.
#   Portable across BSD sed (macOS) and GNU sed.
#
#   slugify_url https://vivotek.atlassian.net
#   → https---vivotek-atlassian-net
# ---------------------------------------------------------------------------
slugify_url() {
  echo "$1" | sed 's|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//'
}

# ---------------------------------------------------------------------------
# service_slug <prefix> <url>
#   Compose a service-prefixed slug.
#
#   service_slug jira https://vivotek.atlassian.net
#   → jira-https---vivotek-atlassian-net
# ---------------------------------------------------------------------------
service_slug() {
  echo "$1-$(slugify_url "$2")"
}
```

- [ ] **Step 3: Verify slugify_url output**

Run:

```bash
bash -c 'source lib/lib.sh && slugify_url https://vivotek.atlassian.net'
```

Expected output: `https---vivotek-atlassian-net`

- [ ] **Step 4: Verify service_slug output**

Run:

```bash
bash -c 'source lib/lib.sh && service_slug jira https://vivotek.atlassian.net'
```

Expected output: `jira-https---vivotek-atlassian-net`

- [ ] **Step 5: Verify slug matches existing keychain entries**

```bash
security find-generic-password -s "agent-skills:jira-https---vivotek-atlassian-net" -a "hero.hsu@vivotek.com" 2>&1 | grep -c svce
```

Expected output: `1` (the existing entry exists with this exact slug — confirms our slugify rule produces the same output as before).

- [ ] **Step 6: Commit**

```bash
git add lib/lib.sh
git commit -m "feat: add lib.sh with slug helpers

Centralize the slug-generation rule that was duplicated across 8+ files.
"
```

---

### Task 2: Add find_html2md to lib.sh

The 4-directory probe (`~/.kiro/skills`, `~/.claude/skills`, etc.) is duplicated across 3 SKILL.md files in two different languages. Extract once.

**Files:**
- Modify: `lib/lib.sh`

- [ ] **Step 1: Append find_html2md to lib.sh**

Append to `lib/lib.sh`:

```bash

# ---------------------------------------------------------------------------
# find_html2md
#   Echo absolute path to html2md.py from whichever agent skills dir has it.
#   Returns 1 with stderr message if not found.
# ---------------------------------------------------------------------------
find_html2md() {
  local d
  for d in "$HOME/.kiro/skills" "$HOME/.claude/skills" "$HOME/.copilot/skills" "$HOME/.codex/skills"; do
    if [[ -f "$d/fetch-page-to-markdown/html2md.py" ]]; then
      echo "$d/fetch-page-to-markdown/html2md.py"
      return 0
    fi
  done
  echo "ERROR: html2md.py not found in any agent skills directory." >&2
  echo "  Run: bash scripts/install.sh" >&2
  return 1
}
```

- [ ] **Step 2: Verify it finds the existing html2md.py**

Run:

```bash
bash -c 'source lib/lib.sh && find_html2md'
```

Expected output: an absolute path ending in `fetch-page-to-markdown/html2md.py`. At minimum one of `~/.kiro/skills/`, `~/.claude/skills/`, etc. should already have it from a prior install.

- [ ] **Step 3: Verify failure path**

Run (simulates absence by checking a non-existent file):

```bash
bash -c 'source lib/lib.sh && _orig_HOME="$HOME"; HOME="/nonexistent" find_html2md; echo "rc=$?"'
```

Expected output: stderr `ERROR: html2md.py not found...`, then `rc=1`.

- [ ] **Step 4: Commit**

```bash
git add lib/lib.sh
git commit -m "feat: add find_html2md helper

Was duplicated in fetch-page-to-markdown and fetch-jira-story SKILL.md.
"
```

---

### Task 3: Add config + secret helpers to lib.sh

Skills today inline keychain reads. Centralize via `load_config`, `read_secret`, `require_secret`. lib.sh sources `_store.sh` (sibling file) for the OS-specific keychain primitives.

**Files:**
- Modify: `lib/lib.sh`

- [ ] **Step 1: Append config + secret helpers**

Append to `lib/lib.sh`:

```bash

# ---------------------------------------------------------------------------
# Source _store.sh from the same directory (installed alongside lib.sh).
# Provides: store_credential, read_credential, verify_credential, list_credentials.
# ---------------------------------------------------------------------------
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_LIB_DIR/_store.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/_store.sh"
fi

# ---------------------------------------------------------------------------
# load_config
#   Source ~/.agent-skills-setup/config.sh into the current shell.
#   Print a clear hint and return 1 if missing.
# ---------------------------------------------------------------------------
load_config() {
  local config="$HOME/.agent-skills-setup/config.sh"
  if [[ ! -f "$config" ]]; then
    echo "ERROR: $config not found." >&2
    echo "  Run: bash scripts/setup-credentials.sh <service> add" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$config"
}

# ---------------------------------------------------------------------------
# read_secret <slug> <user>
#   Echo the secret to stdout. Empty string if missing. Never logs.
#   Wraps _store.sh read_credential.
# ---------------------------------------------------------------------------
read_secret() {
  read_credential "$1" "$2"
}

# ---------------------------------------------------------------------------
# require_secret <slug> <user> [hint]
#   Echo secret to stdout. If missing, print hint to stderr and return 1.
# ---------------------------------------------------------------------------
require_secret() {
  local slug="$1" user="$2" hint="${3:-bash scripts/setup-credentials.sh}"
  local pass
  pass=$(read_credential "$slug" "$user")
  if [[ -z "$pass" ]]; then
    echo "ERROR: credential not found at $slug for $user" >&2
    echo "  Run: $hint" >&2
    return 1
  fi
  echo "$pass"
}
```

- [ ] **Step 2: Stage _store.sh next to lib.sh for the test**

The runtime expects `_store.sh` to live next to `lib.sh`. For local testing, copy it temporarily:

```bash
cp scripts/credentials/_store.sh lib/_store.sh
```

- [ ] **Step 3: Verify load_config errors cleanly when config.sh missing**

Run:

```bash
bash -c 'mv ~/.agent-skills-setup/config.sh ~/.agent-skills-setup/config.sh.bak 2>/dev/null; source lib/lib.sh && load_config; echo "rc=$?"'
```

Expected stderr: `ERROR: ... not found` and `Run: bash scripts/setup-credentials.sh ...`. Expected stdout: `rc=1`.

- [ ] **Step 4: Verify require_secret hint works**

Run:

```bash
bash -c 'source lib/lib.sh && require_secret "nonexistent-slug" "nobody" "do something"; echo "rc=$?"'
```

Expected stderr includes `ERROR: credential not found` and `Run: do something`. Expected stdout: `rc=1`.

- [ ] **Step 5: Add lib/_store.sh to .gitignore (test artefact only)**

Append to `.gitignore`:

```
# lib/_store.sh is copied at install time, not source-tracked
lib/_store.sh
```

Then remove the test copy:

```bash
rm lib/_store.sh
```

- [ ] **Step 6: Commit**

```bash
git add lib/lib.sh .gitignore
git commit -m "feat: add load_config, read_secret, require_secret to lib.sh

lib.sh sources _store.sh installed alongside it at runtime.
"
```

---

### Task 4: Add migrate_keychain to lib.sh

One-shot migration from `agent-skills:` → `agent-skills-setup:` prefix. Idempotent. Called by install.sh on every run; logs nothing if nothing to migrate.

**Files:**
- Modify: `lib/lib.sh`

- [ ] **Step 1: Append migrate_keychain**

Append to `lib/lib.sh`:

```bash

# ---------------------------------------------------------------------------
# migrate_keychain
#   Rename keychain entries from agent-skills:* to agent-skills-setup:*.
#   Idempotent: prints "0 migrated" if all entries already use new prefix.
#   Safe: only deletes old entry after new entry write succeeds.
# ---------------------------------------------------------------------------
migrate_keychain() {
  local count=0 os
  os=$(uname -s)

  case "$os" in
    Darwin)
      local entries
      entries=$(security dump-keychain 2>/dev/null | python3 -c "
import sys, re
out = []
for entry in sys.stdin.read().split('keychain:'):
    s = re.search(r'\"svce\"<blob>=\"(agent-skills:[^\"]+)\"', entry)
    a = re.search(r'\"acct\"<blob>=\"([^\"]+)\"', entry)
    if s and a:
        out.append(s.group(1) + '\t' + a.group(1))
print('\n'.join(out))
" 2>/dev/null)

      while IFS=$'\t' read -r svc user; do
        [[ -z "$svc" ]] && continue
        local newsvc="agent-skills-setup:${svc#agent-skills:}"
        local pass
        pass=$(security find-generic-password -s "$svc" -a "$user" -w 2>/dev/null) || continue
        if security add-generic-password -s "$newsvc" -a "$user" -w "$pass" 2>/dev/null; then
          security delete-generic-password -s "$svc" -a "$user" 2>/dev/null
          count=$((count + 1))
        fi
      done <<< "$entries"
      ;;
    Linux)
      if command -v secret-tool &>/dev/null; then
        # secret-tool has no enumerate-by-prefix; rely on user re-run if needed.
        # No-op: Linux users without explicit migration just re-add credentials.
        :
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Windows migration via cmdkey list parsing — best-effort.
      while IFS= read -r line; do
        local target user_field
        target=$(echo "$line" | sed -n 's/.*Target: \(agent-skills:[^ ]*\).*/\1/p')
        [[ -z "$target" ]] && continue
        local newtarget="agent-skills-setup:${target#agent-skills:}"
        # Re-prompt is the safest cross-version path; log a hint.
        echo "  → Windows migration needed for $target — run setup-credentials again." >&2
      done < <(cmdkey /list 2>/dev/null)
      ;;
  esac

  if [[ $count -gt 0 ]]; then
    echo "  ✓ migrated $count keychain entries: agent-skills: → agent-skills-setup:"
  fi
}
```

- [ ] **Step 2: Verify migration is idempotent on a fresh system**

Run (no entries with old prefix should exist after current install):

```bash
bash -c 'source lib/lib.sh && migrate_keychain; echo "rc=$?"'
```

Expected output: no migration lines printed (because no `agent-skills:*` entries exist after a future migration), `rc=0`. On the first run with existing entries, expect `✓ migrated N keychain entries`.

- [ ] **Step 3: Test with a synthetic entry (macOS only)**

Create a fake entry under the old prefix:

```bash
security add-generic-password -s "agent-skills:test-migration" -a "testuser" -w "secret123"
```

Run migration:

```bash
bash -c 'source lib/lib.sh && migrate_keychain'
```

Expected output: `✓ migrated 1 keychain entries: agent-skills: → agent-skills-setup:`

Verify the new entry exists:

```bash
security find-generic-password -s "agent-skills-setup:test-migration" -a "testuser" -w
```

Expected output: `secret123`

Verify the old entry is gone:

```bash
security find-generic-password -s "agent-skills:test-migration" -a "testuser" 2>&1 | grep -c "could not be found"
```

Expected output: `1`

- [ ] **Step 4: Cleanup the test entry**

```bash
security delete-generic-password -s "agent-skills-setup:test-migration" -a "testuser" 2>/dev/null
```

- [ ] **Step 5: Commit**

```bash
git add lib/lib.sh
git commit -m "feat: add migrate_keychain for agent-skills → agent-skills-setup

Auto-migrates existing entries on first install.sh run after upgrade.
"
```

---

### Task 5: Update _store.sh to use new prefix

Change the keychain prefix constant. After this point, all NEW entries land at `agent-skills-setup:*`.

**Files:**
- Modify: `scripts/credentials/_store.sh:16`

- [ ] **Step 1: Change the prefix constant**

In `scripts/credentials/_store.sh` line 16, change:

```bash
readonly _KEYCHAIN_PREFIX="agent-skills"
```

to:

```bash
readonly _KEYCHAIN_PREFIX="agent-skills-setup"
```

- [ ] **Step 2: Verify the constant is used everywhere it should be**

```bash
grep -n "agent-skills" scripts/credentials/_store.sh
```

Expected output: only the line `readonly _KEYCHAIN_PREFIX="agent-skills-setup"` and the comment block. No bare `agent-skills:` literals elsewhere in the file.

- [ ] **Step 3: Commit**

```bash
git add scripts/credentials/_store.sh
git commit -m "refactor: rename keychain prefix to agent-skills-setup

Avoids collision with any tool that might use the more generic
'agent-skills' name. Migration handled by lib.sh::migrate_keychain.
"
```

---

### Task 6: install.sh — install runtime dir + lib files

`install.sh` creates `~/.agent-skills-setup/` and copies `lib.sh` and `_store.sh` into it. Idempotent (`cp -f`).

**Files:**
- Modify: `scripts/_lib.sh` (new helper)
- Modify: `scripts/install.sh` (call helper)

- [ ] **Step 1: Add install_runtime_dir to scripts/_lib.sh**

Append to `scripts/_lib.sh` (after the existing `install_local_skill` function):

```bash

# ---------------------------------------------------------------------------
# install_runtime_dir <repo_dir>
#   Create ~/.agent-skills-setup/ and copy runtime files (lib.sh, _store.sh)
#   into it. Idempotent.
# ---------------------------------------------------------------------------
install_runtime_dir() {
  local repo_dir="$1"
  local rtdir="$HOME/.agent-skills-setup"
  mkdir -p "$rtdir"
  cp -f "$repo_dir/lib/lib.sh" "$rtdir/lib.sh"
  cp -f "$repo_dir/scripts/credentials/_store.sh" "$rtdir/_store.sh"
  echo "  ✓ runtime → $rtdir"
}
```

- [ ] **Step 2: Call install_runtime_dir from install.sh**

In `scripts/install.sh`, find the line:

```bash
echo "==> Installing skills from registry.txt..."
```

Replace it with:

```bash
echo "==> Installing runtime helpers..."
install_runtime_dir "$REPO_DIR"

echo ""
echo "==> Installing skills from registry.txt..."
```

- [ ] **Step 3: Verify ~/.agent-skills-setup/ is created**

Run (in a clean state — back up any existing dir first):

```bash
[ -d ~/.agent-skills-setup ] && mv ~/.agent-skills-setup ~/.agent-skills-setup.bak
bash scripts/install.sh --agent claude 2>/dev/null || bash -c 'source scripts/_lib.sh && install_runtime_dir "$(pwd)"'
ls -la ~/.agent-skills-setup/
```

Expected output: shows `lib.sh` and `_store.sh` both present.

- [ ] **Step 4: Verify lib.sh is sourceable from its installed location**

```bash
bash -c 'source ~/.agent-skills-setup/lib.sh && slugify_url https://example.com'
```

Expected output: `https---example-com`

- [ ] **Step 5: Restore any backup (if Step 3 created one)**

```bash
[ -d ~/.agent-skills-setup.bak ] && rm -rf ~/.agent-skills-setup.bak
```

- [ ] **Step 6: Commit**

```bash
git add scripts/_lib.sh scripts/install.sh
git commit -m "feat: install.sh copies lib.sh + _store.sh to ~/.agent-skills-setup/

Cross-agent runtime layer. SKILL.md files source these instead of
inlining the same logic four times.
"
```

---

### Task 7: install.sh — run keychain migration

Call `migrate_keychain` from install.sh on every run. Idempotent.

**Files:**
- Modify: `scripts/install.sh`

- [ ] **Step 1: Source lib.sh from the install dir and call migration**

In `scripts/install.sh`, after the `install_runtime_dir` call, add:

```bash

echo ""
echo "==> Migrating keychain entries (if any)..."
# shellcheck source=/dev/null
source "$HOME/.agent-skills-setup/lib.sh"
migrate_keychain
```

The full block now reads:

```bash
echo "==> Installing runtime helpers..."
install_runtime_dir "$REPO_DIR"

echo ""
echo "==> Migrating keychain entries (if any)..."
# shellcheck source=/dev/null
source "$HOME/.agent-skills-setup/lib.sh"
migrate_keychain

echo ""
echo "==> Installing skills from registry.txt..."
```

- [ ] **Step 2: Verify migration runs without error**

```bash
bash scripts/install.sh --agent claude 2>&1 | grep -E "Migrating|migrated"
```

Expected output: at minimum the `==> Migrating keychain entries` line. May also show `✓ migrated N entries` if there are any old `agent-skills:*` entries left.

- [ ] **Step 3: Verify migration is idempotent (run install.sh twice)**

```bash
bash scripts/install.sh --agent claude 2>&1 | grep -c "✓ migrated"
```

Expected output: `0` on the second run (everything already migrated, nothing to do).

- [ ] **Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: install.sh runs keychain migration on every run

Idempotent — only acts when old agent-skills:* entries are present.
"
```

---

### Task 8: install.sh — write installed.txt

Track skill names installed this run so uninstall doesn't need network.

**Files:**
- Modify: `scripts/_lib.sh`
- Modify: `scripts/install.sh`

- [ ] **Step 1: Initialize installed.txt at start of install loop**

In `scripts/install.sh`, before the `for agent in "${SELECTED_AGENTS[@]}"` loop, add:

```bash
INSTALLED_LIST="$HOME/.agent-skills-setup/installed.txt"
> "$INSTALLED_LIST"  # truncate
```

- [ ] **Step 2: Update install helpers in scripts/_lib.sh to append to INSTALLED_LIST**

In `scripts/_lib.sh`, add after the existing helpers:

```bash

# ---------------------------------------------------------------------------
# record_installed <skill_name>
#   Append a skill name to ~/.agent-skills-setup/installed.txt for offline
#   uninstall. No-op if INSTALLED_LIST is unset.
# ---------------------------------------------------------------------------
record_installed() {
  [[ -n "${INSTALLED_LIST:-}" ]] || return 0
  echo "$1" >> "$INSTALLED_LIST"
}
```

- [ ] **Step 3: Call record_installed from install_skill**

In `scripts/_lib.sh`, find the existing `install_skill` function (around line 62) and modify the `echo "  ✓ $name"` line. Replace:

```bash
  echo "  ✓ $name"
}
```

with:

```bash
  echo "  ✓ $name"
  record_installed "$name"
}
```

- [ ] **Step 4: Call record_installed from install_github_skill**

In `scripts/_lib.sh`, find the existing `install_github_skill` function. Inside the `for skill_dir in "$src_dir"/*/` loop, after the `cp -r` and `count=$((count + 1))` lines, add:

```bash
    record_installed "$skill_name"
```

The loop body becomes:

```bash
  for skill_dir in "$src_dir"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    cp -r "$skill_dir" "$target_dir/$skill_name"
    record_installed "$skill_name"
    count=$((count + 1))
  done
```

- [ ] **Step 5: Verify installed.txt is populated after install**

```bash
bash scripts/install.sh --agent claude
cat ~/.agent-skills-setup/installed.txt
```

Expected output: a list of installed skill names, one per line. At least `fetch-page-to-markdown`, `fetch-jira-story`, `plan-story`, `create-story-tasks`, plus the superpowers skills.

- [ ] **Step 6: Commit**

```bash
git add scripts/_lib.sh scripts/install.sh
git commit -m "feat: install.sh records installed skills to installed.txt

Enables offline uninstall without re-downloading the GitHub zip.
"
```

---

### Task 9: install.sh — accept --agent flag

Match the existing `install.ps1 -Agent` behavior so the script can be used non-interactively.

**Files:**
- Modify: `scripts/_lib.sh:select_agents`
- Modify: `scripts/install.sh`

- [ ] **Step 1: Modify select_agents to accept a default**

In `scripts/_lib.sh`, replace the `select_agents()` function (around line 216) with:

```bash
# Accept agent via $1 (kiro|claude|copilot|codex|all). Prompt only if empty.
# Sets global SELECTED_AGENTS array.
select_agents() {
  local choice="${1:-}"

  if [[ -z "$choice" ]]; then
    echo ""
    echo "Which agent(s) to target?"
    echo "  1) Kiro        (~/.kiro/skills/)"
    echo "  2) Claude Code (~/.claude/skills/)"
    echo "  3) Copilot     (~/.copilot/skills/)"
    echo "  4) Codex       (~/.codex/skills/)"
    echo "  5) All of the above"
    echo ""
    read -rp "Choice [1-5]: " input
    case "$input" in
      1) choice="kiro" ;;
      2) choice="claude" ;;
      3) choice="copilot" ;;
      4) choice="codex" ;;
      5) choice="all" ;;
      *) echo "Invalid choice, defaulting to kiro."; choice="kiro" ;;
    esac
  fi

  case "$choice" in
    kiro)    SELECTED_AGENTS=("kiro") ;;
    claude)  SELECTED_AGENTS=("claude") ;;
    copilot) SELECTED_AGENTS=("copilot") ;;
    codex)   SELECTED_AGENTS=("codex") ;;
    all)     SELECTED_AGENTS=("kiro" "claude" "copilot" "codex") ;;
    *)       echo "Invalid agent: $choice"; exit 1 ;;
  esac
}
```

- [ ] **Step 2: Parse --agent in install.sh**

In `scripts/install.sh`, after the `source "$REPO_DIR/scripts/_lib.sh"` line, add:

```bash
AGENT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_ARG="$2"; shift 2 ;;
    --agent=*)
      AGENT_ARG="${1#*=}"; shift ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

select_agents "$AGENT_ARG"
```

Remove the standalone `select_agents` call further down (the one without an argument).

- [ ] **Step 3: Verify non-interactive flag works**

```bash
bash scripts/install.sh --agent claude 2>&1 | head -5
```

Expected output: no "Which agent(s) to target?" prompt; install proceeds for claude only.

- [ ] **Step 4: Verify equals-form works**

```bash
bash scripts/install.sh --agent=claude 2>&1 | grep -c "Agent: claude"
```

Expected output: `1`

- [ ] **Step 5: Verify interactive mode still works (no flag)**

```bash
echo "2" | bash scripts/install.sh
```

Expected: prompts for choice, accepts `2`, installs to claude. (May error after if rerunning quickly — that's fine.)

- [ ] **Step 6: Commit**

```bash
git add scripts/_lib.sh scripts/install.sh
git commit -m "feat: install.sh accepts --agent flag for non-interactive use

Matches the existing install.ps1 -Agent behavior.
"
```

---

### Task 10: install.sh — extract kiro prompts into named function

Move the inlined kiro prompts copy into `install_kiro_prompts()` for clarity and so install.ps1 can mirror it cleanly in Task 18.

**Files:**
- Modify: `scripts/_lib.sh`
- Modify: `scripts/install.sh`

- [ ] **Step 1: Add install_kiro_prompts to scripts/_lib.sh**

Append to `scripts/_lib.sh`:

```bash

# ---------------------------------------------------------------------------
# install_kiro_prompts <repo_dir>
#   Copy prompts/*.md to ~/.kiro/prompts/. Kiro-specific (no other agent
#   has a prompts/ concept), so this is appropriately a special case.
# ---------------------------------------------------------------------------
install_kiro_prompts() {
  local repo_dir="$1"
  local target="$HOME/.kiro/prompts"
  mkdir -p "$target"
  local count=0
  for f in "$repo_dir/prompts/"*.md; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$target/$(basename "$f")"
    count=$((count + 1))
  done
  echo "  ✓ kiro prompts ($count files) → $target"
}
```

- [ ] **Step 2: Replace the inlined block in install.sh**

In `scripts/install.sh`, find the existing block:

```bash
# Install Kiro steering file if kiro was selected
for agent in "${SELECTED_AGENTS[@]}"; do
  if [[ "$agent" == "kiro" ]]; then
    mkdir -p "$HOME/.kiro/prompts"
    for f in "$REPO_DIR/prompts/"*.md; do
      cp "$f" "$HOME/.kiro/prompts/$(basename "$f")"
    done
    echo "  ✓ kiro prompts → ~/.kiro/prompts/"
    break
  fi
done
```

Replace with:

```bash
# Install Kiro prompts if kiro was selected
for agent in "${SELECTED_AGENTS[@]}"; do
  if [[ "$agent" == "kiro" ]]; then
    install_kiro_prompts "$REPO_DIR"
    break
  fi
done
```

- [ ] **Step 3: Verify kiro prompts still install correctly**

```bash
bash scripts/install.sh --agent kiro 2>&1 | grep "kiro prompts"
ls ~/.kiro/prompts/
```

Expected output of grep: `✓ kiro prompts (N files) → /Users/.../​.kiro/prompts`
Expected `ls`: shows brainstorming.md, debug.md, tdd.md, etc.

- [ ] **Step 4: Commit**

```bash
git add scripts/_lib.sh scripts/install.sh
git commit -m "refactor: extract install_kiro_prompts into _lib.sh

Named function, easier to mirror in install.ps1.
"
```

---

### Task 11: Create scripts/credentials/service.sh

Unified credential script that replaces 95% of confluence.sh + jira.sh + apidog.sh. Also writes to `config.sh`.

**Files:**
- Create: `scripts/credentials/service.sh`

- [ ] **Step 1: Create service.sh**

Create `scripts/credentials/service.sh`:

```bash
#!/usr/bin/env bash
# credentials/service.sh — manage credentials for any service in one script
# Usage: bash service.sh <service> <add|update|delete|list|verify>
#
# Supported services: confluence | jira | apidog
set -euo pipefail
source "$(dirname "$0")/_store.sh"

CONFIG_FILE="$HOME/.agent-skills-setup/config.sh"

# ---------------------------------------------------------------------------
# Service definitions
# ---------------------------------------------------------------------------
# Each service: <slug-prefix>|<url-prompt>|<config-host-key>|<config-user-key>|<extra-prompts>
#   url-prompt = empty if service has no URL (e.g. apidog)
#   extra-prompts = colon-separated list of "config_key:prompt_text" pairs
service_def() {
  case "$1" in
    confluence)
      echo "confluence|Confluence URL (e.g. https://confluence.example.com)|CONFLUENCE_HOST|CONFLUENCE_USER|"
      ;;
    jira)
      echo "jira|Jira URL (e.g. https://your-org.atlassian.net)|JIRA_HOST|JIRA_USER|JIRA_PROJECT_KEY:Jira project key (e.g. VOR)"
      ;;
    apidog)
      echo "apidog||APIDOG_HOST|APIDOG_USER|"
      ;;
    *)
      echo "ERROR: unknown service '$1'. Supported: confluence | jira | apidog" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# write_config_kv <key> <value>
#   Idempotent upsert: replaces existing KEY=... line, or appends.
# ---------------------------------------------------------------------------
write_config_kv() {
  local key="$1" val="$2"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    {
      echo "# ~/.agent-skills-setup/config.sh — generated by setup-credentials.sh"
      echo "# Edit by hand if needed; setup-credentials re-reads on next run."
      echo ""
    } > "$CONFIG_FILE"
  fi
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    # Use sed -i with portable BSD/GNU compatibility
    sed -i.bak "s|^$key=.*|$key=\"$val\"|" "$CONFIG_FILE"
    rm -f "$CONFIG_FILE.bak"
  else
    echo "$key=\"$val\"" >> "$CONFIG_FILE"
  fi
}

# ---------------------------------------------------------------------------
# read_config_kv <key>
#   Print value of $key from config.sh, empty if missing.
# ---------------------------------------------------------------------------
read_config_kv() {
  [[ -f "$CONFIG_FILE" ]] || { echo ""; return; }
  local val
  val=$(grep "^$1=" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^=]*=//;s/^"//;s/"$//')
  echo "$val"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SERVICE="${1:-}"
ACTION="${2:-}"

if [[ -z "$SERVICE" || -z "$ACTION" ]]; then
  echo "Usage: $0 <service> <add|update|delete|list|verify>"
  echo "Services: confluence | jira | apidog"
  exit 1
fi

DEF=$(service_def "$SERVICE") || exit 1
IFS='|' read -r SLUG_PREFIX URL_PROMPT HOST_KEY USER_KEY EXTRA <<< "$DEF"

# ---------------------------------------------------------------------------
# Compute slug from current host (URL or fixed for apidog)
# Reads HOST from config.sh first; prompts if missing.
# ---------------------------------------------------------------------------
compute_slug() {
  if [[ -z "$URL_PROMPT" ]]; then
    echo "$SLUG_PREFIX"   # services without URL (apidog)
    return
  fi
  local host
  host=$(read_config_kv "$HOST_KEY")
  if [[ -z "$host" ]]; then
    echo "ERROR: $HOST_KEY not in config.sh — run '$0 $SERVICE add' first." >&2
    return 1
  fi
  source "$HOME/.agent-skills-setup/lib.sh" 2>/dev/null
  service_slug "$SLUG_PREFIX" "https://$host"
}

case "$ACTION" in
  add|update)
    if [[ -n "$URL_PROMPT" ]]; then
      DEFAULT_HOST=$(read_config_kv "$HOST_KEY")
      read -rp "$URL_PROMPT${DEFAULT_HOST:+ [https://$DEFAULT_HOST]}: " URL_INPUT
      URL_INPUT="${URL_INPUT:-https://$DEFAULT_HOST}"
      HOST_VALUE="${URL_INPUT#https://}"; HOST_VALUE="${HOST_VALUE#http://}"
      write_config_kv "$HOST_KEY" "$HOST_VALUE"
      SLUG="${SLUG_PREFIX}-$(echo "$URL_INPUT" | sed 's|[^a-zA-Z0-9]|-|g;s/-\+/-/g;s/-$//')"
    else
      SLUG="$SLUG_PREFIX"
    fi

    DEFAULT_USER=$(read_config_kv "$USER_KEY")
    read -rp "Username${DEFAULT_USER:+ [$DEFAULT_USER]}: " USER_INPUT
    USER_INPUT="${USER_INPUT:-$DEFAULT_USER}"
    write_config_kv "$USER_KEY" "$USER_INPUT"

    read -rsp "Password / API token (hidden): " PASS; echo
    store_credential "$SLUG" "$USER_INPUT" "$PASS"

    # Handle extra prompts (e.g. JIRA_PROJECT_KEY)
    if [[ -n "$EXTRA" ]]; then
      IFS=':' read -r EXTRA_KEY EXTRA_PROMPT <<< "$EXTRA"
      DEFAULT_EXTRA=$(read_config_kv "$EXTRA_KEY")
      read -rp "$EXTRA_PROMPT${DEFAULT_EXTRA:+ [$DEFAULT_EXTRA]}: " EXTRA_INPUT
      EXTRA_INPUT="${EXTRA_INPUT:-$DEFAULT_EXTRA}"
      write_config_kv "$EXTRA_KEY" "$EXTRA_INPUT"
    fi

    echo "  ✓ $SERVICE credentials saved (keychain + $CONFIG_FILE)"
    ;;

  delete)
    SLUG=$(compute_slug) || exit 1
    USER_VAL=$(read_config_kv "$USER_KEY")
    if [[ -z "$USER_VAL" ]]; then
      read -rp "Username: " USER_VAL
    fi
    delete_credential "$SLUG" "$USER_VAL"
    ;;

  list)
    list_credentials
    ;;

  verify)
    SLUG=$(compute_slug) || exit 1
    USER_VAL=$(read_config_kv "$USER_KEY")
    if [[ -z "$USER_VAL" ]]; then
      read -rp "Username: " USER_VAL
    fi
    verify_credential "$SLUG" "$USER_VAL"
    ;;

  *)
    echo "Unknown action: $ACTION. Use add|update|delete|list|verify." >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/credentials/service.sh
```

- [ ] **Step 3: Verify list works (no input)**

```bash
bash scripts/credentials/service.sh apidog list
```

Expected output: header `Stored credentials (prefix: agent-skills-setup:):` followed by either entries or `(none)`.

- [ ] **Step 4: Verify error message for unknown service**

```bash
bash scripts/credentials/service.sh unknown add 2>&1 | head -1
```

Expected output: `ERROR: unknown service 'unknown'. Supported: confluence | jira | apidog`

- [ ] **Step 5: Commit**

```bash
git add scripts/credentials/service.sh
git commit -m "feat: add unified service.sh credential manager

Replaces 95% duplicated logic in confluence.sh + jira.sh + apidog.sh.
Also writes config.sh as a side effect of add/update.
"
```

---

### Task 12: Verify config.sh write flow end-to-end

Add a real credential through service.sh, confirm config.sh + keychain are both populated, then read it back.

**Files:**
- (No file changes — verification only)

- [ ] **Step 1: Back up any existing config.sh**

```bash
[ -f ~/.agent-skills-setup/config.sh ] && cp ~/.agent-skills-setup/config.sh ~/.agent-skills-setup/config.sh.bak
```

- [ ] **Step 2: Add a test confluence credential**

```bash
echo -e "https://confluence.test.com\ntest-user\nsecret123" | bash scripts/credentials/service.sh confluence add
```

Expected output: `✓ confluence credentials saved (keychain + ~/.agent-skills-setup/config.sh)`

- [ ] **Step 3: Verify config.sh has the values**

```bash
cat ~/.agent-skills-setup/config.sh
```

Expected output (subset):
```
CONFLUENCE_HOST="confluence.test.com"
CONFLUENCE_USER="test-user"
```

- [ ] **Step 4: Verify the keychain entry exists with correct slug**

```bash
security find-generic-password \
  -s "agent-skills-setup:confluence-https---confluence-test-com" \
  -a "test-user" -w
```

Expected output: `secret123`

- [ ] **Step 5: Test verify action**

```bash
bash scripts/credentials/service.sh confluence verify
```

Expected output: `✓ Credential found for confluence-https---confluence-test-com / test-user (value hidden)`

- [ ] **Step 6: Test that defaults pre-fill on subsequent add**

```bash
echo -e "\n\nnewsecret456" | bash scripts/credentials/service.sh confluence add
```

(Empty input for URL and user — should fall back to existing values.)

```bash
security find-generic-password \
  -s "agent-skills-setup:confluence-https---confluence-test-com" \
  -a "test-user" -w
```

Expected output: `newsecret456` (password updated, slug + user unchanged).

- [ ] **Step 7: Cleanup the test credential**

```bash
bash scripts/credentials/service.sh confluence delete <<< "test-user"
```

Restore original config.sh:

```bash
[ -f ~/.agent-skills-setup/config.sh.bak ] && mv ~/.agent-skills-setup/config.sh.bak ~/.agent-skills-setup/config.sh
```

- [ ] **Step 8: Commit (no files changed — note in the next task's commit if needed)**

Skip — no source changes in this verification task.

---

### Task 13: Convert confluence.sh / jira.sh / apidog.sh into shims

Backward-compat: existing scripts keep working but now delegate to service.sh.

**Files:**
- Modify: `scripts/credentials/confluence.sh` (full rewrite)
- Modify: `scripts/credentials/jira.sh` (full rewrite)
- Modify: `scripts/credentials/apidog.sh` (full rewrite)

- [ ] **Step 1: Replace confluence.sh with a shim**

Replace the entire contents of `scripts/credentials/confluence.sh` with:

```bash
#!/usr/bin/env bash
# credentials/confluence.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" confluence "$@"
```

- [ ] **Step 2: Replace jira.sh with a shim**

Replace the entire contents of `scripts/credentials/jira.sh` with:

```bash
#!/usr/bin/env bash
# credentials/jira.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" jira "$@"
```

- [ ] **Step 3: Replace apidog.sh with a shim**

Replace the entire contents of `scripts/credentials/apidog.sh` with:

```bash
#!/usr/bin/env bash
# credentials/apidog.sh — shim, delegates to service.sh
# Kept for backward compatibility with existing references.
exec bash "$(dirname "$0")/service.sh" apidog "$@"
```

- [ ] **Step 4: Verify each shim still works**

```bash
bash scripts/credentials/confluence.sh list 2>&1 | head -1
bash scripts/credentials/jira.sh list 2>&1 | head -1
bash scripts/credentials/apidog.sh list 2>&1 | head -1
```

Expected output (each line): `Stored credentials (prefix: agent-skills-setup:):`

- [ ] **Step 5: Verify setup-credentials.sh dispatch still works**

```bash
bash scripts/setup-credentials.sh apidog list 2>&1 | head -1
```

Expected output: `Stored credentials (prefix: agent-skills-setup:):` (because setup-credentials.sh dispatches to `apidog.sh`, which is now a shim that exec's `service.sh`).

- [ ] **Step 6: Commit**

```bash
git add scripts/credentials/confluence.sh scripts/credentials/jira.sh scripts/credentials/apidog.sh
git commit -m "refactor: collapse credential scripts into shims for service.sh

confluence.sh, jira.sh, apidog.sh were 95% identical. Logic lives in
service.sh; these are kept as one-line backward-compat wrappers.
"
```

---

### Task 14: Refactor fetch-jira-story/SKILL.md

Remove all hardcoded vivotek/hero.hsu values. Use lib.sh helpers.

**Files:**
- Modify: `skills/fetch-jira-story/SKILL.md`

- [ ] **Step 1: Replace the Implementation section**

Open `skills/fetch-jira-story/SKILL.md`. Replace the section starting at `## Implementation` and continuing through `### Step 3 — Follow links` with:

````markdown
## Implementation

### Step 0 — Load config and helpers

Every skill invocation starts with this:

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

# Validate required keys are set
[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }
```

### Step 1 — Fetch story

```bash
STORY_ID="$1"   # e.g. VOR-29600

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  "https://$JIRA_HOST/rest/api/2/issue/$STORY_ID" \
  > /tmp/_jira_issue.json
unset _JIRA_PASS
```

### Step 2 — Extract and save story.md

```python
import json, re, os

with open('/tmp/_jira_issue.json') as f:
    issue = json.load(f)

fields = issue['fields']
story_id = issue['key']
title = fields['summary']
description = fields.get('description') or ''
status = fields['status']['name']
story_type = fields['issuetype']['name']

out_dir = f'./docs/stories/{story_id}'
os.makedirs(out_dir, exist_ok=True)

urls = re.findall(r'https?://[^\s\|\]\"]+', description)

with open(f'{out_dir}/story.md', 'w') as f:
    f.write(f'# {story_id}: {title}\n\n')
    f.write(f'**Type:** {story_type}  \n**Status:** {status}  \n**Branch:** {story_id}\n\n')
    f.write('## Description\n\n')
    f.write(description + '\n\n')
    if urls:
        f.write('## Extracted Links\n\n')
        for url in urls:
            f.write(f'- {url}\n')

print(f'Saved: {out_dir}/story.md')
print(f'Links found: {urls}')
```

### Step 3 — Follow links

For each extracted URL:

**Confluence links** (`confluence.` in host):

```bash
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — skip Confluence link" >&2; }

CONF_SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_CONF_PASS=$(require_secret "$CONF_SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add")

if [[ -n "${_CONF_PASS:-}" ]]; then
  PAGE_ID="<extracted from URL ?pageId=XXXXXX>"
  HTML2MD=$(find_html2md) || exit 1

  curl -s -u "$CONFLUENCE_USER:$_CONF_PASS" \
    "https://$CONFLUENCE_HOST/rest/api/content/$PAGE_ID?expand=body.storage,title" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['body']['storage']['value'])
" | python3 "$HTML2MD" > "./docs/stories/$STORY_ID/confluence-${PAGE_ID}.md"
  unset _CONF_PASS
fi
```

→ Save to `./docs/stories/<STORY-ID>/confluence-<pageId>.md`

**Apidog / other public links**:

```bash
URL="https://..."
SLUG=$(slugify_url "$URL" | cut -c1-40)
HTML2MD=$(find_html2md) || exit 1

curl -s "$URL" | python3 "$HTML2MD" \
  > "./docs/stories/$STORY_ID/apidog-${SLUG}.md"
```
````

- [ ] **Step 2: Update the Credential Setup section to reference service.sh**

In the same file, replace the `## Credential Setup` section with:

```markdown
## Credential Setup

Run once per service. The setup writes both the keychain entry and the
matching `config.sh` keys (`JIRA_HOST`, `JIRA_USER`, `JIRA_PROJECT_KEY`).

```bash
bash scripts/credentials/service.sh jira add

# Verify (no value printed):
bash scripts/credentials/service.sh jira verify
```

**Important:** Jira Cloud requires the full email address as the username
(e.g. `you@your-org.com`). Username-only returns 401.
```

- [ ] **Step 3: Remove the now-obsolete Security Rule section**

Delete the entire `## Security Rule` section. The `require_secret` helper handles unset-after-use semantics implicitly (the variable goes out of scope at function return, and the SKILL.md still calls `unset _JIRA_PASS` after the curl).

- [ ] **Step 4: Verify SKILL.md no longer contains hardcoded values**

```bash
grep -E "vivotek|hero\.hsu" skills/fetch-jira-story/SKILL.md
```

Expected output: empty (no matches).

- [ ] **Step 5: Verify the file references lib.sh helpers**

```bash
grep -E "load_config|service_slug|require_secret|find_html2md|slugify_url" skills/fetch-jira-story/SKILL.md | wc -l
```

Expected output: at least `5` (each helper appears at least once).

- [ ] **Step 6: Commit**

```bash
git add skills/fetch-jira-story/SKILL.md
git commit -m "refactor: fetch-jira-story uses lib.sh helpers, no hardcoded values

Removes vivotek/hero.hsu hardcoded references; reads JIRA_HOST etc.
from \$HOME/.agent-skills-setup/config.sh.
"
```

---

### Task 15: Refactor fetch-page-to-markdown/SKILL.md

Same treatment as Task 14, applied to the Confluence + plain-curl flows.

**Files:**
- Modify: `skills/fetch-page-to-markdown/SKILL.md`

- [ ] **Step 1: Replace the Implementation section**

In `skills/fetch-page-to-markdown/SKILL.md`, replace the entire `## Implementation` section (down to but not including `## File Naming`) with:

````markdown
## Implementation

### Step 0 — Load config and helpers

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1
```

### Confluence URL (REST API path)

```bash
[[ -z "${CONFLUENCE_HOST:-}" ]] && { echo "ERROR: CONFLUENCE_HOST not in config.sh — run: bash scripts/credentials/service.sh confluence add" >&2; exit 1; }

SLUG=$(service_slug confluence "https://$CONFLUENCE_HOST")
_PASS=$(require_secret "$SLUG" "$CONFLUENCE_USER" "bash scripts/credentials/service.sh confluence add") || exit 1

SPACE="PP2"
TITLE="My Page Title"
API="https://$CONFLUENCE_HOST/rest/api/content"

curl -s -u "$CONFLUENCE_USER:$_PASS" \
  "${API}?spaceKey=${SPACE}&title=${TITLE}&expand=body.storage" \
  > /tmp/_cf_response.json
unset _PASS

HTML2MD=$(find_html2md) || exit 1

python3 - <<EOF
import json, subprocess, os, re
from datetime import date

with open('/tmp/_cf_response.json') as f:
    data = json.load(f)

r = data['results'][0]
title = r['title']
html = r['body']['storage']['value']

with open('/tmp/_cf_body.html', 'w') as f:
    f.write(html)

slug = re.sub(r'-+', '-', re.sub(r'[^a-z0-9]', '-', title.lower()))[:40]
out_dir = './docs/pre-specs'
os.makedirs(out_dir, exist_ok=True)
out = f"{out_dir}/{date.today()}-{slug}-reference.md"

result = subprocess.run(
    ['python3', '$HTML2MD'],
    stdin=open('/tmp/_cf_body.html'), capture_output=True, text=True
)
with open(out, 'w') as f:
    f.write(result.stdout)

print(f"Saved: {out}")
EOF
rm -f /tmp/_cf_response.json /tmp/_cf_body.html
```

### MCP path (if Confluence MCP server configured)

If a Confluence MCP tool is available, use it instead — it handles auth and returns clean content directly. Still save output with the same file naming convention.

### Non-Confluence URL (plain curl)

```bash
URL="https://example.com/some-page"
SLUG=$(slugify_url "$URL" | cut -c1-40)
DATE=$(date +%Y-%m-%d)
HTML2MD=$(find_html2md) || exit 1

mkdir -p ./docs/pre-specs
curl -s "$URL" | python3 "$HTML2MD" \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
```

For authenticated non-Confluence URLs, use `require_secret` against an
appropriate slug — see fetch-jira-story's Apidog example.
````

- [ ] **Step 2: Replace the Credential Setup section**

Replace the existing `## Credential Setup` section with:

```markdown
## Credential Setup (one-time per platform)

```bash
bash scripts/credentials/service.sh confluence add

# Verify (no value printed):
bash scripts/credentials/service.sh confluence verify
```

The setup writes both the keychain entry and `CONFLUENCE_HOST` /
`CONFLUENCE_USER` keys in `~/.agent-skills-setup/config.sh`.
```

- [ ] **Step 3: Remove the obsolete Security Rule section**

Delete the entire `## Security Rule` section.

- [ ] **Step 4: Verify the file no longer contains hardcoded values**

```bash
grep -E "vivotek|hero\.hsu" skills/fetch-page-to-markdown/SKILL.md
```

Expected output: empty.

- [ ] **Step 5: Verify lib.sh helpers are referenced**

```bash
grep -E "load_config|service_slug|require_secret|find_html2md|slugify_url" skills/fetch-page-to-markdown/SKILL.md | wc -l
```

Expected output: at least `4`.

- [ ] **Step 6: Commit**

```bash
git add skills/fetch-page-to-markdown/SKILL.md
git commit -m "refactor: fetch-page-to-markdown uses lib.sh helpers

Removes vivotek/hero.hsu hardcoded references; reads CONFLUENCE_HOST
and CONFLUENCE_USER from config.sh.
"
```

---

### Task 16: Refactor create-story-tasks/SKILL.md

Final SKILL.md cleanup. Includes `JIRA_PROJECT_KEY` from config.sh.

**Files:**
- Modify: `skills/create-story-tasks/SKILL.md`

- [ ] **Step 1: Replace Step 1 (Create Jira sub-tasks) of the Workflow section**

In `skills/create-story-tasks/SKILL.md`, replace the entire `### Step 1 — Create Jira sub-tasks` block (the bash code block following the heading) with:

````markdown
### Step 1 — Create Jira sub-tasks

```bash
source ~/.agent-skills-setup/lib.sh
load_config || exit 1

[[ -z "${JIRA_HOST:-}" ]] && { echo "ERROR: JIRA_HOST not in config.sh" >&2; exit 1; }
[[ -z "${JIRA_USER:-}" ]] && { echo "ERROR: JIRA_USER not in config.sh" >&2; exit 1; }
[[ -z "${JIRA_PROJECT_KEY:-}" ]] && { echo "ERROR: JIRA_PROJECT_KEY not in config.sh — run: bash scripts/credentials/service.sh jira add" >&2; exit 1; }

STORY_ID="$1"   # e.g. VOR-29600

SLUG=$(service_slug jira "https://$JIRA_HOST")
_JIRA_PASS=$(require_secret "$SLUG" "$JIRA_USER" "bash scripts/credentials/service.sh jira add") || exit 1

# Create sub-task
curl -s -u "$JIRA_USER:$_JIRA_PASS" \
  -X POST \
  -H "Content-Type: application/json" \
  "https://$JIRA_HOST/rest/api/2/issue" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"$JIRA_PROJECT_KEY\"},
      \"parent\": {\"key\": \"$STORY_ID\"},
      \"issuetype\": {\"name\": \"Sub-task\"},
      \"summary\": \"<task title>\",
      \"description\": \"<task description>\\nBranch: <branch-name>\"
    }
  }" > /tmp/_jira_subtask.json
unset _JIRA_PASS

# Extract created sub-task ID
python3 -c "import json; d=json.load(open('/tmp/_jira_subtask.json')); print(d['key'])"
```
````

- [ ] **Step 2: Verify the file no longer contains hardcoded values**

```bash
grep -E "vivotek|hero\.hsu|VOR" skills/create-story-tasks/SKILL.md
```

Expected output: empty (no hardcoded refs). Note: example mentions like `VOR-29600` in the file's prose are fine if they're labelled as examples — search above is for code references. If you find any literal `VOR` outside example narrative, replace with `<STORY-ID>` placeholder.

- [ ] **Step 3: Verify lib.sh helpers are referenced**

```bash
grep -E "load_config|service_slug|require_secret" skills/create-story-tasks/SKILL.md | wc -l
```

Expected output: at least `3`.

- [ ] **Step 4: Commit**

```bash
git add skills/create-story-tasks/SKILL.md
git commit -m "refactor: create-story-tasks uses lib.sh helpers + JIRA_PROJECT_KEY

Reads JIRA_HOST, JIRA_USER, JIRA_PROJECT_KEY from config.sh instead
of hardcoding 'vivotek' and 'VOR'.
"
```

---

### Task 17: uninstall.sh — read installed.txt for offline uninstall

Replace network-dependent github skill enumeration with a simple file read.

**Files:**
- Modify: `scripts/_lib.sh:uninstall_github_skill`
- Modify: `scripts/uninstall.sh`

- [ ] **Step 1: Replace uninstall_github_skill in _lib.sh**

In `scripts/_lib.sh`, replace the entire `uninstall_github_skill()` function with:

```bash
# uninstall_github_skill <owner/repo> <skills-subpath> <target_dir>
# Reads ~/.agent-skills-setup/installed.txt to know which skills to remove.
# Falls back to network re-fetch only if installed.txt is missing.
uninstall_github_skill() {
  local repo="$1" subpath="$2" target_dir="$3"
  local list="$HOME/.agent-skills-setup/installed.txt"

  if [[ -f "$list" ]]; then
    local count=0
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      if [[ -d "$target_dir/$skill_name" || -L "$target_dir/$skill_name" ]]; then
        remove_skill "$skill_name" "$target_dir"
        count=$((count + 1))
      fi
    done < "$list"
    echo "  ✓ $repo ($count skills removed via installed.txt)"
    return 0
  fi

  # Fallback: network path (legacy behavior preserved for safety)
  echo "  WARNING: $list missing — falling back to network re-fetch" >&2
  local reponame="${repo##*/}"
  local zip extract branch_dir
  zip=$(mktemp /tmp/agent-skills-XXXXXX.zip)
  extract=$(mktemp -d /tmp/agent-skills-extract-XXXXXX)

  download_file "https://github.com/${repo}/archive/refs/heads/main.zip" "$zip" || {
    echo "  WARNING: could not fetch $repo; skipping uninstall." >&2
    rm -f "$zip"; rm -rf "$extract"; return 0
  }
  unzip -q "$zip" -d "$extract"
  rm -f "$zip"

  branch_dir=$(find "$extract" -maxdepth 1 -type d -name "${reponame}-*" | head -1)
  local src_dir="${branch_dir}/${subpath}"
  local count=0
  if [[ -d "$src_dir" ]]; then
    for skill_dir in "$src_dir"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      remove_skill "$skill_name" "$target_dir"
      count=$((count + 1))
    done
  fi
  rm -rf "$extract"
  echo "  ✓ $repo ($count skills removed via fallback)"
}
```

- [ ] **Step 2: Verify offline uninstall works**

Simulate offline by pointing to a non-resolvable host (no actual network disable needed):

```bash
# First make sure installed.txt exists
ls -l ~/.agent-skills-setup/installed.txt
```

Expected: a file exists (created by Task 8's install run). Run:

```bash
bash scripts/uninstall.sh --agent claude 2>&1 | grep "skills removed"
```

Expected output: lines like `✓ obra/superpowers (N skills removed via installed.txt)`.

- [ ] **Step 3: Re-install for subsequent tasks**

```bash
bash scripts/install.sh --agent claude > /dev/null
```

- [ ] **Step 4: Add `--agent` flag to uninstall.sh too (parity with install.sh)**

In `scripts/uninstall.sh`, after the `source ... _lib.sh` line, add:

```bash
AGENT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT_ARG="$2"; shift 2 ;;
    --agent=*)  AGENT_ARG="${1#*=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

select_agents "$AGENT_ARG"
```

Remove the standalone `select_agents` call below.

- [ ] **Step 5: Verify --agent flag works**

```bash
bash scripts/uninstall.sh --agent claude 2>&1 | head -3
```

Expected output: no interactive prompt; uninstall proceeds for claude only.

- [ ] **Step 6: Re-install one more time**

```bash
bash scripts/install.sh --agent claude > /dev/null
```

- [ ] **Step 7: Commit**

```bash
git add scripts/_lib.sh scripts/uninstall.sh
git commit -m "feat: offline uninstall via installed.txt; uninstall.sh --agent flag

Removes the network re-fetch path from the happy case. Falls back to
network only if installed.txt is missing.
"
```

---

### Task 18: install.ps1 — mirror lib copy, migration, installed.txt

Bring Windows install to parity. Same logic as install.sh, translated to PowerShell.

**Files:**
- Modify: `scripts/install.ps1`

- [ ] **Step 1: Add Install-RuntimeDir function**

In `scripts/install.ps1`, before the `# Main:` block (around line 128), add:

```powershell
# ---------------------------------------------------------------------------
# Cross-agent runtime dir
# ---------------------------------------------------------------------------
function Install-RuntimeDir {
    $rtDir = Join-Path $env:USERPROFILE '.agent-skills-setup'
    New-Item -ItemType Directory -Path $rtDir -Force | Out-Null
    Copy-Item (Join-Path $RepoDir 'lib\lib.sh') (Join-Path $rtDir 'lib.sh') -Force
    Copy-Item (Join-Path $RepoDir 'scripts\credentials\_store.sh') (Join-Path $rtDir '_store.sh') -Force
    Write-Host "  v runtime -> $rtDir"
}

function Invoke-KeychainMigration {
    # Windows: best-effort. Lists cmdkey entries with old prefix and warns user.
    $found = cmdkey /list 2>$null | Select-String 'agent-skills:'
    if ($found) {
        Write-Warning "Found credentials with 'agent-skills:' prefix. Re-run setup-credentials.ps1 for each service to migrate to 'agent-skills-setup:'."
    }
}

function Initialize-InstalledList {
    $script:InstalledList = Join-Path $env:USERPROFILE '.agent-skills-setup\installed.txt'
    Set-Content -Path $script:InstalledList -Value '' -Force
}

function Add-InstalledSkill([string]$Name) {
    if ($script:InstalledList) {
        Add-Content -Path $script:InstalledList -Value $Name
    }
}

function Install-KiroPrompts {
    $target = Join-Path $env:USERPROFILE '.kiro\prompts'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $count = 0
    foreach ($f in Get-ChildItem (Join-Path $RepoDir 'prompts') -Filter '*.md' -ErrorAction SilentlyContinue) {
        Copy-Item $f.FullName (Join-Path $target $f.Name) -Force
        $count++
    }
    Write-Host "  v kiro prompts ($count files) -> $target"
}
```

- [ ] **Step 2: Call new functions from main block**

Find the line `Write-Host "`n==> Installing skills from registry.txt..."` (around line 130). Replace it with:

```powershell
Write-Host "`n==> Installing runtime helpers..."
Install-RuntimeDir

Write-Host "`n==> Migrating keychain entries (if any)..."
Invoke-KeychainMigration

Initialize-InstalledList

Write-Host "`n==> Installing skills from registry.txt..."
```

- [ ] **Step 3: Make Install-LocalSkill and Install-GithubSkill record installs**

In `Install-LocalSkill`, after `Write-Host "  v $SkillName (local)"`, add:

```powershell
    Add-InstalledSkill $SkillName
```

In `Install-GithubSkill`, inside the `foreach ($skillDir in Get-ChildItem $srcDir -Directory)` loop, after `$count++`, add:

```powershell
        Add-InstalledSkill $skillDir.Name
```

- [ ] **Step 4: Add Install-KiroPrompts call after the main install loop**

After the closing `}` of the outer `foreach ($agentName in $SelectedAgents)` block, add:

```powershell

# Install Kiro prompts if kiro was selected
if ($SelectedAgents -contains 'kiro') {
    Install-KiroPrompts
}
```

- [ ] **Step 5: Verify on macOS that the .ps1 is at least syntactically valid**

(We can't run PowerShell tests on macOS without pwsh installed. Visually scan the diff:)

```bash
git diff scripts/install.ps1 | head -100
```

Expected: clean PowerShell syntax, no obvious typos. If `pwsh` is available locally, run:

```bash
command -v pwsh && pwsh -NoProfile -Command "Get-Content scripts/install.ps1 | Out-Null; Write-Host 'parsed OK'"
```

Expected output (if pwsh available): `parsed OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/install.ps1
git commit -m "feat: install.ps1 parity — runtime dir, migration, installed.txt, kiro prompts

Mirrors the install.sh changes. Runtime files land at
%USERPROFILE%\.agent-skills-setup\.
"
```

---

### Task 19: End-to-end smoke verification

Run the four manual smoke tests from the spec to confirm nothing is broken.

**Files:**
- (No file changes — verification only)

- [ ] **Step 1: Fresh-install smoke test**

```bash
[ -d ~/.agent-skills-setup ] && mv ~/.agent-skills-setup ~/.agent-skills-setup.bak
bash scripts/install.sh --agent claude
```

Then:

```bash
ls ~/.agent-skills-setup/
```

Expected output (one per line): `_store.sh`, `installed.txt`, `lib.sh`, possibly `config.sh` if you had one before backup. Restore the backup if needed:

```bash
[ -d ~/.agent-skills-setup.bak ] && {
  cp ~/.agent-skills-setup.bak/config.sh ~/.agent-skills-setup/config.sh 2>/dev/null
  rm -rf ~/.agent-skills-setup.bak
}
```

- [ ] **Step 2: Lib loads correctly from installed location**

```bash
bash -c 'source ~/.agent-skills-setup/lib.sh && slugify_url https://example.com && service_slug confluence https://example.com && find_html2md'
```

Expected output (3 lines):
```
https---example-com
confluence-https---example-com
/Users/.../<some agent dir>/fetch-page-to-markdown/html2md.py
```

- [ ] **Step 3: Migration synthetic test**

```bash
security add-generic-password -s "agent-skills:smoke-test" -a "smoke-user" -w "smoke-pw" 2>/dev/null || true
bash scripts/install.sh --agent claude 2>&1 | grep "migrated"
```

Expected: shows `✓ migrated 1 keychain entries: agent-skills: → agent-skills-setup:` (or similar).

Verify and clean up:

```bash
security find-generic-password -s "agent-skills-setup:smoke-test" -a "smoke-user" -w
security delete-generic-password -s "agent-skills-setup:smoke-test" -a "smoke-user" 2>/dev/null
```

Expected: first command outputs `smoke-pw`; second deletes silently.

- [ ] **Step 4: Run actual fetch-jira-story end-to-end (optional, requires real Jira creds)**

Only run if your existing creds are migrated. From the project root:

```bash
# This is not idempotent — only run if you can clean up the resulting docs/stories/ dir afterward.
echo "Skipped — run manually with a real Jira ticket if desired:"
echo "  Create a test agent invocation that runs the fetch-jira-story flow."
```

Just confirm the SKILL.md is sourced correctly:

```bash
bash -c 'source ~/.agent-skills-setup/lib.sh && load_config && echo "JIRA_HOST=${JIRA_HOST:-<unset>}, JIRA_USER=${JIRA_USER:-<unset>}, JIRA_PROJECT_KEY=${JIRA_PROJECT_KEY:-<unset>}"'
```

Expected output (with your real values): `JIRA_HOST=vivotek.atlassian.net, JIRA_USER=hero.hsu@vivotek.com, JIRA_PROJECT_KEY=VOR`.

If any of these are `<unset>`, run `bash scripts/credentials/service.sh jira add` once.

- [ ] **Step 5: Offline-uninstall smoke test**

```bash
bash scripts/uninstall.sh --agent claude 2>&1 | tail -5
```

Expected output: lines including `✓ ... (N skills removed via installed.txt)` for each registry entry. No `WARNING: ... falling back to network re-fetch` lines.

Re-install:

```bash
bash scripts/install.sh --agent claude > /dev/null
```

- [ ] **Step 6: Final checklist**

Confirm all of these:

- [ ] `~/.agent-skills-setup/{lib.sh,_store.sh,installed.txt}` exist
- [ ] `~/.agent-skills-setup/config.sh` populated (run `cat` on it)
- [ ] No `agent-skills:*` (old prefix) keychain entries remain — verify with `security dump-keychain 2>/dev/null | grep -c '"svce"<blob>="agent-skills:'`. Expected: `0`.
- [ ] Three SKILL.md files contain zero hardcoded `vivotek`/`hero.hsu` strings — verify with `grep -E 'vivotek|hero\.hsu' skills/*/SKILL.md`. Expected: empty.
- [ ] `bash scripts/install.sh --agent claude` runs end-to-end without errors.
- [ ] `bash scripts/credentials/service.sh confluence verify` shows `✓ Credential found` (assuming real creds are configured).

- [ ] **Step 7: Commit final notes (only if any verification revealed an issue and required a fix)**

If any step required a fix, that fix should have been committed already as part of its task. This step is a no-op if all verifications passed.

---

## Summary

After completing all 19 tasks:

- `~/.agent-skills-setup/` is the cross-agent runtime layer, holding `lib.sh`, `_store.sh`, `config.sh`, `installed.txt`.
- Three SKILL.md files reference user values via `${JIRA_HOST}` etc., no hardcoded `vivotek` or `hero.hsu`.
- Slug rule and html2md detection live in exactly one place.
- Three credential scripts are 4-line shims; logic lives in one `service.sh`.
- Keychain prefix is `agent-skills-setup:`; old `agent-skills:*` entries auto-migrate.
- `install.sh --agent claude` is non-interactive.
- `uninstall.sh` works offline via `installed.txt`.
- `install.ps1` is at parity (lib copy, migration, installed.txt, kiro prompts).
