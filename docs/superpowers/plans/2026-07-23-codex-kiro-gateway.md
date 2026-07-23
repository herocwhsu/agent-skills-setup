# codex-kiro Gateway Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `setup-codex` / `remove-codex` subcommands to `kiro-gateway.sh` so OpenAI's Codex CLI routes through the existing kiro-gateway container, mirroring `claude-kiro`.

**Architecture:** Extend the single `kiro-gateway.sh` script. Extract two shared helpers (`rc_file_path`, `store_proxy_key`) from the existing `setup-alias` code, then reuse them in `setup-codex`. Codex config lives in an isolated `~/.codex-kiro/config.toml` (via `CODEX_HOME`) that we fully own, never touching the unrelated tool already in `~/.codex`.

**Tech Stack:** Bash, macOS `security` / Linux `secret-tool` keychain, TOML config, the existing no-bats shell test runner.

## Global Constraints

- Config home is isolated: `~/.codex-kiro/` via `CODEX_HOME`. Never edit `~/.codex/config.toml`.
- `wire_api = "chat"` is mandatory — the gateway 404s on `/v1/responses`.
- Default model: `claude-opus-4.8` (confirmed working via passthrough, though absent from `/v1/models`).
- Proxy key is read from keychain at runtime; never write a plaintext token to a shell rc file (keychain service `agent-skills-setup:kiro-gateway`, account `proxy-key`).
- Config/alias are written even when the `codex` binary is absent; print the install hint (`npm i -g @openai/codex`) and exit 0.
- New tests MUST mock `security` (prepend a fake to PATH) so the real keychain is never written.
- Match the existing script style: `cmd_*` functions, `die()` for errors, `set -euo pipefail`.

---

## File Structure

- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` — add helpers + 2 subcommands, extend `status` and dispatch.
- Modify: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh` — add test functions.
- Modify: `skills/infra/kiro-gateway/IMPL.md`, `skills/infra/kiro-gateway/README.md`, `skills/infra/SKILL.md` — docs.

---

### Task 1: Extract helpers + fix keychain-clobbering tests

Two coupled changes: (a) extract the rc-file and keychain logic from
`cmd_setup_alias` into reusable helpers that `setup-codex` (Task 2) will
consume; (b) fix the existing `setup-alias` tests, which currently invoke the
**real** `security` binary — writing `test-key` over the real proxy key and
popping a macOS auth dialog on every run. Both tests must mock `security` and
assert against the macOS code path (the current `grep KIRO_PROXY_KEY` assertion
only ever matched the headless-Linux fallback).

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh`
- Modify: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Produces: `rc_file_path()` — echoes the rc file path based on `$SHELL`/OS. `store_proxy_key()` — stores `$KIRO_PROXY_KEY` (or prompts) into keychain and echoes the runtime read-command string on stdout; human notes go to stderr. `make_mock_bin()` (test helper) — prepends a fake `security` to PATH so tests never touch the real keychain.

- [ ] **Step 1: Run the existing suite to observe the failing baseline**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `Results: 5 passed, 1 failed` — the failure is `setup-alias writes alias and key to rc file` with a `security: ... authorization was canceled by the user` message (or, if you click Allow, it silently overwrites your real keychain key — do NOT click Allow). This task makes the suite green without touching the real keychain.

- [ ] **Step 2: Add the two helpers**

Insert after the `container_status()` helper (near line 46), before the subcommands section:

```bash
rc_file_path() {
  case "${SHELL:-}" in
    */zsh)  echo "$HOME/.zshrc" ;;
    */bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.bashrc"
      fi
      ;;
    *) echo "$HOME/.zshrc" ;;
  esac
}

