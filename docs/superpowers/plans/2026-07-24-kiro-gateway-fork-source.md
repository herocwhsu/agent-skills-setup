# kiro-gateway Fork-Source Reproducible Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the `infra/kiro-gateway` skill so it builds the gateway image from the user's fork (which carries the `role: str` 422 fix), verifies that fix on every build, corrects the container mount, keeps SHA-tagged rollback, and reconciles `~/.zshrc` aliases via a managed block.

**Architecture:** Extend the existing single-script skill `lib/kiro-gateway.sh`. Replace the upstream-image pull path with a fork clone/symlink + local `docker build` tagged by git short SHA. Add a fix-guard (assert `role: str`, re-apply a tracked patch if missing) and a post-start HTTP 200 health probe. Replace `grep && skip` alias logic with a sentinel-delimited managed block. All state stays in `~/.agent-skills-setup/kiro-gateway.state`.

**Tech Stack:** Bash (`set -euo pipefail`), Docker, git, `shellcheck`, macOS keychain (`security`) / `secret-tool`, the repo's plain-bash test runner.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-24-kiro-gateway-fork-source-design.md`.
- Canonical build path: `~/.agent-skills-setup/kiro-gateway` (a dir when cloned, a symlink when reusing a checkout). Override answer via `KIRO_GATEWAY_DIR`.
- Fork remote: `git@github.com:herocwhsu/kiro-gateway.git`. Required fix commit: `5b4b873` (`role: str` in `kiro/models_anthropic.py`).
- Container run must match the working `kg-up`: `-p 127.0.0.1:7788:8000`, mount `<kiro-data-dir>:/home/kiro/.local/share/kiro-cli:ro`, `--env-file ~/.env.kiro-gateway`, `-v ~/kiro-gateway-logs:/app/debug_logs`, entry `python main.py`, `--restart unless-stopped`.
- kiro-data-dir: macOS `~/Library/Application Support/kiro-cli`, Linux `~/.local/share/kiro-cli` (existing `kiro_data_dir()`).
- Local image tag: `kiro-gateway:<git-short-sha>`. State keys: `current=<sha>`, `previous=<sha>`.
- No secret value committed to the repo. `~/.env.kiro-gateway` rendered at `chmod 600`.
- Managed-block sentinels: `# >>> agent-skills-setup kiro-gateway >>>` / `# <<< agent-skills-setup kiro-gateway <<<`.
- Tests: plain bash, no bats; `mktemp -d` sandboxes; mock `security`; assert via PASS/FAIL counters; whole file exits non-zero if any fail. Docker-dependent behavior must be unit-tested without a real daemon (mock `docker` and `git` on PATH), and any test needing a real daemon gated behind `RUN_INTEGRATION=1`.

---

### Task 1: Generate the tracked fix patch

**Files:**
- Create: `skills/infra/kiro-gateway/patches/kiro-gateway-system-role.patch`
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh` (add one case)

**Interfaces:**
- Consumes: nothing.
- Produces: a patch file that, applied at the root of a kiro-gateway checkout, changes `role: Literal["user", "assistant"]` to `role: str` in `kiro/models_anthropic.py`. Used by Task 3's fix-guard.

- [ ] **Step 1: Generate the patch from the fork commit**

Run (uses the working checkout on this host; adjust the `-C` path if your clone is elsewhere):

```bash
cd ~/Project/agent-skills-setup
mkdir -p skills/infra/kiro-gateway/patches
git -C ~/Project/kiro-gateway format-patch -1 5b4b873 \
  -- kiro/models_anthropic.py \
  --stdout > skills/infra/kiro-gateway/patches/kiro-gateway-system-role.patch
```

- [ ] **Step 2: Verify the patch targets the right line**

Run: `grep -E 'role|models_anthropic' skills/infra/kiro-gateway/patches/kiro-gateway-system-role.patch`
Expected: a diff hunk for `kiro/models_anthropic.py` turning the `Literal["user", "assistant"]` role into `role: str`.

- [ ] **Step 3: Write a test asserting the patch exists and mentions the field**

Add to `tests/test_kiro_gateway.sh` before the final results block:

```bash
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: line `PASS: fix patch exists and targets role field`, final `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/infra/kiro-gateway/patches/kiro-gateway-system-role.patch skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add tracked system-role fix patch for kiro-gateway"
```

