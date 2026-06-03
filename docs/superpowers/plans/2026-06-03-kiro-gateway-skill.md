# kiro-gateway Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `kiro-gateway` skill to `agent-skills-setup` that manages the kiro-gateway Docker container with digest-pinned versioning and one-step rollback.

**Architecture:** A single shell script (`lib/kiro-gateway.sh`) with four subcommands (`init`, `update`, `rollback`, `status`) backed by a two-entry state file at `~/.agent-skills-setup/kiro-gateway.state`. The skill is installed via the existing `local` registry mechanism — no hooks, no extra deps.

**Tech Stack:** bash, Docker CLI, pytest (for shell integration tests via subprocess)

**Spec:** `docs/superpowers/specs/2026-06-03-kiro-gateway-skill-design.md`

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `skills/kiro-gateway/SKILL.md` | Skill descriptor Claude reads |
| Create | `skills/kiro-gateway/README.md` | Human-readable install + usage |
| Create | `skills/kiro-gateway/lib/kiro-gateway.sh` | All four subcommands |
| Create | `skills/kiro-gateway/tests/test_kiro_gateway.sh` | Integration tests (bats-free, plain bash) |
| Modify | `registry.txt` | Add `local  kiro-gateway` |

---

## Task 1: Scaffold skill directory and SKILL.md

**Files:**
- Create: `skills/kiro-gateway/SKILL.md`

- [ ] **Step 1: Create the skill directory and SKILL.md**

```bash
mkdir -p ~/Project/agent-skills-setup/skills/kiro-gateway/lib
mkdir -p ~/Project/agent-skills-setup/skills/kiro-gateway/tests
```

Create `skills/kiro-gateway/SKILL.md`:

```markdown
---
name: kiro-gateway
description: Use when the user wants to initialize, update, rollback, or check the status of the kiro-gateway Docker container. Manages a digest-pinned image with one-step rollback. Subcommands: init, update, rollback, status.
---

# kiro-gateway

Manages the kiro-gateway Docker container — the proxy that lets Claude Code and Kiro IDE authenticate through AWS/Kiro credentials to use Claude models.

## Usage

Ask Claude to:
- "Set up kiro-gateway" → runs `init`
- "Update kiro-gateway" → runs `update`
- "Rollback kiro-gateway" → runs `rollback`
- "Show kiro-gateway status" → runs `status`

Claude will call:
```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh <subcommand>
```

## Subcommands

| Subcommand | What it does |
|---|---|
| `init` | Start the container. Pins digest on first run. Idempotent. |
| `update` | Pull latest, confirm new digest, recreate container. |
| `rollback` | Revert to previous digest. Swaps current ↔ previous in state. |
| `status` | Show container state, current digest, previous digest. |

## State file

`~/.agent-skills-setup/kiro-gateway.state` — two lines:
```
current=ghcr.io/jwadow/kiro-gateway@sha256:<digest>
previous=ghcr.io/jwadow/kiro-gateway@sha256:<old-digest>
```
`previous` is absent until the first `update`.
```

- [ ] **Step 2: Verify file exists**

```bash
cat ~/Project/agent-skills-setup/skills/kiro-gateway/SKILL.md | head -5
```
Expected: frontmatter with `name: kiro-gateway`

- [ ] **Step 3: Commit**

```bash
cd ~/Project/agent-skills-setup
git add skills/kiro-gateway/SKILL.md
git commit -m "feat: scaffold kiro-gateway skill directory and SKILL.md"
```

---

## Task 2: Write README.md

**Files:**
- Create: `skills/kiro-gateway/README.md`

- [ ] **Step 1: Create README.md**

Create `skills/kiro-gateway/README.md`:

