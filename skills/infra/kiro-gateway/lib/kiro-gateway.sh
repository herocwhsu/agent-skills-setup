#!/usr/bin/env bash
# kiro-gateway.sh — manage the kiro-gateway Docker container
set -euo pipefail

CONTAINER_NAME="${KIRO_GATEWAY_CONTAINER:-kiro-gateway}"
HOST_PORT="${KIRO_GATEWAY_HOST_PORT:-127.0.0.1:7788}"
CONTAINER_PORT="8000"
# The kiro-cli data dir is mounted at this fixed path INSIDE the container.
# KIRO_CLI_DB_FILE must reference this container path — NOT the host path — or
# the app cannot find the DB and crash-loops with "No Kiro credentials".
CONTAINER_KIRO_DIR="/home/kiro/.local/share/kiro-cli"
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
  # Explicit: the conditional echo above is the group's last command and
  # returns 1 when previous is empty (fresh init). Without this, write_state
  # returns 1 and — as cmd_init's last statement before health_probe — aborts
  # init under set -e, silently skipping the probe on every fresh build.
  return 0
}

container_status() {
  # docker inspect prints a blank line to stdout AND exits non-zero when the
  # container is missing (docker 29.x), so `|| echo absent` would yield
  # "\nabsent". Capture stdout and treat empty as absent — exit-code-independent.
  local s
  s=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
  if [[ -n "$s" ]]; then echo "$s"; else echo "absent"; fi
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
  # Decide whether to WRITE. setup-alias calls this only for the read-back
  # snippet, so it must never overwrite an already-stored key: doing so with the
  # prompt default (kiro-local) silently breaks auth against a gateway that was
  # built with the real key. Store only when a key is explicitly provided via
  # KIRO_PROXY_KEY, or when none is stored yet. Otherwise emit the snippet only.
  local do_store=1
  if [[ -z "$proxy_key" ]]; then
    if [[ -n "$(read_proxy_key || true)" ]]; then
      do_store=0                       # key already stored — preserve it
    else
      # `|| true`: read returns non-zero on EOF; a bare read would abort under
      # set -e before the default below applies. Degrade to the kiro-local default.
      read -rp "KIRO_PROXY_KEY value (leave blank for 'kiro-local'): " proxy_key || true
      proxy_key="${proxy_key:-kiro-local}"
    fi
  fi

  if command -v security &>/dev/null; then
    if [[ "$do_store" == "1" ]]; then
      security delete-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" >/dev/null 2>&1 || true
      security add-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w "$proxy_key"
    fi
    echo '$(security find-generic-password -s "agent-skills-setup:kiro-gateway" -a "proxy-key" -w 2>/dev/null)'
  elif command -v secret-tool &>/dev/null; then
    if [[ "$do_store" == "1" ]]; then
      echo -n "$proxy_key" | secret-tool store --label="kiro-gateway proxy-key" \
        service "agent-skills-setup:kiro-gateway" username "proxy-key"
    fi
    echo '$(secret-tool lookup service "agent-skills-setup:kiro-gateway" username "proxy-key" 2>/dev/null)'
  else
    if [[ "$do_store" == "1" ]]; then
      echo "export KIRO_PROXY_KEY=${proxy_key}" >> "$HOME/.zshrc.local"
      echo "  Note: no keychain available — token written to ~/.zshrc.local (headless fallback)" >&2
    fi
    echo "\${KIRO_PROXY_KEY}"
  fi
}

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
    # `|| answer=""`: read returns non-zero on EOF (closed stdin, e.g. piped/CI
    # run without KIRO_GATEWAY_DIR). Under set -e a bare read would abort; degrade
    # to blank instead, which is the documented "clone fresh" default.
    read -rp "Path to an existing kiro-gateway checkout (blank = clone fresh): " answer || answer=""
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
  # `|| true`: git rev-parse exits non-zero on a repo with no commits or a
  # corrupt/shallow .git; a bare assignment would abort under set -e before the
  # die-guard below can produce a clear message.
  local sha; sha="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)"
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
    -v "${data_dir}:${CONTAINER_KIRO_DIR}:ro" \
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
  # `|| true`: security exits 44 when the item is absent (empty keychain on a
  # fresh host). A bare assignment would inherit that under set -e and abort
  # BEFORE the store-and-retry fallback below can run, defeating bootstrap.
  local key; key="$(read_proxy_key || true)"
  [[ -n "$key" ]] || { store_proxy_key >/dev/null; key="$(read_proxy_key || true)"; }
  # Fail loud rather than write PROXY_API_KEY= and start an unauthenticated
  # gateway (no keychain tool, or store failed).
  [[ -n "$key" ]] || die "No proxy key available (keychain empty and no keychain tool) — cannot render ~/.env.kiro-gateway."
  # Container path, not host path: the DB is read from inside the container,
  # where kiro_data_dir is mounted at CONTAINER_KIRO_DIR (see start_container).
  local db="${CONTAINER_KIRO_DIR}/data.sqlite3"
  local envf="$HOME/.env.kiro-gateway"
  # Values are UNQUOTED: docker --env-file does NOT strip quotes, so a quoted
  # value would reach the container with literal double-quotes embedded
  # (breaking auth and the DB path). --env-file reads the whole post-`=` line
  # verbatim, so spaces in the DB path (…/Application Support/…) are preserved.
  # FIRST_TOKEN_TIMEOUT: gateway default (15) 500s high-effort/large-prompt
  # calls (e.g. Claude Code subagents) before first token; 120 avoids it and
  # stays below STREAMING_READ_TIMEOUT (300).
  # SQLITE_READONLY: the kiro-cli data dir is bind-mounted :ro (see
  # start_container), so the gateway's post-refresh write-back to that DB can
  # never succeed. Left unset, every refresh logs two WARNINGs whose text
  # ("no matching keys found") misdescribes the cause: the keys DO match, but
  # the UPDATE is rejected and the error is swallowed. Setting this skips the
  # write-back before it opens the DB. Upstream default is false.
  # umask scoped to a subshell so it doesn't leak to the rest of the script.
  ( umask 077
    printf 'PROXY_API_KEY=%s\nKIRO_CLI_DB_FILE=%s\nFIRST_TOKEN_TIMEOUT=120\nSQLITE_READONLY=true\n' "$key" "$db" > "$envf" )
  chmod 600 "$envf"
  echo "Rendered $envf (chmod 600)"
}