# Stores the proxy key in the OS keychain (or headless fallback) and echoes the
# shell snippet that reads it back at runtime. Notes go to stderr so stdout is
# exactly the read command.
store_proxy_key() {
  local proxy_key="${KIRO_PROXY_KEY:-}"
  if [[ -z "$proxy_key" ]]; then
    read -rp "KIRO_PROXY_KEY value (leave blank for 'kiro-local'): " proxy_key
    proxy_key="${proxy_key:-kiro-local}"
  fi

  if command -v security &>/dev/null; then
    security delete-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" >/dev/null 2>&1 || true
    security add-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w "$proxy_key"
    echo '$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null)'
  elif command -v secret-tool &>/dev/null; then
    echo -n "$proxy_key" | secret-tool store --label="kiro-gateway proxy-key" \
      service "agent-skills-setup:kiro-gateway" username "proxy-key"
    echo '$(secret-tool lookup service "agent-skills-setup:kiro-gateway" username "proxy-key" 2>/dev/null)'
  else
    echo "export KIRO_PROXY_KEY=${proxy_key}" >> "$HOME/.zshrc.local"
    echo "  Note: no keychain available — token written to ~/.zshrc.local (headless fallback)" >&2
    echo "\${KIRO_PROXY_KEY}"
  fi
}
```

- [ ] **Step 3: Rewire `cmd_setup_alias` to use the helpers**

Replace the entire existing `cmd_setup_alias()` body (lines ~160-214) with:

```bash
cmd_setup_alias() {
  local rc_file
  rc_file=$(rc_file_path)

  if grep -Fq "claude-kiro" "$rc_file" 2>/dev/null; then
    echo "claude-kiro alias already present in $rc_file"
    return 0
  fi

  local read_cmd
  read_cmd=$(store_proxy_key)

  {
    echo ""
    echo "# kiro-gateway"
    echo "alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} claude'"
    echo "alias hermes-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} hermes --provider anthropic --model claude-sonnet-4-6'"
  } >> "$rc_file"

  echo "Token stored in keychain. Added to $rc_file:"
  echo "  alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ...'"
  echo "  alias hermes-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ...'"
  echo ""
  echo "Activate now: source $rc_file"
  echo "Then launch Claude Code via: claude-kiro"
}
```

- [ ] **Step 4: Add the `make_mock_bin` test helper**

Add after the `expect_exit` helper (near line 41 of the test file):

```bash
# Prepend a fake `security` so tests never touch the real keychain.
make_mock_bin() {
  local dir="$1"
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/security"
  chmod +x "$dir/bin/security"
}
```

- [ ] **Step 5: Rewrite the two `setup-alias` tests to mock security and assert the macOS path**

The current tests call the real `security` (clobbering the keychain, popping a dialog) and assert `grep KIRO_PROXY_KEY`, which only ever matched the headless-Linux fallback. Replace `setup_alias_test` (lines ~51-72) and keep `setup_alias_idempotent_test` but add mocking. Replace both function bodies + their call lines with:

```bash
# setup-alias: writes alias to a temp rc file (mock security, assert macOS path)
setup_alias_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  touch "$rc"
  local actual
  actual=$(PATH="$tmpdir/bin:$PATH" \
           KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
           SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
           bash "$SCRIPT" setup-alias 2>&1 || true)
  if grep -q "claude-kiro" "$rc" && grep -q "agent-skills-setup:kiro-gateway" "$rc"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rc file missing alias; output: $actual)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_alias_test "setup-alias writes alias and key to rc file"

# setup-alias: idempotent — does not add duplicate
setup_alias_idempotent_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  echo "alias claude-kiro='already here'" > "$rc"
  local actual
  actual=$(PATH="$tmpdir/bin:$PATH" \
           KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
           SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
           bash "$SCRIPT" setup-alias 2>&1 || true)
  local count
  count=$(grep -c "claude-kiro" "$rc")
  if [[ "$count" -eq 1 ]] && echo "$actual" | grep -q "already present"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (count=$count, output: $actual)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_alias_idempotent_test "setup-alias is idempotent"
```

- [ ] **Step 6: Run the suite — green with no keychain dialog**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `Results: 6 passed, 0 failed`, and NO macOS keychain dialog appears during the run.

- [ ] **Step 7: Verify the real keychain key is untouched**

Run: `security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w | wc -c`
Expected: `33` (32-char key + newline), NOT `9` (which would mean `test-key` clobbered it)

- [ ] **Step 8: Commit**

```bash
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "refactor: extract rc/keychain helpers and mock security in tests"
```

---

### Task 2: Add `setup-codex` subcommand

Writes the isolated Codex config and the `codex-kiro` alias; handles idempotency and the missing-binary case.

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh`
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `rc_file_path()`, `store_proxy_key()` from Task 1.
- Produces: `cmd_setup_codex()` — writes `$HOME/.codex-kiro/config.toml` and appends the `codex-kiro` alias to the rc file; dispatched via `setup-codex`.