```markdown
# kiro-gateway

Manages the kiro-gateway Docker container with digest pinning and rollback.

## Requirements

- Docker installed and running
- Kiro CLI run at least once (creates the data dir the container mounts)

## Install

```bash
bash scripts/install.sh
```

Adds `~/.claude/skills/kiro-gateway/` (and `~/.kiro/skills/kiro-gateway/` if kiro is selected) as a symlink into this repo.

## Usage

Tell your AI agent: "set up kiro-gateway" / "update kiro-gateway" / "rollback kiro-gateway" / "kiro-gateway status".

Or run directly:

```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh init
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh update
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh rollback
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh status
```

## Container details

| Setting | Value |
|---|---|
| Image | `ghcr.io/jwadow/kiro-gateway` (digest-pinned) |
| Host port | `127.0.0.1:7788` |
| Container port | `8000` |
| Volume | `<kiro-data-dir> → /home/ubuntu/.local/share/kiro-cli` |
| Restart | `unless-stopped` |

Data dir by platform:
- macOS: `$HOME/Library/Application Support/kiro-cli`
- Linux: `$HOME/.local/share/kiro-cli`

## State file

`~/.agent-skills-setup/kiro-gateway.state`

Tracks current and previous digests for rollback. Never delete this file manually — use `rollback` instead.

## Troubleshooting

**"kiro data dir not found"** — Run Kiro IDE or CLI once to create it, then retry `init`.

**"docker: command not found"** — Install Docker Desktop (macOS) or `docker-ce` (Linux).

**"no previous version recorded"** — `rollback` requires at least one prior `update`. There is no version before the first pinned digest.
```

- [ ] **Step 2: Commit**

```bash
cd ~/Project/agent-skills-setup
git add skills/kiro-gateway/README.md
git commit -m "feat: add kiro-gateway README"
```

---

## Task 3: Write the shell script — helpers and `status`

**Files:**
- Create: `skills/kiro-gateway/lib/kiro-gateway.sh`

- [ ] **Step 1: Write the failing test for `status` with no container**

Create `skills/kiro-gateway/tests/test_kiro_gateway.sh`:

```bash
#!/usr/bin/env bash
# Minimal test runner — no bats dependency.
# Each test_* function runs in a subshell with a temp state dir.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/lib/kiro-gateway.sh"
PASS=0
FAIL=0

run_test() {
  local name="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  if ( KIRO_GATEWAY_STATE_FILE="$tmpdir/kiro-gateway.state" bash "$SCRIPT" "$@" 2>&1 ); then
    echo "PASS: $name"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

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

# --- tests ---

expect_output "status no state file shows no state" "no state file" status
expect_output "rollback no previous exits with message" "no previous version" rollback
expect_exit   "rollback no previous exits 1" 1 rollback
expect_exit   "unknown subcommand exits 1" 1 unknown-cmd

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Project/agent-skills-setup
bash skills/kiro-gateway/tests/test_kiro_gateway.sh 2>&1 | head -20
```
Expected: errors like "No such file or directory" — script does not exist yet.

- [ ] **Step 3: Create `kiro-gateway.sh` with helpers and `status`**

Create `skills/kiro-gateway/lib/kiro-gateway.sh`:

```bash
#!/usr/bin/env bash
# kiro-gateway.sh — manage the kiro-gateway Docker container
set -euo pipefail

IMAGE_BASE="ghcr.io/jwadow/kiro-gateway"
CONTAINER_NAME="kiro-gateway"
HOST_PORT="127.0.0.1:7788"
CONTAINER_PORT="8000"
STATE_FILE="${KIRO_GATEWAY_STATE_FILE:-$HOME/.agent-skills-setup/kiro-gateway.state}"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

require_docker() {
  command -v docker &>/dev/null || die "docker not found. Install Docker Desktop (macOS) or docker-ce (Linux)."
}

kiro_data_dir() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support/kiro-cli" ;;
    Linux)  echo "$HOME/.local/share/kiro-cli" ;;
    *)      die "Unsupported platform: $(uname -s)" ;;
  esac
}

read_state() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  grep "^${key}=" "$STATE_FILE" | cut -d= -f2- || true
}

write_state() {
  local current="$1" previous="${2:-}"
  mkdir -p "$(dirname "$STATE_FILE")"
  {
    echo "current=$current"
    [[ -n "$previous" ]] && echo "previous=$previous"
  } > "$STATE_FILE"
}

container_status() {
  docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "absent"
}

resolve_digest() {
  local ref="$1"
  docker inspect --format '{{index .RepoDigests 0}}' "$ref" 2>/dev/null | grep -o 'sha256:[a-f0-9]*' || true
}

start_container() {
  local image_ref="$1"
  local data_dir
  data_dir=$(kiro_data_dir)
  [[ -d "$data_dir" ]] || die "kiro data dir not found: $data_dir\nRun Kiro IDE or CLI once to create it, then retry."
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    -v "${data_dir}:/home/ubuntu/.local/share/kiro-cli" \
    "$image_ref" \
    python main.py
  echo "Started $CONTAINER_NAME ($image_ref)"
}

# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------

cmd_status() {
  require_docker
  local state
  state=$(container_status)
  echo "Container:  $state"
  if [[ -f "$STATE_FILE" ]]; then
    echo "Current:    $(read_state current)"
    local prev
    prev=$(read_state previous)
    [[ -n "$prev" ]] && echo "Previous:   $prev" || echo "Previous:   (none)"
    echo "Port:       $HOST_PORT → $CONTAINER_PORT"
  else
    echo "State file: no state file (run 'init' first)"
  fi
}

cmd_init() {
  require_docker
  local image_ref
  local current
  current=$(read_state current)

  if [[ -n "$current" ]]; then
    image_ref="$current"
    echo "Using pinned image: $image_ref"
  else
    echo "No state file — pulling latest to pin digest..."
    docker pull "${IMAGE_BASE}:latest"
    local digest
    digest=$(resolve_digest "${IMAGE_BASE}:latest")
    [[ -n "$digest" ]] || die "Could not resolve digest for ${IMAGE_BASE}:latest"
    image_ref="${IMAGE_BASE}@${digest}"
    write_state "$image_ref"
    echo "Pinned: $image_ref"
  fi

  local state
  state=$(container_status)
  case "$state" in
    running)
      echo "$CONTAINER_NAME is already running."
      ;;
    exited|created|paused)
      echo "Restarting stopped container..."
      docker start "$CONTAINER_NAME"
      ;;
    absent)
      start_container "$image_ref"
      ;;
    *)
      die "Unexpected container state: $state"
      ;;
  esac
}

cmd_update() {
  require_docker
  echo "Pulling ${IMAGE_BASE}:latest..."
  docker pull "${IMAGE_BASE}:latest"

  local new_digest
  new_digest=$(resolve_digest "${IMAGE_BASE}:latest")
  [[ -n "$new_digest" ]] || die "Could not resolve digest after pull."
  local new_ref="${IMAGE_BASE}@${new_digest}"

  local current
  current=$(read_state current)
  if [[ "$new_ref" == "$current" ]]; then
    echo "Already up to date: $new_ref"
    exit 0
  fi

  echo "Current: $current"
  echo "New:     $new_ref"
  read -rp "Apply update? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  local previous
  previous=$(read_state previous)
  write_state "$new_ref" "${current:-}"

  local state
  state=$(container_status)
  if [[ "$state" != "absent" ]]; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi
  cmd_init
}

cmd_rollback() {
  require_docker
  local previous
  previous=$(read_state previous)
  [[ -n "$previous" ]] || die "no previous version recorded. Rollback requires at least one prior update."

  local current
  current=$(read_state current)
  echo "Rolling back: $current → $previous"

  local state
  state=$(container_status)
  if [[ "$state" != "absent" ]]; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi

  write_state "$previous" "$current"
  start_container "$previous"
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  init)     cmd_init ;;
  update)   cmd_update ;;
  rollback) cmd_rollback ;;
  status)   cmd_status ;;
  *)        die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status" ;;
esac
```