health_probe() {
  command -v curl &>/dev/null || { echo "curl not found — skipping health probe." >&2; return 0; }
  local key; key="$(read_proxy_key)" || true
  local body='{"model":"claude-sonnet-4-20250514","max_tokens":16,"messages":[{"role":"user","content":"ping"},{"role":"system","content":"be terse"}]}'
  # Poll: the app has a blocking startup (token refresh, account init) and does
  # not bind its port for several seconds after `docker run -d` returns. Retry
  # while the connection is refused (HTTP 000), but fail FAST on any real HTTP
  # response other than 200 (e.g. 422/500 — server is up and rejecting, so
  # retrying won't help). Overridable for tests via HEALTH_PROBE_RETRIES/INTERVAL.
  local retries="${HEALTH_PROBE_RETRIES:-20}" interval="${HEALTH_PROBE_INTERVAL:-2}"
  local i code
  for (( i=1; i<=retries; i++ )); do
    # `|| true`: curl exits non-zero (7) on connection-refused while still
    # printing 000. Under `set -e` a bare assignment would inherit that exit and
    # kill the script on the first probe — before the retry loop can wait for the
    # app to bind its port. Absorb it here; the 000 case below drives the retry.
    code=$(curl -s -o /dev/null -w '%{http_code}' \
      "http://${HOST_PORT}/v1/messages" \
      -H "content-type: application/json" \
      -H "x-api-key: ${key}" \
      -H "anthropic-version: 2023-06-01" \
      -d "$body" 2>/dev/null || true)
    case "$code" in
      200)
        echo "Health probe: HTTP 200 — system-role request accepted."
        return 0
        ;;
      000|000000|"")
        sleep "$interval" ;;  # not listening yet — wait and retry
      *)
        echo "Health probe FAILED: HTTP $code" >&2
        docker logs --tail 30 "$CONTAINER_NAME" 2>&1 | sed 's/^/  /' >&2 || true
        die "Gateway returned HTTP $code for a system-role request." ;;
    esac
  done
  echo "Health probe FAILED: gateway not ready after $((retries * interval))s" >&2
  docker logs --tail 30 "$CONTAINER_NAME" 2>&1 | sed 's/^/  /' >&2 || true
  die "Gateway did not become ready (no HTTP 200 within timeout)."
}

