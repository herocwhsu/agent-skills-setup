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

# Regression: setup-alias must NOT overwrite an already-stored proxy key. It
# calls store_proxy_key only for the read-back snippet; the buggy version
# unconditionally delete+add, so with no KIRO_PROXY_KEY and closed stdin the
# read hit EOF and stored the 'kiro-local' default — silently breaking auth
# against a gateway built with the real key. Stateful security mock holds a
# real key; assert it is unchanged after setup-alias. Fails on buggy code.
setup_alias_preserves_key_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/security" <<EOF
#!/usr/bin/env bash
KF="$tmpdir/kc"
case "\$1" in
  find-generic-password) if [[ -f "\$KF" ]]; then cat "\$KF"; else exit 44; fi ;;
  add-generic-password) p=""; for a in "\$@"; do [[ "\$p" == "-w" ]] && printf '%s' "\$a" > "\$KF"; p="\$a"; done ;;
  delete-generic-password) rm -f "\$KF" ;;
esac
exit 0
EOF
  chmod +x "$tmpdir/bin/security"
  printf 'REAL-32-char-key-aaaaaaaaaaaaaaaa' > "$tmpdir/kc"   # preexisting good key
  local before after
  before=$(cat "$tmpdir/kc")
  # NO KIRO_PROXY_KEY; closed stdin so the prompt (if reached) hits EOF.
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" SHELL="/bin/zsh" \
    KIRO_GATEWAY_STATE_FILE="$tmpdir/state" \
    bash "$SCRIPT" setup-alias >/dev/null 2>&1 </dev/null || true
  after=$(cat "$tmpdir/kc")
  if [[ "$before" == "$after" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (key changed: '$after')"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
setup_alias_preserves_key_test "setup-alias preserves an existing proxy key (no clobber)"

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
  if [[ "$prov_count" -eq 1 && "$alias_count" -eq 1 ]]; then
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
  # mock security so cmd_init's render_env_file never touches the real keychain
  cat > "$tmpdir/bin/security" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"find-generic-password"*"-w"*) echo "test-key-123" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmpdir/bin/security"
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

# init with a REAL-docker-style absent container: `docker inspect` prints a
# blank line to stdout AND exits 1 when the container is missing. container_status
# must still resolve to "absent" (not "\nabsent") so init reaches the build branch.
init_realdocker_absent_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"; printf '    role: str\n' > "$canon/kiro/models_anthropic.py"
  mkdir -p "$tmpdir/Library/Application Support/kiro-cli" "$tmpdir/bin"
  # docker mock: inspect prints a BLANK line to stdout and exits 1 (real 29.x behavior)
  cat > "$tmpdir/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$tmpdir/docker.calls"
case "\$1" in
  inspect) echo ""; exit 1 ;;
  build|run|stop|rm|start|logs) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$tmpdir/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"rev-parse --short HEAD"* ]]; then echo "def5678"; exit 0; fi
exit 0
EOF
  cat > "$tmpdir/bin/security" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"find-generic-password"*"-w"*) echo "k";; *) exit 0;; esac
EOF
  chmod +x "$tmpdir/bin/docker" "$tmpdir/bin/git" "$tmpdir/bin/security"
  local state="$tmpdir/state"
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" CANONICAL_DIR="$canon" \
    KIRO_GATEWAY_STATE_FILE="$state" KIRO_GATEWAY_DIR="" SKIP_HEALTH_PROBE=1 \
    bash "$SCRIPT" init >/dev/null 2>&1 || true
  # must have reached the build branch (built def5678) and recorded it
  if grep -q "build -t kiro-gateway:def5678" "$tmpdir/docker.calls" 2>/dev/null \
     && grep -q "current=def5678" "$state" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (did not reach build branch: calls=$(cat "$tmpdir/docker.calls" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
init_realdocker_absent_test "init handles real-docker absent (blank stdout + exit 1)"

# Regression (C1): a FRESH init (no prior 'previous' sha) must EXIT 0 and must
# actually RUN the health probe. write_state's last command is a conditional
# echo that returns 1 when previous is empty; as cmd_init's last statement
# before health_probe, a non-zero return aborts init under set -e — silently
# skipping the probe (the branch's core verification) on every new build. This
# test does NOT set SKIP_HEALTH_PROBE and asserts init exit 0 + probe ran (curl
# mock touches a sentinel). Fails on buggy code (init exits 1, sentinel absent).
init_fresh_exits_zero_and_probes_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"; printf '    role: str\n' > "$canon/kiro/models_anthropic.py"
  mkdir -p "$tmpdir/Library/Application Support/kiro-cli"
  make_docker_git_mocks "$tmpdir" "abc1234"
  cat > "$tmpdir/bin/security" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"find-generic-password"*"-w"*) echo "test-key-123";; *) exit 0;; esac