---

### Task 2: Build-path resolution (clone-or-symlink to canonical path)

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (add constants + `resolve_build_path`)
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `resolve_build_path()` — ensures `$CANONICAL_DIR` (default `$HOME/.agent-skills-setup/kiro-gateway`) resolves to a kiro-gateway checkout, returns 0 on success. Reads `KIRO_GATEWAY_DIR` (non-interactive answer) or prompts. `build_path()` echoes the canonical path. Both used by Tasks 3–6.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_kiro_gateway.sh`:

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: three `FAIL:` lines for the resolve cases (subcommand `__resolve_build_path` unknown → exit 1, but assertions on symlink/refusal fail).

- [ ] **Step 3: Add constants and the resolver**

In `lib/kiro-gateway.sh`, after the existing constants (near line 9), add:

```bash
FORK_REMOTE="git@github.com:herocwhsu/kiro-gateway.git"
CANONICAL_DIR="${CANONICAL_DIR:-$HOME/.agent-skills-setup/kiro-gateway}"
```

Add these functions after the helpers section:

```bash
build_path() { echo "$CANONICAL_DIR"; }

# Expand a leading ~ to $HOME and make absolute.
_expand_path() {
  local p="$1"
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in
    /*) echo "$p" ;;
    *)  echo "$PWD/$p" ;;
  esac
}

_is_git_repo() { [[ -d "$1/.git" ]] || git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

# Ensure $CANONICAL_DIR resolves to a kiro-gateway checkout.
# KIRO_GATEWAY_DIR (if set) is the non-interactive answer; blank prompt = clone.
resolve_build_path() {
  mkdir -p "$(dirname "$CANONICAL_DIR")"

  local answer="${KIRO_GATEWAY_DIR-__UNSET__}"
  if [[ "$answer" == "__UNSET__" ]]; then
    read -rp "Path to an existing kiro-gateway checkout (blank = clone fresh): " answer
  fi

  if [[ -n "$answer" ]]; then
    local target; target="$(_expand_path "$answer")"
    _is_git_repo "$target" || die "Not a git checkout: $target"
    if [[ -L "$CANONICAL_DIR" ]]; then
      rm -f "$CANONICAL_DIR"
    elif [[ -e "$CANONICAL_DIR" ]]; then
      die "Refusing to overwrite existing $CANONICAL_DIR — remove it or unset KIRO_GATEWAY_DIR."
    fi
    ln -s "$target" "$CANONICAL_DIR"
    local remote; remote="$(git -C "$target" remote get-url origin 2>/dev/null || true)"
    [[ "$remote" == *herocwhsu/kiro-gateway* ]] || echo "Note: $target origin is '$remote' (not herocwhsu/kiro-gateway) — using it anyway." >&2
    echo "Linked $CANONICAL_DIR -> $target"
    return 0
  fi

  if _is_git_repo "$CANONICAL_DIR"; then
    echo "Using existing clone at $CANONICAL_DIR"
    return 0
  fi
  if [[ -e "$CANONICAL_DIR" && ! -L "$CANONICAL_DIR" ]]; then
    die "Refusing to overwrite existing $CANONICAL_DIR — remove it first."
  fi
  require_git
  echo "Cloning $FORK_REMOTE -> $CANONICAL_DIR"
  git clone "$FORK_REMOTE" "$CANONICAL_DIR"
}

require_git() { command -v git &>/dev/null || die "git not found."; }
```

Add a hidden dispatch case (for tests) in the `case` block near the bottom:

```bash
  __resolve_build_path) resolve_build_path ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: the three resolve cases now `PASS`; final `0 failed`.

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add clone-or-symlink build-path resolution to kiro-gateway"
```

---

### Task 3: Fix-guard

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (add `fix_guard`)
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `build_path()` (Task 2), the patch from Task 1.
- Produces: `fix_guard()` — asserts `role: str` in `$(build_path)/kiro/models_anthropic.py`; if absent, applies the tracked patch; aborts (die) if the patch fails. Returns 0 when the fix is present. Used by Task 4's build.

- [ ] **Step 1: Write the failing tests**

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: both `fix-guard` cases FAIL (`__fix_guard` unknown → exit 1; present-case expected 0).

- [ ] **Step 3: Implement `fix_guard`**

Add to `lib/kiro-gateway.sh`:

```bash
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$LIB_DIR/../patches/kiro-gateway-system-role.patch"

fix_guard() {
  local repo; repo="$(build_path)"
  local model="$repo/kiro/models_anthropic.py"
  [[ -f "$model" ]] || die "Cannot find $model — is the build path a kiro-gateway checkout?"

  if grep -Eq '^\s*role:\s*str' "$model"; then
    echo "Fix-guard: role:str present."
    return 0
  fi

  echo "Fix-guard: strict role type detected — applying tracked patch..."
  [[ -f "$PATCH_FILE" ]] || die "Fix patch missing: $PATCH_FILE"
  if git -C "$repo" apply --check "$PATCH_FILE" 2>/dev/null; then
    git -C "$repo" apply "$PATCH_FILE"
  else
    die "Fix patch will not apply cleanly to $repo — aborting before build. Resolve manually."
  fi
  grep -Eq '^\s*role:\s*str' "$model" || die "Fix-guard: role:str still absent after patch — aborting."
  echo "Fix-guard: patch applied."
}
```

Add dispatch case:

```bash
  __fix_guard) fix_guard ;;
```

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: both fix-guard cases `PASS`; final `0 failed`.

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add fix-guard asserting role:str before build"
```

---

### Task 4: Local SHA-tagged build; rewire init/update/rollback

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (replace `cmd_init`, `cmd_update`, `cmd_rollback`, `start_container`; drop `resolve_digest`/`IMAGE_BASE` pull path)
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `resolve_build_path`/`build_path` (Task 2), `fix_guard` (Task 3), `kiro_data_dir` (existing), state helpers (existing).
- Produces: `build_image()` → echoes `<short-sha>` and builds `kiro-gateway:<sha>`; `start_container "<sha>"`; `cmd_init`/`cmd_update`/`cmd_rollback` operating on SHA tags. Health probe is added in Task 6 (init calls a `health_probe` stub here, defined in Task 6).

- [ ] **Step 1: Write the failing tests (mock docker + git on PATH)**

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: both new cases FAIL (init still uses upstream pull; rollback re-runs without image check).

- [ ] **Step 3: Replace the build/run/lifecycle functions**

In `lib/kiro-gateway.sh`, delete `resolve_digest()` and the `IMAGE_BASE` constant. Replace `start_container`, `cmd_init`, `cmd_update`, `cmd_rollback` with:

```bash
image_exists() { docker image inspect "kiro-gateway:$1" >/dev/null 2>&1; }

build_image() {
  local repo; repo="$(build_path)"
  local sha; sha="$(git -C "$repo" rev-parse --short HEAD)"
  [[ -n "$sha" ]] || die "Could not resolve git SHA in $repo"
  docker build -t "kiro-gateway:$sha" "$repo" >&2
  echo "$sha"
}

start_container() {
  local sha="$1"
  local data_dir; data_dir=$(kiro_data_dir)
  [[ -d "$data_dir" ]] || die "kiro data dir not found: $data_dir. Run Kiro CLI once, then retry."
  mkdir -p "$HOME/kiro-gateway-logs"; chmod 755 "$HOME/kiro-gateway-logs"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    --env-file "$HOME/.env.kiro-gateway" \
    -v "${data_dir}:/home/kiro/.local/share/kiro-cli:ro" \
    -v "$HOME/kiro-gateway-logs:/app/debug_logs" \
    "kiro-gateway:$sha" \
    python main.py
  echo "Started $CONTAINER_NAME (kiro-gateway:$sha)"
}

cmd_init() {
  require_docker
  resolve_build_path
  fix_guard
  render_env_file
  local sha; sha="$(build_image)"
  local state; state=$(container_status)
  case "$state" in
    running) echo "$CONTAINER_NAME already running." ;;
    exited|created|paused) docker start "$CONTAINER_NAME" ;;
    absent) start_container "$sha" ;;
    *) die "Unexpected container state: $state" ;;
  esac
  write_state "$sha" "$(read_state previous)"
  [[ "${SKIP_HEALTH_PROBE:-0}" == "1" ]] || health_probe
}

cmd_update() {
  require_docker
  resolve_build_path
  local repo; repo="$(build_path)"
  git -C "$repo" pull --ff-only >&2 || die "git pull failed in $repo"
  fix_guard
  local new_sha; new_sha="$(build_image)"
  local current; current=$(read_state current)
  if [[ "$new_sha" == "$current" ]] && image_exists "$new_sha"; then
    echo "Already up to date: kiro-gateway:$new_sha"; return 0
  fi
  if [[ "$(container_status)" != "absent" ]]; then
    docker stop "$CONTAINER_NAME"; docker rm "$CONTAINER_NAME"
  fi
  start_container "$new_sha"
  write_state "$new_sha" "${current:-}"
  [[ "${SKIP_HEALTH_PROBE:-0}" == "1" ]] || health_probe
}

cmd_rollback() {
  local previous; previous=$(read_state previous)
  [[ -n "$previous" ]] || die "no previous version recorded."
  require_docker
  image_exists "$previous" || die "previous image kiro-gateway:$previous not present on this host — cannot roll back."
  local current; current=$(read_state current)
  echo "Rolling back: $current -> $previous"
  if [[ "$(container_status)" != "absent" ]]; then
    docker stop "$CONTAINER_NAME"; docker rm "$CONTAINER_NAME"
  fi
  start_container "$previous"
  write_state "$previous" "$current"
}
```

Add a temporary `health_probe`/`render_env_file` stub near the top of the subcommand section so this task runs standalone (Tasks 5–6 replace them):

```bash
render_env_file() { :; }   # replaced in Task 5
health_probe() { :; }      # replaced in Task 6
```

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `init builds SHA-tagged image...` and `rollback fails loud...` both PASS; existing tests still PASS; final `0 failed`.

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: build kiro-gateway from fork with SHA-tagged images and rollback"
```

---

### Task 5: Render `~/.env.kiro-gateway` from keychain; ship example

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (replace `render_env_file` stub)
- Create: `skills/infra/kiro-gateway/config/.env.kiro-gateway.example`
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `store_proxy_key()` (existing — stores key, echoes read command) and the keychain value it stored.
- Produces: `render_env_file()` — writes `$HOME/.env.kiro-gateway` at `chmod 600` containing `PROXY_API_KEY=<value>` plus the SQLite DB path. Called by `cmd_init`/`cmd_update`.

- [ ] **Step 1: Create the example file (no secrets)**

`config/.env.kiro-gateway.example`:

```bash
# Copy to ~/.env.kiro-gateway (chmod 600). Rendered automatically by
# `kiro-gateway init` from the keychain entry agent-skills-setup:kiro-gateway.
PROXY_API_KEY="replace-with-your-proxy-key"
KIRO_CLI_DB_FILE="/Users/you/Library/Application Support/kiro-cli/data.sqlite3"
```

- [ ] **Step 2: Write the failing test**

```bash
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
  if [[ -f "$envf" ]] && grep -q "test-key-123" "$envf" && [[ "$perm" == "600" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (perm=$perm content=$(cat "$envf" 2>/dev/null))"; FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}
render_env_test "render_env_file writes chmod 600 env with key"
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `render_env_file...` FAILs (stub writes nothing; `__render_env` unknown).

- [ ] **Step 4: Replace the stub**

```bash
read_proxy_key() {
  if command -v security &>/dev/null; then
    security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null
  elif command -v secret-tool &>/dev/null; then
    secret-tool lookup service "agent-skills-setup:kiro-gateway" username "proxy-key" 2>/dev/null
  fi
}

render_env_file() {
  local key; key="$(read_proxy_key)"
  [[ -n "$key" ]] || { store_proxy_key >/dev/null; key="$(read_proxy_key)"; }
  local db; db="$(kiro_data_dir)/data.sqlite3"
  local envf="$HOME/.env.kiro-gateway"
  umask 077
  printf 'PROXY_API_KEY="%s"\nKIRO_CLI_DB_FILE="%s"\n' "$key" "$db" > "$envf"
  chmod 600 "$envf"
  echo "Rendered $envf (chmod 600)"
}
```

Add dispatch case: `__render_env) render_env_file ;;`

- [ ] **Step 5: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `render_env_file...` PASS; `0 failed`.

- [ ] **Step 6: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/config/.env.kiro-gateway.example skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: render ~/.env.kiro-gateway from keychain, add example template"
```

---

### Task 6: Health probe

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (replace `health_probe` stub)
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: nothing new; uses `curl` and the running container on `$HOST_PORT`.
- Produces: `health_probe()` — POSTs a system-role-in-`messages[]` payload to `http://127.0.0.1:7788/v1/messages`; returns 0 on HTTP 200, dies (after printing `docker logs` tail) otherwise. Called by `cmd_init`/`cmd_update` unless `SKIP_HEALTH_PROBE=1`.

- [ ] **Step 1: Write the failing tests (mock curl)**

```bash
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
    bash "$SCRIPT" __health_probe >/dev/null 2>&1 || code=$?
  if [[ "$code" -ne 0 ]]; then echo "PASS: $name"; PASS=$((PASS+1))
  else echo "FAIL: $name (expected non-zero)"; FAIL=$((FAIL+1)); fi
  rm -rf "$tmpdir"
}
health_probe_422_test "health probe fails on non-200"
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: both probe cases FAIL (stub returns 0 always; `__health_probe` unknown).

- [ ] **Step 3: Replace the stub**

```bash
health_probe() {
  command -v curl &>/dev/null || { echo "curl not found — skipping health probe." >&2; return 0; }
  local key; key="$(read_proxy_key)"
  local body='{"model":"claude-sonnet-4-20250514","max_tokens":16,"messages":[{"role":"user","content":"ping"},{"role":"system","content":"be terse"}]}'
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://${HOST_PORT}/v1/messages" \
    -H "content-type: application/json" \
    -H "x-api-key: ${key}" \
    -H "anthropic-version: 2023-06-01" \
    -d "$body" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "Health probe: HTTP 200 — system-role request accepted."
    return 0
  fi
  echo "Health probe FAILED: HTTP $code" >&2
  docker logs --tail 30 "$CONTAINER_NAME" 2>&1 | sed 's/^/  /' >&2 || true
  die "Gateway did not return 200 for a system-role request (got $code)."
}
```

Add dispatch case: `__health_probe) health_probe ;;`

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: both probe cases PASS; `0 failed`.

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add HTTP 200 health probe with system-role payload"
```

---

### Task 7: Managed zshrc block for setup-alias / setup-codex / remove-codex

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (rewrite `cmd_setup_alias`, `cmd_setup_codex`, `cmd_remove_codex`; add block helpers)
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh` (update idempotency expectations)

**Interfaces:**
- Consumes: `store_proxy_key()` (existing), `rc_file_path()` (existing).
- Produces: `write_managed_line "<alias-name>" "<full-line>"` (insert-or-update one line inside the sentinel block); `remove_managed_line "<alias-name>"`; block removed when it becomes empty. Sentinels per Global Constraints.

- [ ] **Step 1: Update/replace tests to assert update-in-place**

Replace the existing `setup_alias_idempotent_test` and add an update test:

```bash
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
```

Delete the old `setup_alias_idempotent_test` invocation and the `remove_codex_only_content_test` (superseded).

- [ ] **Step 2: Run to verify new tests fail**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `managed block updates...` and `remove-codex empties...` FAIL (current code appends, doesn't manage a block).

- [ ] **Step 3: Add block helpers and rewrite the three commands**

Add helpers:

```bash
BLOCK_START="# >>> agent-skills-setup kiro-gateway >>>"
BLOCK_END="# <<< agent-skills-setup kiro-gateway <<<"

# Read the current block body (lines between sentinels), if any.
_read_block() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    $0==s {inb=1; next} $0==e {inb=0; next} inb {print}' "$rc"
}

# Rewrite the rc file with a new block body (may be empty → block removed).
_write_block() {
  local rc="$1" body="$2" tmp
  tmp="$(mktemp)"
  # copy everything outside the block
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    $0==s {inb=1; next} $0==e {inb=0; next} !inb {print}' "$rc" 2>/dev/null > "$tmp"
  if [[ -n "$body" ]]; then
    { echo "$BLOCK_START"; printf '%s\n' "$body"; echo "$BLOCK_END"; } >> "$tmp"
  fi
  mv "$tmp" "$rc"
}

# Insert or update one alias line (keyed by alias name) within the block.
write_managed_line() {
  local rc="$1" key="$2" line="$3"
  touch "$rc"
  local body; body="$(_read_block "$rc")"
  local newbody=""
  local found=0
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    if [[ "$l" == *"alias $key="* ]]; then newbody+="$line"$'\n'; found=1
    else newbody+="$l"$'\n'; fi
  done <<< "$body"
  [[ "$found" -eq 0 ]] && newbody+="$line"$'\n'
  _write_block "$rc" "${newbody%$'\n'}"
}

remove_managed_line() {
  local rc="$1" key="$2"
  [[ -f "$rc" ]] || return 0
  local body; body="$(_read_block "$rc")"
  local newbody=""
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    [[ "$l" == *"alias $key="* ]] && continue
    newbody+="$l"$'\n'
  done <<< "$body"
  _write_block "$rc" "${newbody%$'\n'}"
}
```

Rewrite the commands:

```bash
cmd_setup_alias() {
  local rc; rc=$(rc_file_path)
  local read_cmd; read_cmd=$(store_proxy_key)
  write_managed_line "$rc" "claude-kiro" \
    "alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} claude'"
  write_managed_line "$rc" "hermes-kiro" \
    "alias hermes-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} hermes --provider anthropic --model claude-sonnet-4-6'"
  echo "Reconciled claude-kiro/hermes-kiro in $rc. Activate: source $rc"
}

cmd_setup_codex() {
  local codex_home="$HOME/.codex-kiro"
  local config_file="$codex_home/config.toml"
  local rc; rc=$(rc_file_path)
  local read_cmd; read_cmd=$(store_proxy_key)
  mkdir -p "$codex_home"
  if ! grep -Fq "[model_providers.kiro]" "$config_file" 2>/dev/null; then
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
  write_managed_line "$rc" "codex-kiro" \
    "alias codex-kiro='CODEX_HOME=\"\$HOME/.codex-kiro\" KIRO_PROXY_KEY=${read_cmd} codex --profile kiro'"
  command -v codex &>/dev/null || echo "Note: codex not found. Install: npm i -g @openai/codex"
  echo "Reconciled codex-kiro in $rc. Activate: source $rc"
}

cmd_remove_codex() {
  local codex_home="$HOME/.codex-kiro"
  local rc; rc=$(rc_file_path)
  remove_managed_line "$rc" "codex-kiro"
  echo "Removed codex-kiro from $rc"
  if [[ -d "$codex_home" ]]; then rm -rf "$codex_home"; echo "Removed $codex_home"; fi
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `managed block updates...`, `remove-codex empties...`, and the retained `setup-codex writes correct config.toml` / `setup-codex appends codex-kiro alias` cases PASS; `0 failed`.

- [ ] **Step 5: shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
git add skills/infra/kiro-gateway/lib/kiro-gateway.sh skills/infra/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: reconcile kiro-gateway aliases via managed zshrc block"
```

---

### Task 8: Update status + docs

**Files:**
- Modify: `skills/infra/kiro-gateway/lib/kiro-gateway.sh` (`cmd_status`: report build-path form + image tag; update dispatch usage string)
- Modify: `skills/infra/kiro-gateway/README.md` and `skills/infra/kiro-gateway/IMPL.md`
- Modify: `skills/infra/kiro-gateway/SKILL.md` (if present) — reflect fork-source
- Test: `skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`

**Interfaces:**
- Consumes: `build_path`, state helpers.
- Produces: `cmd_status` output lines `Build path: linked → <target>` or `Build path: cloned` and `Image: kiro-gateway:<current-sha>`.

- [ ] **Step 1: Write the failing test**

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `status reports build path...` FAILs.

- [ ] **Step 3: Extend `cmd_status`**

Add near the top of `cmd_status` (after the codex block, before the state-file check):

```bash
  if [[ -L "$CANONICAL_DIR" ]]; then
    echo "Build path: linked → $(readlink "$CANONICAL_DIR")"
  elif [[ -d "$CANONICAL_DIR" ]]; then
    echo "Build path: cloned ($CANONICAL_DIR)"
  else
    echo "Build path: not set up (run 'init')"
  fi
  local cur; cur=$(read_state current)
  [[ -n "$cur" ]] && echo "Image:      kiro-gateway:$cur"
```

Update the final `die` usage string to list the same subcommands (unchanged names).

- [ ] **Step 4: Run to verify pass**

Run: `bash skills/infra/kiro-gateway/tests/test_kiro_gateway.sh`
Expected: `status reports build path...` PASS; `0 failed`.

- [ ] **Step 5: Update README.md / IMPL.md prose**

Replace any "upstream `ghcr.io/jwadow`" / "digest-pinned" wording with: builds from the fork `herocwhsu/kiro-gateway`, SHA-tagged images, fix-guard, health probe, managed zshrc block, `KIRO_GATEWAY_DIR` reuse. Note `init` clones on first run.

- [ ] **Step 6: Full test run + shellcheck + commit**

```bash
shellcheck --severity=warning skills/infra/kiro-gateway/lib/kiro-gateway.sh
bash scripts/run-tests.sh --fast
git add skills/infra/kiro-gateway/
git commit -m "docs: update kiro-gateway status and docs for fork-source model"
```

---

### Task 9: Live end-to-end verification (integration, this host)

**Files:** none (verification only).

- [ ] **Step 1: Reuse the existing checkout, initialize**

```bash
CANONICAL_DIR="$HOME/.agent-skills-setup/kiro-gateway" \
KIRO_GATEWAY_DIR="$HOME/Project/kiro-gateway" \
  bash skills/infra/kiro-gateway/lib/kiro-gateway.sh init
```

Expected: `Linked … -> …/Project/kiro-gateway`, `Fix-guard: role:str present.`, a docker build, `Started kiro-gateway (kiro-gateway:<sha>)`, `Health probe: HTTP 200`.

- [ ] **Step 2: Confirm container + probe independently**

```bash
docker ps --filter name=kiro-gateway --format '{{.Status}} {{.Image}}'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7788/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: $(security find-generic-password -s agent-skills-setup:kiro-gateway -a proxy-key -w)" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-sonnet-4-20250514","max_tokens":16,"messages":[{"role":"user","content":"ping"},{"role":"system","content":"be terse"}]}'
```

Expected: healthy container on `kiro-gateway:<sha>`; HTTP `200`.

- [ ] **Step 3: Confirm zshrc block reconciled**

Run: `grep -n "agent-skills-setup kiro-gateway" ~/.zshrc`
Expected: exactly one start + one end sentinel, aliases between them, surrounding content intact.

- [ ] **Step 4: Record outcome**

If any step fails, STOP and debug with `superpowers:systematic-debugging`; do not mark the plan complete.

---

## Self-Review

**Spec coverage:** fork source + local build (T4); SHA rollback (T4); fix-guard + patch (T1, T3); health probe (T6); corrected mount/env-file/logs (T4); build-path clone-or-symlink + edge cases (T2); managed zshrc block add/update/remove (T7); keychain/no-secrets + `.env` render + example (T5); status/docs (T8); live verify (T9). All spec sections mapped.

**Placeholder scan:** none — every step has concrete code/commands and expected output.

**Type consistency:** `build_path`/`resolve_build_path`, `fix_guard`, `build_image`→`<sha>`, `start_container <sha>`, `render_env_file`/`read_proxy_key`, `health_probe`, `write_managed_line`/`remove_managed_line`, `CANONICAL_DIR`/`FORK_REMOTE`/`PATCH_FILE`/`BLOCK_START`/`BLOCK_END` used consistently across tasks. Stubs for `render_env_file`/`health_probe` are introduced in T4 and replaced in T5/T6 so each task runs green standalone.