cmd_status() {
  # Both halves must be present to work. Reporting "configured" off the
  # provider alone hid a host whose profile file was missing entirely.
  # if/then, not `grep ... && x=1`: the latter returns non-zero when grep
  # misses and aborts the script under set -e.
  local has_provider=0 has_profile=0
  if grep -Fq "[model_providers.kiro]" "$HOME/.codex-kiro/config.toml" 2>/dev/null; then
    has_provider=1
  fi
  if grep -Fq 'model_provider = "kiro"' "$HOME/.codex-kiro/kiro.config.toml" 2>/dev/null; then
    has_profile=1
  fi
  if [[ "$has_provider" == "1" && "$has_profile" == "1" ]]; then
    echo "Codex:      configured (~/.codex-kiro)"
  elif [[ "$has_provider" == "1" ]]; then
    echo "Codex:      INCOMPLETE - provider set, kiro.config.toml missing (run setup-codex)"
  elif [[ "$has_profile" == "1" ]]; then
    echo "Codex:      INCOMPLETE - profile set, config.toml provider missing (run setup-codex)"
  else
    echo "Codex:      not configured"
  fi
  if [[ -L "$CANONICAL_DIR" ]]; then
    echo "Build path: linked → $(readlink "$CANONICAL_DIR")"
  elif [[ -d "$CANONICAL_DIR" ]]; then
    echo "Build path: cloned ($CANONICAL_DIR)"
  else
    echo "Build path: not set up (run 'init')"
  fi
  local cur; cur=$(read_state current)
  [[ -n "$cur" ]] && echo "Image:      kiro-gateway:$cur"
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
  render_env_file
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
  local rc; rc=$(rc_file_path)
  local read_cmd; read_cmd=$(store_proxy_key)
  write_managed_line "$rc" "claude-kiro" \
    "alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} claude'"
  write_managed_line "$rc" "hermes-kiro" \
    "alias hermes-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=${read_cmd} hermes --provider anthropic --model claude-sonnet-5'"
  echo "Reconciled claude-kiro/hermes-kiro in $rc. Activate: source $rc"
}

cmd_setup_codex() {
  local codex_home="$HOME/.codex-kiro"
  local config_file="$codex_home/config.toml"
  local profile_file="$codex_home/kiro.config.toml"
  local rc; rc=$(rc_file_path)
  local read_cmd; read_cmd=$(store_proxy_key)
  mkdir -p "$codex_home"
  # Two files, two independent guards. `codex --help` documents --profile as
  # "Layer $CODEX_HOME/<name>.config.toml on top of the base user config", so
  # the provider lives in config.toml and the model in kiro.config.toml.
  # The old single heredoc wrote both tables together, so it is not what split
  # them -- Codex 0.149.1 most likely migrated the profile out itself (its
  # binary carries a "`.config.toml` instead" string). The guard's real fault is
  # that it could not *repair* the result: the marker it tests stayed present,
  # so setup-codex skipped the write while status still reported "configured".
  if ! grep -Fq "[model_providers.kiro]" "$config_file" 2>/dev/null; then
    cat > "$config_file" <<'EOF'
[model_providers.kiro]
name = "Kiro Gateway"
base_url = "http://localhost:7788/v1"
env_key = "KIRO_PROXY_KEY"
wire_api = "responses"
EOF
    echo "Wrote $config_file"
  fi

  # Never overwrite an existing profile: this file is where a model is pinned,
  # and rewriting it would silently revert a deliberate choice.
  if ! grep -Fq 'model_provider = "kiro"' "$profile_file" 2>/dev/null; then
    cat > "$profile_file" <<'EOF'
model = "claude-opus-4.8"
model_provider = "kiro"
EOF
    echo "Wrote $profile_file"
  else
    echo "Kept $profile_file (existing model choice preserved)"
  fi

  # A [profiles.kiro] table in config.toml is the pre-V2 layout this script used
  # to write. Report it rather than deleting it -- whether 0.149.x still honours
  # it is not something this script can determine.
  if grep -Fq "[profiles.kiro]" "$config_file" 2>/dev/null; then
    echo "Note: $config_file still has a legacy [profiles.kiro] table; --profile now reads $profile_file." >&2
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
  __health_probe) health_probe ;;
  *)             die "Unknown subcommand: '${1:-}'. Use: init | update | rollback | status | setup-alias | setup-codex | remove-codex" ;;

esac
