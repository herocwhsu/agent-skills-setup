#!/usr/bin/env bash
# Minimal test runner — no bats dependency.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/lib/kiro-gateway.sh"
PASS=0
FAIL=0

expect_output() {
  local name="$1" expected="$2"
  shift 2
  local tmpdir
  tmpdir=$(mktemp -d)
  local actual
  actual=$(KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" bash "$SCRIPT" "$@" 2>&1 || true)
  if echo "$actual" | grep -qF "$expected"; then
    echo "PASS: $name"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

expect_exit() {
  local name="$1" expected_code="$2"
  shift 2
  local tmpdir
  tmpdir=$(mktemp -d)
  local actual_code=0
  KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" bash "$SCRIPT" "$@" >/dev/null 2>&1 || actual_code=$?
  if [[ "$actual_code" == "$expected_code" ]]; then
    echo "PASS: $name"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected exit $expected_code, got $actual_code)"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

# Prepend a fake `security` so tests never touch the real keychain.
make_mock_bin() {
  local dir="$1"
  mkdir -p "$dir/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/security"
  chmod +x "$dir/bin/security"
}

# --- tests ---

expect_output "status no state file shows no state" "no state file" status
expect_output "rollback no previous exits with message" "no previous version" rollback
expect_exit   "rollback no previous exits 1" 1 rollback
expect_exit   "unknown subcommand exits 1" 1 unknown-cmd

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