- [ ] **Step 1: Write the first failing test**

The `make_mock_bin` helper already exists in the test file (added in Task 1). Add this test function before the final `echo ""` results block:

```bash
# setup-codex: writes config.toml with provider + profile
setup_codex_config_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  touch "$tmpdir/.zshrc"
  local cfg="$tmpdir/.codex-kiro/config.toml"
  PATH="$tmpdir/bin:$PATH" \
    KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
    bash "$SCRIPT" setup-codex >/dev/null 2>&1 || true
  if [[ -f "$cfg" ]] \
     && grep -Fq "[model_providers.kiro]" "$cfg" \
     && grep -Fq 'wire_api = "chat"' "$cfg" \
     && grep -Fq 'model = "claude-opus-4.8"' "$cfg"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (config missing/incorrect at $cfg)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_codex_config_test "setup-codex writes correct config.toml"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `FAIL: setup-codex writes correct config.toml` (subcommand unknown → no config written)

- [ ] **Step 3: Add `cmd_setup_codex`**

Insert after `cmd_setup_alias()`:

```bash
cmd_setup_codex() {
  local codex_home="$HOME/.codex-kiro"
  local config_file="$codex_home/config.toml"
  local rc_file
  rc_file=$(rc_file_path)

  local read_cmd
  read_cmd=$(store_proxy_key)

  mkdir -p "$codex_home"
  if grep -Fq "[model_providers.kiro]" "$config_file" 2>/dev/null; then
    echo "codex-kiro config already present in $config_file"
  else
    cat > "$config_file" <<'EOF'
[model_providers.kiro]
name = "Kiro Gateway"
base_url = "http://localhost:7788/v1"
env_key = "KIRO_PROXY_KEY"
wire_api = "chat"

[profiles.kiro]
model = "claude-opus-4.8"
model_provider = "kiro"
EOF
    echo "Wrote $config_file"
  fi

  if grep -Fq "alias codex-kiro" "$rc_file" 2>/dev/null; then
    echo "codex-kiro alias already present in $rc_file"
  else
    {
      echo ""
      echo "# kiro-gateway (codex)"
      echo "alias codex-kiro='CODEX_HOME=\"\$HOME/.codex-kiro\" KIRO_PROXY_KEY=${read_cmd} codex --profile kiro'"
    } >> "$rc_file"
    echo "Added codex-kiro alias to $rc_file"
  fi

  if ! command -v codex &>/dev/null; then
    echo ""
    echo "Note: codex not found. Install it with:"
    echo "  npm i -g @openai/codex"
  fi
  echo ""
  echo "Activate now: source $rc_file"
  echo "Then launch Codex via the gateway: codex-kiro"
}
```

- [ ] **Step 4: Wire the dispatch case**

In the `case "${1:-}"` block, add after the `setup-alias)` line and update the error usage string:

```bash
  setup-codex)   cmd_setup_codex ;;
```

Change the `*)` line to:

```bash
  *)             die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status | setup-alias | setup-codex" ;;
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `PASS: setup-codex writes correct config.toml`

- [ ] **Step 6: Add alias, idempotency, and missing-codex tests**

Add before the results block:

```bash
# setup-codex: appends the codex-kiro alias
setup_codex_alias_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  touch "$rc"
  PATH="$tmpdir/bin:$PATH" \
    KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
    bash "$SCRIPT" setup-codex >/dev/null 2>&1 || true
  if grep -Fq "alias codex-kiro" "$rc" && grep -Fq "CODEX_HOME" "$rc"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (alias not written to rc)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_codex_alias_test "setup-codex appends codex-kiro alias"

# setup-codex: idempotent — no duplicate config block or alias
setup_codex_idempotent_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  touch "$rc"
  local out
  for _ in 1 2; do
    out=$(PATH="$tmpdir/bin:$PATH" \
      KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
      SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
      bash "$SCRIPT" setup-codex 2>&1 || true)
  done
  local prov_count alias_count
  prov_count=$(grep -cF "[model_providers.kiro]" "$tmpdir/.codex-kiro/config.toml")
  alias_count=$(grep -cF "alias codex-kiro" "$rc")
  if [[ "$prov_count" -eq 1 && "$alias_count" -eq 1 ]] && echo "$out" | grep -q "already present"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (prov=$prov_count alias=$alias_count out=$out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_codex_idempotent_test "setup-codex is idempotent"

# setup-codex: missing codex binary still writes config + prints install hint
setup_codex_missing_binary_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  touch "$tmpdir/.zshrc"
  # PATH has ONLY the mock bin dir + coreutils; codex is absent by construction
  local out
  out=$(PATH="$tmpdir/bin:/usr/bin:/bin" \
    KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
    bash "$SCRIPT" setup-codex 2>&1 || true)
  if [[ -f "$tmpdir/.codex-kiro/config.toml" ]] && echo "$out" | grep -q "npm i -g @openai/codex"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (out=$out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_codex_missing_binary_test "setup-codex handles missing codex binary"
```

- [ ] **Step 7: Run the suite**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: all new PASS lines; failed count `0`

- [ ] **Step 8: Commit**

```bash
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add setup-codex subcommand to kiro-gateway"
```

---

### Task 3: Add `remove-codex` subcommand

