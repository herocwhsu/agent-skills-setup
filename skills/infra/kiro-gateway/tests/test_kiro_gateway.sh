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

# remove-codex: rc file whose ONLY content is the codex-kiro block (no orphan tmp)
remove_codex_only_content_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"
  local rc="$tmpdir/.zshrc"
  touch "$rc"
  # Run setup-codex so the rc contains ONLY the codex-kiro comment+alias
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="test-key" \
    bash "$SCRIPT" setup-codex >/dev/null 2>&1 || true
  # Now remove-codex: rc content is exactly those lines (grep -v produces empty output)
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" \
    SHELL="/bin/zsh" HOME="$tmpdir" \
    bash "$SCRIPT" remove-codex >/dev/null 2>&1 || true
  local alias_gone tmp_gone
  alias_gone=true; tmp_gone=true
  grep -Fq "codex-kiro" "$rc" 2>/dev/null && alias_gone=false
  [[ -f "$rc.tmp" ]] && tmp_gone=false
  if $alias_gone && $tmp_gone; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (alias_gone=$alias_gone tmp_gone=$tmp_gone)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
remove_codex_only_content_test "remove-codex: empty-result grep leaves no orphan tmp file"

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

# patch: tracked fix patch exists and targets the role field
patch_exists_test() {
  local name="$1"
  local patch
  patch="$(cd "$(dirname "$0")/.." && pwd)/patches/kiro-gateway-system-role.patch"
  if [[ -f "$patch" ]] && grep -Fq "models_anthropic.py" "$patch" && grep -Eq 'role' "$patch"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (patch missing or wrong target: $patch)"; FAIL=$((FAIL+1))
  fi
}
patch_exists_test "fix patch exists and targets role field"

# build-path: KIRO_GATEWAY_DIR pointing at a git checkout creates a symlink
resolve_symlink_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local target="$tmpdir/realrepo"; mkdir -p "$target/.git"
  HOME="$tmpdir" KIRO_GATEWAY_DIR="$target" \
    bash "$SCRIPT" __resolve_build_path >/dev/null 2>&1 || true
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  if [[ -L "$canon" && "$(readlink "$canon")" == "$target" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (canon=$canon link=$(readlink "$canon" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
resolve_symlink_test "resolve: existing checkout becomes a symlink"

# build-path: a real dir with content at canonical refuses to clobber
resolve_refuse_clobber_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon"; echo x > "$canon/file"
  local target="$tmpdir/realrepo"; mkdir -p "$target/.git"
  local code=0
  HOME="$tmpdir" KIRO_GATEWAY_DIR="$target" \
    bash "$SCRIPT" __resolve_build_path >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 && -e "$canon/file" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (code=$code)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
resolve_refuse_clobber_test "resolve: refuses to clobber a real canonical dir"

# build-path: non-git target fails without leaving a dangling link
resolve_nongit_fails_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local target="$tmpdir/notrepo"; mkdir -p "$target"
  local code=0
  HOME="$tmpdir" KIRO_GATEWAY_DIR="$target" \
    bash "$SCRIPT" __resolve_build_path >/dev/null 2>&1 || code=$?
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  if [[ "$code" -ne 0 && ! -e "$canon" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (code=$code, canon exists=$([[ -e "$canon" ]] && echo yes || echo no))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
resolve_nongit_fails_test "resolve: non-git target fails without dangling link"

# fix-guard: passes when role: str already present
fix_guard_present_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"
  printf 'class Message:\n    role: str\n' > "$canon/kiro/models_anthropic.py"
  local code=0
  HOME="$tmpdir" CANONICAL_DIR="$canon" \
    bash "$SCRIPT" __fix_guard >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (code=$code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
fix_guard_present_test "fix-guard passes when role:str present"

# fix-guard: a field starting with "str" but not `str` (e.g. role: strict) must
# NOT false-positive as the fix — treated as unfixed, must abort (no git repo
# here → patch cannot apply → non-zero).
fix_guard_no_false_positive_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"
  printf 'class Message:\n    role: strict_enum\n' > "$canon/kiro/models_anthropic.py"
  local code=0
  HOME="$tmpdir" CANONICAL_DIR="$canon" \
    bash "$SCRIPT" __fix_guard >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (role: strict_enum false-positived as fixed)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
fix_guard_no_false_positive_test "fix-guard does not false-positive on role: strict"

# fix-guard: aborts when the field is strict and no applicable patch
fix_guard_aborts_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"
  printf 'class Message:\n    role: Literal["user", "assistant"]\n' > "$canon/kiro/models_anthropic.py"
  # No git repo in canon → patch cannot apply cleanly → must abort non-zero
  local code=0
  HOME="$tmpdir" CANONICAL_DIR="$canon" \
    bash "$SCRIPT" __fix_guard >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected non-zero, got 0)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
fix_guard_aborts_test "fix-guard aborts when fix cannot be applied"

# Adds mock `docker` and `git` that record calls, so build/run logic is testable
# without a daemon. `git rev-parse --short HEAD` returns a fixed sha.
make_docker_git_mocks() {
  local dir="$1" sha="$2"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$dir/docker.calls"
case "\$1" in
  inspect) exit 1 ;;   # container/image absent
  build|run|stop|rm|start|logs) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$dir/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"rev-parse --short HEAD"* ]]; then echo "$sha"; exit 0; fi
echo "git \$*" >> "$dir/git.calls"
exit 0
EOF
  chmod +x "$dir/bin/docker" "$dir/bin/git"
}

# init: builds a SHA-tagged image and records current=<sha>
init_builds_sha_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"; printf '    role: str\n' > "$canon/kiro/models_anthropic.py"
  # macOS data dir must exist for start_container's guard
  mkdir -p "$tmpdir/Library/Application Support/kiro-cli"
  make_docker_git_mocks "$tmpdir" "abc1234"
  local state="$tmpdir/state"
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" CANONICAL_DIR="$canon" \
    KIRO_GATEWAY_STATE_FILE="$state" KIRO_GATEWAY_DIR="" SKIP_HEALTH_PROBE=1 \
    bash "$SCRIPT" init >/dev/null 2>&1 || true
  if grep -q "build -t kiro-gateway:abc1234" "$tmpdir/docker.calls" 2>/dev/null \
     && grep -q "current=abc1234" "$state" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (calls=$(cat "$tmpdir/docker.calls" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
init_builds_sha_test "init builds SHA-tagged image and records current"

# rollback: fails loud when previous image absent from host
rollback_missing_image_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_docker_git_mocks "$tmpdir" "abc1234"
  local state="$tmpdir/state"; printf 'current=new123\nprevious=old999\n' > "$state"
  # docker inspect returns 1 (image absent) via the mock → rollback must die
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    KIRO_GATEWAY_STATE_FILE="$state" \
    bash "$SCRIPT" rollback >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected non-zero)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
rollback_missing_image_test "rollback fails loud when previous image absent"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
