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
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "State file: no state file (run 'init' first)"
    return 0
  fi
  require_docker
  local state
  state=$(container_status)
  echo "Container:  $state"
  echo "Current:    $(read_state current)"
  local prev
  prev=$(read_state previous)
  [[ -n "$prev" ]] && echo "Previous:   $prev" || echo "Previous:   (none)"
  echo "Port:       $HOST_PORT → $CONTAINER_PORT"
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

  write_state "$new_ref" "${current:-}"

  local state
  state=$(container_status)
  if [[ "$state" != "absent" ]]; then
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"
  fi
  cmd_init
}

cmd_setup_alias() {
  local rc_file
  case "${SHELL:-}" in
    */zsh)  rc_file="$HOME/.zshrc" ;;
    */bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        rc_file="$HOME/.bash_profile"
      else
        rc_file="$HOME/.bashrc"
      fi
      ;;
    *) rc_file="$HOME/.zshrc" ;;
  esac

  if grep -Fq "claude-kiro" "$rc_file" 2>/dev/null; then
    echo "claude-kiro alias already present in $rc_file"
    return 0
  fi

  local proxy_key="${KIRO_PROXY_KEY:-}"
  if [[ -z "$proxy_key" ]]; then
    read -rp "KIRO_PROXY_KEY value (leave blank for 'kiro-local'): " proxy_key
    proxy_key="${proxy_key:-kiro-local}"
  fi

  # Store in keychain — never write plaintext token to shell rc files
  if command -v security &>/dev/null; then
    security delete-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" >/dev/null 2>&1 || true
    security add-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w "$proxy_key"
    local read_cmd='$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null)'
  elif command -v secret-tool &>/dev/null; then
    echo -n "$proxy_key" | secret-tool store --label="kiro-gateway proxy-key" \
      service "agent-skills-setup:kiro-gateway" username "proxy-key"
    local read_cmd='$(secret-tool lookup service "agent-skills-setup:kiro-gateway" username "proxy-key" 2>/dev/null)'
  else
    # Headless Linux fallback: write to ~/.zshrc.local, not main rc
    local read_cmd="\${KIRO_PROXY_KEY}"
    echo "export KIRO_PROXY_KEY=${proxy_key}" >> "$HOME/.zshrc.local"
    echo "  Note: no keychain available — token written to ~/.zshrc.local (headless fallback)"
  fi

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

cmd_rollback() {
  local previous
  previous=$(read_state previous)
  [[ -n "$previous" ]] || die "no previous version recorded. Rollback requires at least one prior update."
  require_docker
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
  init)          cmd_init ;;
  update)        cmd_update ;;
  rollback)      cmd_rollback ;;
  status)        cmd_status ;;
  setup-alias)   cmd_setup_alias ;;
  *)             die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status | setup-alias" ;;
esac