- [ ] **Step 4: Run the tests**

```bash
cd ~/Project/agent-skills-setup
bash skills/kiro-gateway/tests/test_kiro_gateway.sh
```
Expected:
```
PASS: status no state file shows no state
PASS: rollback no previous exits with message
PASS: rollback no previous exits 1
PASS: unknown subcommand exits 1

Results: 4 passed, 0 failed
```

- [ ] **Step 5: Commit**

```bash
cd ~/Project/agent-skills-setup
git add skills/kiro-gateway/lib/kiro-gateway.sh skills/kiro-gateway/tests/test_kiro_gateway.sh
git commit -m "feat: add kiro-gateway.sh with init/update/rollback/status"
```

---

## Task 4: Register skill in registry.txt

**Files:**
- Modify: `registry.txt`

- [ ] **Step 1: Add entry to registry.txt**

Open `registry.txt` and add one line after `local  review-pr`:

```
local  kiro-gateway
```

The relevant section should look like:

```
local  create-story-tasks
local  fetch-jira-story
local  fetch-page-to-markdown
local  mine-review-patterns
local  plan-story
local  polish-input
local  review-pr
local  kiro-gateway
```

- [ ] **Step 2: Verify install.sh picks it up (dry run)**

```bash
cd ~/Project/agent-skills-setup
grep "kiro-gateway" registry.txt
```
Expected: `local  kiro-gateway`

- [ ] **Step 3: Commit**

```bash
cd ~/Project/agent-skills-setup
git add registry.txt
git commit -m "feat: register kiro-gateway in registry.txt"
```

---

## Task 5: Install and smoke test

**Files:** none new — verifies end-to-end install

- [ ] **Step 1: Run installer for claude agent**

```bash
cd ~/Project/agent-skills-setup
bash scripts/install.sh --agent claude
```
Expected output includes: `✓ kiro-gateway`

- [ ] **Step 2: Verify symlink exists**

```bash
ls -la ~/.claude/skills/kiro-gateway
```
Expected: symlink pointing into `~/Project/agent-skills-setup/skills/kiro-gateway`

- [ ] **Step 3: Smoke test status via installed path**

```bash
bash ~/.claude/skills/kiro-gateway/lib/kiro-gateway.sh status
```
Expected: prints container state (running or absent) + current digest from state file.

- [ ] **Step 4: Run tests one more time from installed path**

```bash
bash ~/.claude/skills/kiro-gateway/tests/test_kiro_gateway.sh
```
Expected: `Results: 4 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
cd ~/Project/agent-skills-setup
git add -A
git status
# Nothing to commit if install only created symlinks outside repo
git log --oneline -5
```

No new files to commit here — install creates symlinks outside the repo. Confirm the previous 4 commits are present.

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| `init` subcommand | Task 3, `cmd_init` |
| `update` subcommand | Task 3, `cmd_update` |
| `rollback` subcommand | Task 3, `cmd_rollback` |
| `status` subcommand | Task 3, `cmd_status` |
| Digest pinning on first pull | Task 3, `cmd_init` — no-state-file branch |
| State file with `current`/`previous` | Task 3, `write_state` / `read_state` |
| Platform data dir detection | Task 3, `kiro_data_dir()` |
| `docker` not found → exit 1 | Task 3, `require_docker` |
| Data dir missing → exit 1 with hint | Task 3, `start_container` |
| `docker pull` fails → state unchanged | Task 3 — `set -euo pipefail` exits before `write_state` |
| `previous` absent on rollback → exit 1 | Task 3, `cmd_rollback` |
| Registry entry | Task 4 |
| SKILL.md | Task 1 |
| README.md | Task 2 |
| Port `127.0.0.1:7788:8000` | Task 3, `start_container` |
| `restart: unless-stopped` | Task 3, `start_container` |

All requirements covered. No placeholders. Types consistent across all tasks.
