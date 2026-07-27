#!/usr/bin/env bash
# kiro-gateway.sh — manage the kiro-gateway Docker container
set -euo pipefail

CONTAINER_NAME="kiro-gateway"
HOST_PORT="127.0.0.1:7788"
CONTAINER_PORT="8000"
STATE_FILE="${KIRO_GATEWAY_STATE_FILE:-$HOME/.agent-skills-setup/kiro-gateway.state}"
FORK_REMOTE="git@github.com:herocwhsu/kiro-gateway.git"
CANONICAL_DIR="${CANONICAL_DIR:-$HOME/.agent-skills-setup/kiro-gateway}"

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

build_path() { echo "$CANONICAL_DIR"; }

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$LIB_DIR/../patches/kiro-gateway-system-role.patch"

# Assert the role:str fix is present before any build; apply the tracked
# patch if the field is still the strict Literal. Aborts loudly if the patch
# cannot be applied — never build from known-broken code.
fix_guard() {
  local repo; repo="$(build_path)"
  local model="$repo/kiro/models_anthropic.py"
  [[ -f "$model" ]] || die "Cannot find $model — is the build path a kiro-gateway checkout?"

  # Trailing (#|$) boundary so `role: strict`/`role: strawberry` cannot
  # false-positive as the fix (which would skip the patch on broken code).
  # Matches `role: str` alone and `role: str  # comment` (what the patch writes).
  if grep -Eq '^\s*role:\s*str\s*(#|$)' "$model"; then
    echo "Fix-guard: role:str present."
    return 0
  fi

  echo "Fix-guard: strict role type detected — applying tracked patch..."
  [[ -f "$PATCH_FILE" ]] || die "Fix patch missing: $PATCH_FILE"
  if git -C "$repo" apply --check "$PATCH_FILE" 2>/dev/null; then
    git -C "$repo" apply "$PATCH_FILE" || die "Fix patch --check passed but apply failed in $repo — aborting."
  else
    die "Fix patch will not apply cleanly to $repo — aborting before build. Resolve manually."
  fi
  grep -Eq '^\s*role:\s*str\s*(#|$)' "$model" || die "Fix-guard: role:str still absent after patch — aborting."
  echo "Fix-guard: patch applied."
}

# Expand a leading ~ to $HOME and make absolute.
_expand_path() {
  local p="$1"
  # shellcheck disable=SC2088 # intentional: matching literal "~/" prefix in case patterns, not shell-expanding it
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

require_git() { command -v git &>/dev/null || die "git not found."; }

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

# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------

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
  # FIRST_TOKEN_TIMEOUT: gateway default (15) 500s high-effort/large-prompt
  # calls (e.g. Claude Code subagents) before first token; 120 avoids it and
  # stays below STREAMING_READ_TIMEOUT (300).
  printf 'PROXY_API_KEY="%s"\nKIRO_CLI_DB_FILE="%s"\nFIRST_TOKEN_TIMEOUT=120\n' "$key" "$db" > "$envf"
  chmod 600 "$envf"
  echo "Rendered $envf (chmod 600)"
}

health_probe() { :; }      # replaced in Task 6

cmd_status() {
  if [[ -f "$HOME/.codex-kiro/config.toml" ]] \
     && grep -Fq "[model_providers.kiro]" "$HOME/.codex-kiro/config.toml" 2>/dev/null; then
    echo "Codex:      configured (~/.codex-kiro)"
  else
    echo "Codex:      not configured"
  fi
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

# Idempotent bring-up. Check container state FIRST; only the absent branch
# builds a new image and writes state — so re-running init on a live container
# never rebuilds/redeploys and never records a sha that isn't actually running
# (that drift would make status/rollback trust a lie). `update` is the explicit
# rebuild+redeploy path.
cmd_init() {
  require_docker
  local state; state=$(container_status)
  case "$state" in
    running)
      echo "$CONTAINER_NAME already running (kiro-gateway:$(read_state current)). Use 'update' to rebuild+redeploy."
      return 0
      ;;
    exited|created|paused)
      echo "Restarting existing container (image unchanged)..."
      docker start "$CONTAINER_NAME"
      ;;
    absent)
      resolve_build_path
      fix_guard
      render_env_file
      local sha; sha="$(build_image)"
      start_container "$sha"
      write_state "$sha" "$(read_state previous)"
      ;;
    *) die "Unexpected container state: $state" ;;
  esac
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

cmd_remove_codex() {
  local codex_home="$HOME/.codex-kiro"
  local rc_file
  rc_file=$(rc_file_path)

  if [[ -f "$rc_file" ]] && grep -Fq "codex-kiro" "$rc_file"; then
    grep -v -e "alias codex-kiro" -e "kiro-gateway (codex)" "$rc_file" > "$rc_file.tmp" || true
    mv "$rc_file.tmp" "$rc_file"
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

cmd_rollback() {
  local previous; previous=$(read_state previous)
  [[ -n "$previous" ]] || die "no previous version recorded. Rollback requires at least one prior update."
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

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  init)          cmd_init ;;
  update)        cmd_update ;;
  rollback)      cmd_rollback ;;
  status)        cmd_status ;;
  setup-alias)   cmd_setup_alias ;;
  setup-codex)   cmd_setup_codex ;;
  remove-codex)  cmd_remove_codex ;;
  __resolve_build_path) resolve_build_path ;;
  __fix_guard)   fix_guard ;;
  __render_env)  render_env_file ;;
  *)             die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status | setup-alias | setup-codex | remove-codex" ;;
esac