EOF
  # curl mock: prove the probe ran by touching a sentinel, then report HTTP 200.
  cat > "$tmpdir/bin/curl" <<EOF
#!/usr/bin/env bash
touch "$tmpdir/probe.ran"
echo -n 200
EOF
  chmod +x "$tmpdir/bin/security" "$tmpdir/bin/curl"
  local state="$tmpdir/state" code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" CANONICAL_DIR="$canon" \
    KIRO_GATEWAY_STATE_FILE="$state" KIRO_GATEWAY_DIR="" \
    HEALTH_PROBE_RETRIES=2 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" init >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]] && [[ -f "$tmpdir/probe.ran" ]] \
     && grep -q "current=abc1234" "$state" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (init exit=$code, probe.ran=$([[ -f "$tmpdir/probe.ran" ]] && echo yes || echo no))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
init_fresh_exits_zero_and_probes_test "fresh init exits 0 and runs the health probe"

# Regression (I1): render_env_file must reach its store-and-retry fallback when
# the keychain is EMPTY. `security find-generic-password -w` exits 44 when the
# item is absent; a bare key="$(read_proxy_key)" inherits that under set -e and
# aborts BEFORE the fallback can store+reread. Stateful security mock: find
# exits 44 until add-generic-password stores a key. With KIRO_PROXY_KEY set, the
# fallback stores non-interactively. Fixed code writes the key; buggy code
# aborts and writes no env file.
render_env_empty_keychain_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin" "$tmpdir/Library/Application Support/kiro-cli"
  cat > "$tmpdir/bin/security" <<EOF