Teardown: strip the alias (and its comment) from the rc file and delete the isolated config dir.

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh`
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `rc_file_path()` from Task 1.
- Produces: `cmd_remove_codex()` — dispatched via `remove-codex`.

- [ ] **Step 1: Write the failing test**

Add before the results block:

```bash
# remove-codex: strips alias and deletes the config dir
remove_codex_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  touch "$rc"
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
    bash "$SCRIPT" setup-codex >/dev/null 2>&1 || true
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" \
    bash "$SCRIPT" remove-codex >/dev/null 2>&1 || true
  if ! grep -Fq "codex-kiro" "$rc" && [[ ! -d "$tmpdir/.codex-kiro" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (alias or dir still present)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
remove_codex_test "remove-codex strips alias and deletes dir"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `FAIL: remove-codex strips alias and deletes dir` (unknown subcommand)

- [ ] **Step 3: Add `cmd_remove_codex`**

Insert after `cmd_setup_codex()`:

```bash
cmd_remove_codex() {
  local codex_home="$HOME/.codex-kiro"
  local rc_file
  rc_file=$(rc_file_path)

  if [[ -f "$rc_file" ]] && grep -Fq "codex-kiro" "$rc_file"; then
    grep -v -e "alias codex-kiro" -e "kiro-gateway (codex)" "$rc_file" > "$rc_file.tmp" \
      && mv "$rc_file.tmp" "$rc_file"
    echo "Removed codex-kiro alias from $rc_file"
  else
    echo "No codex-kiro alias found in $rc_file"
  fi

  if [[ -d "$codex_home" ]]; then
    rm -rf "$codex_home"
    echo "Removed $codex_home"
  else
    echo "No $codex_home directory to remove"
  fi
}
```

- [ ] **Step 4: Wire the dispatch case**

Add after the `setup-codex)` line and update the usage string:

```bash
  remove-codex)  cmd_remove_codex ;;
```

Change the `*)` line to:

```bash
  *)             die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status | setup-alias | setup-codex | remove-codex" ;;
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `PASS: remove-codex strips alias and deletes dir`

- [ ] **Step 6: Commit**

```bash
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add remove-codex subcommand to kiro-gateway"
```

---

### Task 4: Report codex status in `status`

One line in `status`, printed independent of gateway state and docker so it works in CI without docker.

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh`
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `cmd_status` prints `Codex:      configured (~/.codex-kiro)` or `Codex:      not configured`.

- [ ] **Step 1: Write the failing test**

Add before the results block:

```bash
# status: reports codex configured after setup, independent of docker/state
status_codex_configured_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.codex-kiro"
  printf '[model_providers.kiro]\n' > "$tmpdir/.codex-kiro/config.toml"
  local out
  out=$(KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" HOME="$tmpdir" \
    bash "$SCRIPT" status 2>&1 || true)
  if echo "$out" | grep -q "Codex:      configured"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (out=$out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
status_codex_configured_test "status reports codex configured"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `FAIL: status reports codex configured` (no Codex line yet)

- [ ] **Step 3: Add the codex line at the top of `cmd_status`**

Insert as the first lines inside `cmd_status()`, before the `if [[ ! -f "$STATE_FILE" ]]` check:

```bash
  if [[ -f "$HOME/.codex-kiro/config.toml" ]] \
     && grep -Fq "[model_providers.kiro]" "$HOME/.codex-kiro/config.toml" 2>/dev/null; then
    echo "Codex:      configured (~/.codex-kiro)"
  else
    echo "Codex:      not configured"
  fi
```

- [ ] **Step 4: Run the suite**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `PASS: status reports codex configured`, and the existing `status no state file shows no state` test still passes; failed count `0`

- [ ] **Step 5: Commit**

```bash
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: report codex-kiro status in kiro-gateway status"
```

---

### Task 5: Update documentation

**Files:**
- Modify: `skills/infra/kiro-gateway/IMPL.md`
- Modify: `skills/infra/kiro-gateway/README.md`
- Modify: `skills/infra/SKILL.md`

- [ ] **Step 1: Update `IMPL.md`**

In the frontmatter `description`, append `setup-codex` and `remove-codex` to the subcommand list. In the "Usage" bullet list add:

```markdown
- "Set up codex-kiro" → runs `setup-codex`
- "Remove codex-kiro" → runs `remove-codex`
```

In the Subcommands table add two rows:

```markdown
| `setup-codex` | Write `~/.codex-kiro/config.toml` (isolated `CODEX_HOME`) + `codex-kiro` alias. Checks for `codex` binary. Idempotent. |
| `remove-codex` | Remove the `codex-kiro` alias and the `~/.codex-kiro` dir. |
```

- [ ] **Step 2: Update `README.md`**

Add a section after "The claude-kiro alias":

````markdown
## The codex-kiro alias

`codex-kiro` launches OpenAI's Codex CLI against the gateway using an isolated
config home so it never collides with anything already in `~/.codex`:

```bash
alias codex-kiro='CODEX_HOME="$HOME/.codex-kiro" KIRO_PROXY_KEY=$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null) codex --profile kiro'
```

Set it up with:

```bash
bash ~/.claude/skills/infra/kiro-gateway/lib/kiro-gateway.sh setup-codex
source ~/.zshrc
```

This writes `~/.codex-kiro/config.toml`:

```toml
[model_providers.kiro]
name = "Kiro Gateway"
base_url = "http://localhost:7788/v1"
env_key = "KIRO_PROXY_KEY"
wire_api = "chat"

[profiles.kiro]
model = "claude-opus-4.8"
model_provider = "kiro"
```

`wire_api = "chat"` is required — the gateway serves OpenAI Chat Completions,
not the Responses API. Override the model per run: `codex-kiro -m claude-sonnet-4.6`.

If `codex` isn't installed, `setup-codex` still writes the config and prints
`npm i -g @openai/codex`. Remove everything with `remove-codex`.

Smoke test once installed:

```bash
codex-kiro exec "reply with OK"
```
````

- [ ] **Step 3: Update `infra/SKILL.md`**

In the `/infra-kiro-gateway` row of the Subcommands table, extend the sub-subcommand list to include `setup-codex`, `remove-codex`. Add to the "When to use which subcommand" block:

```
Route OpenAI Codex CLI through the gateway → /infra-kiro-gateway setup-codex
Undo the codex-kiro setup → /infra-kiro-gateway remove-codex
```

- [ ] **Step 4: Commit**

```bash
git add skills/infra/kiro-gateway/IMPL.md skills/infra/kiro-gateway/README.md skills/infra/SKILL.md
git commit -m "docs: document codex-kiro setup in kiro-gateway"
```

---

## Notes / Known Issues

- Task 1 fixes the pre-existing bug where `setup-alias` tests called the real `security` (clobbering the real keychain key and popping a macOS auth dialog). All tests now mock `security` via `make_mock_bin`. The old `grep KIRO_PROXY_KEY` assertion only matched the headless-Linux fallback; it is replaced with `grep agent-skills-setup:kiro-gateway`, which matches the macOS keychain-read code path.
- End-to-end verification requires installing Codex CLI (`npm i -g @openai/codex`), then running the documented smoke test. Not automatable in this repo's test suite.