#!/usr/bin/env bash
KEYFILE="$tmpdir/kc.key"
case "\$1" in
  find-generic-password)
    if [[ "\$*" == *"-w"* ]]; then
      if [[ -f "\$KEYFILE" ]]; then cat "\$KEYFILE"; exit 0; else exit 44; fi
    fi
    exit 0 ;;
  add-generic-password)
    prev=""; for a in "\$@"; do [[ "\$prev" == "-w" ]] && printf '%s' "\$a" > "\$KEYFILE"; prev="\$a"; done
    exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmpdir/bin/security"
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" KIRO_PROXY_KEY="bootstrap-key" \
    bash "$SCRIPT" __render_env >/dev/null 2>&1 || true
  local envf="$tmpdir/.env.kiro-gateway"
  if [[ -f "$envf" ]] && grep -q "^PROXY_API_KEY=bootstrap-key$" "$envf"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (env missing or key not stored: $(cat "$envf" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
render_env_empty_keychain_test "render_env_file bootstraps from empty keychain (no set -e abort)"

# init idempotency: on an ALREADY-RUNNING container, init must NOT rebuild and
# must NOT rewrite state (else state.current drifts from the live image).
init_running_noop_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$canon/kiro"; printf '    role: str\n' > "$canon/kiro/models_anthropic.py"
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$tmpdir/docker.calls"
case "\$1" in
  inspect) echo "running"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
  cat > "$tmpdir/bin/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"rev-parse --short HEAD"* ]]; then echo "new999"; exit 0; fi
exit 0
EOF
  chmod +x "$tmpdir/bin/docker" "$tmpdir/bin/git"
  local state="$tmpdir/state"; printf 'current=old111\n' > "$state"
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" CANONICAL_DIR="$canon" \
    KIRO_GATEWAY_STATE_FILE="$state" KIRO_GATEWAY_DIR="" SKIP_HEALTH_PROBE=1 \
    bash "$SCRIPT" init >/dev/null 2>&1 || true
  if ! grep -q "build -t" "$tmpdir/docker.calls" 2>/dev/null \
     && grep -q "current=old111" "$state" 2>/dev/null \
     && ! grep -q "new999" "$state" 2>/dev/null; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (rebuilt or rewrote state: calls=$(cat "$tmpdir/docker.calls" 2>/dev/null) state=$(cat "$state" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
init_running_noop_test "init on running container does not rebuild or rewrite state"

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

# render_env_file writes a chmod 600 file containing the proxy key
render_env_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"   # mock security (exit 0)
  # mock security to echo a key on find-generic-password -w
  cat > "$tmpdir/bin/security" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"find-generic-password"*"-w"*) echo "test-key-123" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmpdir/bin/security"
  mkdir -p "$tmpdir/Library/Application Support/kiro-cli"
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    bash "$SCRIPT" __render_env >/dev/null 2>&1 || true
  local envf="$tmpdir/.env.kiro-gateway"
  local perm; perm=$(stat -f '%Lp' "$envf" 2>/dev/null || stat -c '%a' "$envf" 2>/dev/null)
  # Assert the exact UNQUOTED line (docker --env-file keeps literal quotes, so a
  # quoted value would be a bug). `^PROXY_API_KEY=test-key-123$` fails if quoted.
  # KIRO_CLI_DB_FILE must be the CONTAINER path (where the data dir is mounted),
  # never the host path — the host path exists nowhere in the container and the
  # app crash-loops with "No Kiro credentials". The `! grep host-path` clause is
  # the discriminating assertion that catches that regression.
  if [[ -f "$envf" ]] && grep -q "^PROXY_API_KEY=test-key-123$" "$envf" \
     && grep -q "^FIRST_TOKEN_TIMEOUT=120$" "$envf" \
     && grep -q "^KIRO_CLI_DB_FILE=/home/kiro/.local/share/kiro-cli/data.sqlite3$" "$envf" \
     && ! grep -q "^KIRO_CLI_DB_FILE=$tmpdir" "$envf" \
     && [[ "$perm" == "600" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (perm=$perm content=$(cat "$envf" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
render_env_test "render_env_file writes chmod 600 env with key"

# health_probe: mocks curl (emulates -w '%{http_code}' -o /dev/null) and docker
make_curl_mock() {
  local dir="$1" code="$2"
  mkdir -p "$dir/bin"
  cat > "$dir/bin/curl" <<EOF
#!/usr/bin/env bash
# emulate -w '%{http_code}' -o /dev/null
echo -n "$code"
EOF
  chmod +x "$dir/bin/curl"
  cat > "$dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$dir/bin/docker"
}

health_probe_200_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_curl_mock "$tmpdir" "200"
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    HEALTH_PROBE_RETRIES=2 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (code=$code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_200_test "health probe passes on HTTP 200"

health_probe_422_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_curl_mock "$tmpdir" "422"
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    HEALTH_PROBE_RETRIES=2 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected non-zero)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_422_test "health probe fails on non-200"

# readiness race: curl returns 000 (connection refused) repeatedly, then the
# probe must retry and finally die non-zero after the window — NOT die on the
# first 000. Uses a tiny window so the test is instant.
health_probe_retries_then_fails_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  printf '#!/usr/bin/env bash\necho -n 000\n' > "$tmpdir/bin/curl"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/docker"
  chmod +x "$tmpdir/bin/curl" "$tmpdir/bin/docker"
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    HEALTH_PROBE_RETRIES=3 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected non-zero after retries)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_retries_then_fails_test "health probe retries on 000 then fails after window"

# readiness race success: curl returns 000 twice, then 200 — probe must retry
# through the 000s and succeed (exit 0), proving polling works end-to-end.
health_probe_eventual_200_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/curl" <<EOF
#!/usr/bin/env bash
n=\$(cat "$tmpdir/n" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "$tmpdir/n"
if [[ "\$n" -ge 3 ]]; then echo -n 200; else echo -n 000; fi
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/docker"
  chmod +x "$tmpdir/bin/curl" "$tmpdir/bin/docker"
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    HEALTH_PROBE_RETRIES=5 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected success after eventual 200)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_eventual_200_test "health probe succeeds when server ready after initial 000s"

# Regression: real curl EXITS NON-ZERO (7) on connection-refused while still
# printing 000. Under `set -e`, a bare `code=$(curl ...)` inherits that exit
# and kills the script on the FIRST probe — before any retry, sleep, or echo
# (the observed silent `init` exit-1). Prior 000 mocks all `exit 0`, so they
# never caught this. Mock: exit 7 (prints 000) twice, then 200 (exit 0). Buggy
# code dies before reaching 200; fixed code retries through and exits 0.
health_probe_curl_nonzero_exit_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/curl" <<EOF
#!/usr/bin/env bash
n=\$(cat "$tmpdir/n" 2>/dev/null || echo 0); n=\$((n+1)); echo "\$n" > "$tmpdir/n"
if [[ "\$n" -ge 3 ]]; then echo -n 200; exit 0; else echo -n 000; exit 7; fi
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmpdir/bin/docker"
  chmod +x "$tmpdir/bin/curl" "$tmpdir/bin/docker"
  local code=0
  PATH="$tmpdir/bin:/usr/bin:/bin" HOME="$tmpdir" \
    HEALTH_PROBE_RETRIES=5 HEALTH_PROBE_INTERVAL=0 \
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (curl exit-7 killed probe before retry; code=$code)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_curl_nonzero_exit_test "health probe survives curl non-zero exit (connection refused) and retries"

# managed block: changing a definition updates in place (not duplicate, not stale)
managed_update_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"; local rc="$tmpdir/.zshrc"
  printf 'export FOO=1\n' > "$rc"   # pre-existing unrelated content
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="k" \
    bash "$SCRIPT" setup-alias >/dev/null 2>&1 || true
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="k" \
    bash "$SCRIPT" setup-alias >/dev/null 2>&1 || true
  local blocks aliases foo
  blocks=$(grep -c ">>> agent-skills-setup kiro-gateway >>>" "$rc")
  aliases=$(grep -c "alias claude-kiro" "$rc")
  foo=$(grep -c "export FOO=1" "$rc")
  if [[ "$blocks" -eq 1 && "$aliases" -eq 1 && "$foo" -eq 1 ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (blocks=$blocks aliases=$aliases foo=$foo)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
managed_update_test "managed block updates in place, preserves surrounding lines"

# remove-codex: drops only codex line; if block empties, whole block removed
remove_codex_empties_block_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  make_mock_bin "$tmpdir"; local rc="$tmpdir/.zshrc"; touch "$rc"
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/state" \
    SHELL="/bin/zsh" HOME="$tmpdir" KIRO_PROXY_KEY="k" \
    bash "$SCRIPT" setup-codex >/dev/null 2>&1 || true
  PATH="$tmpdir/bin:$PATH" KIRO_GATEWAY_STATE_FILE="$tmpdir/state" \
    SHELL="/bin/zsh" HOME="$tmpdir" \
    bash "$SCRIPT" remove-codex >/dev/null 2>&1 || true
  if ! grep -q "codex-kiro" "$rc" && ! grep -q "agent-skills-setup kiro-gateway" "$rc"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (residue in rc)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
remove_codex_empties_block_test "remove-codex empties and removes the block"

# status: reports build path (symlinked checkout) and image tag from state
status_build_path_test() {
  local name="$1"; local tmpdir; tmpdir=$(mktemp -d)
  local canon="$tmpdir/.agent-skills-setup/kiro-gateway"
  mkdir -p "$tmpdir/.agent-skills-setup"
  local target="$tmpdir/realrepo"; mkdir -p "$target/.git"; ln -s "$target" "$canon"
  local state="$tmpdir/state"; printf 'current=abc1234\n' > "$state"
  local out
  out=$(KIRO_GATEWAY_STATE_FILE="$state" HOME="$tmpdir" CANONICAL_DIR="$canon" \
    bash "$SCRIPT" status 2>&1 || true)
  if echo "$out" | grep -q "Build path: linked" && echo "$out" | grep -q "kiro-gateway:abc1234"; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (out=$out)"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
status_build_path_test "status reports build path and image tag"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
