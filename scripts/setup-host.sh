#!/usr/bin/env bash
# setup-host.sh — configure Claude Code host environment
# Run after install.sh to set up statusline, notifications, MCP, and remote control.
#
# Usage:
#   bash scripts/setup-host.sh                  # interactive
#   bash scripts/setup-host.sh --legacy-statusline   # keep the PS1-style statusline
#   NTFY_URL=https://ntfy.example.com/topic \
#   NTFY_TOKEN=tk_xxx \
#     bash scripts/setup-host.sh               # non-interactive
#
# Statusline: defaults to the claude-hud plugin (context bar, tools, agents,
# todos) when the plugin and a bun/node runtime are present; otherwise — or
# with --legacy-statusline — installs config/statusline-command.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"
CLAUDE_DIR="$HOME/.claude"

LEGACY_STATUSLINE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --legacy-statusline) LEGACY_STATUSLINE=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── colours ────────────────────────────────────────────────────────────────────
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
step()   { echo; bold "==> $*"; }

# ── checks ─────────────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required. Install it first (apt install jq / brew install jq)." >&2
  exit 1
fi
if ! command -v claude &>/dev/null; then
  echo "ERROR: claude CLI not found. Install Claude Code first." >&2
  exit 1
fi

# ── 1. statusline ──────────────────────────────────────────────────────────────
# hud_statusline_cmd <runtime_path> <source_file> <bun_flags>
#   Emit the settings.json statusLine command for claude-hud. Template comes
#   verbatim from the plugin's own /claude-hud:setup instructions: exports the
#   real terminal width via COLUMNS and resolves the newest installed plugin
#   version at each refresh, so plugin updates don't require re-running setup.
hud_statusline_cmd() {
  local runtime="$1" source_file="$2" bun_flags="$3"
  local tpl
  read -r -d '' tpl <<'TPL' || true
bash -c 'cols=${COLUMNS:-}; case "$cols" in ""|*[!0-9]*) cols=$(stty size </dev/tty 2>/dev/null | awk '"'"'{print $2}'"'"');; esac; case "$cols" in ""|*[!0-9]*) cols=120;; esac; export COLUMNS=$(( cols > 4 ? cols - 4 : 1 )); plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/claude-hud/*/ 2>/dev/null | awk -F/ '"'"'{ print $(NF-1) "\t" $(0) }'"'"' | grep -E '"'"'^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]'"'"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec "{RUNTIME_PATH}"{BUN_FLAGS} "${plugin_dir}{SOURCE}"'
TPL
  tpl="${tpl//\{RUNTIME_PATH\}/$runtime}"
  tpl="${tpl//\{SOURCE\}/$source_file}"
  tpl="${tpl//\{BUN_FLAGS\}/$bun_flags}"
  printf '%s' "$tpl"
}

step "Configuring statusline"
mkdir -p "$CLAUDE_DIR"

HUD_STATUSLINE_CMD=""
if [[ $LEGACY_STATUSLINE -eq 0 ]]; then
  HUD_DIR=$(ls -d "$CLAUDE_DIR"/plugins/cache/*/claude-hud/*/ 2>/dev/null | sort -V | tail -1 || true)
  HUD_RUNTIME=$(command -v bun 2>/dev/null || command -v node 2>/dev/null || true)
  if [[ -n "$HUD_DIR" && -n "$HUD_RUNTIME" ]]; then
    if [[ "$(basename "$HUD_RUNTIME")" == bun* ]]; then
      # --env-file /dev/null keeps bun from auto-loading project .env files
      HUD_STATUSLINE_CMD=$(hud_statusline_cmd "$HUD_RUNTIME" "src/index.ts" " --env-file /dev/null")
    else
      HUD_STATUSLINE_CMD=$(hud_statusline_cmd "$HUD_RUNTIME" "dist/index.js" "")
    fi
    green "  ✓ claude-hud statusline (runtime: $HUD_RUNTIME)"
  else
    yellow "  ⚠ claude-hud plugin or bun/node runtime not found — falling back to legacy statusline"
    yellow "    (install: claude plugin install claude-hud@claude-hud + Node 18+)"
  fi
fi

if [[ -z "$HUD_STATUSLINE_CMD" ]]; then
  cp "$CONFIG_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"
  green "  ✓ $CLAUDE_DIR/statusline-command.sh (legacy PS1-style)"
fi

# ── 2. notify.sh ──────────────────────────────────────────────────────────────
step "Configuring notification hook"

if [ -z "${NTFY_URL:-}" ]; then
  echo "  ntfy push notifications (leave blank to skip):"
  read -r -p "  ntfy topic URL (e.g. https://ntfy.example.com/claude-code): " NTFY_URL
fi
if [ -n "$NTFY_URL" ] && [ -z "${NTFY_TOKEN:-}" ]; then
  read -r -p "  ntfy token: " NTFY_TOKEN
fi

# Write notify.sh with substituted values (or pass-through env vars if blank)
sed \
  -e "s|NTFY_URL:-}|NTFY_URL:-${NTFY_URL:-}}|" \
  -e "s|NTFY_TOKEN:-}|NTFY_TOKEN:-${NTFY_TOKEN:-}}|" \
  "$CONFIG_DIR/notify.sh" > "$CLAUDE_DIR/notify.sh"
chmod +x "$CLAUDE_DIR/notify.sh"

if [ -n "${NTFY_URL:-}" ]; then
  green "  ✓ $CLAUDE_DIR/notify.sh (url: $NTFY_URL)"
else
  yellow "  ⚠ notify.sh installed without credentials — push disabled until NTFY_URL/NTFY_TOKEN are set"
fi

# ── 3. Claude settings ─────────────────────────────────────────────────────────
step "Patching ~/.claude/settings.json"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS" ]; then
  # Merge patch into existing settings (patch wins on conflicts)
  MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS" "$CONFIG_DIR/claude-settings-patch.json")
  echo "$MERGED" > "$SETTINGS"
  green "  ✓ merged into existing settings.json"
else
  cp "$CONFIG_DIR/claude-settings-patch.json" "$SETTINGS"
  green "  ✓ created settings.json"
fi

# The patch points statusLine at the legacy script; override when using claude-hud
if [ -n "$HUD_STATUSLINE_CMD" ]; then
  MERGED=$(jq --arg cmd "$HUD_STATUSLINE_CMD" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS")
  echo "$MERGED" > "$SETTINGS"
  green "  ✓ statusLine → claude-hud"
fi

# ── 4. Playwright MCP ─────────────────────────────────────────────────────────
step "Registering Playwright MCP server"
if claude mcp list 2>/dev/null | grep -q "playwright"; then
  yellow "  ⚠ playwright MCP already registered — skipping"
else
  claude mcp add playwright --scope user -- npx @playwright/mcp@latest --headless
  green "  ✓ playwright MCP registered (headless)"
fi

# ── 5. tmux ───────────────────────────────────────────────────────────────────
step "Configuring tmux"
TMUX_CONF="$HOME/.tmux.conf"

add_tmux_line() {
  local line="$1"
  if ! grep -qF "$line" "$TMUX_CONF" 2>/dev/null; then
    echo "$line" >> "$TMUX_CONF"
  fi
}

add_tmux_line "set -g mouse on"
# Use xclip on Linux, pbcopy on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
  add_tmux_line "bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel \"pbcopy\""
  add_tmux_line "bind -T copy-mode y send-keys -X copy-pipe-and-cancel \"pbcopy\""
else
  add_tmux_line "bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
  add_tmux_line "bind -T copy-mode y send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
fi
green "  ✓ $TMUX_CONF (mouse on, vi-copy yank)"

# ── done ──────────────────────────────────────────────────────────────────────
echo
bold "Done. What was configured:"
if [ -n "$HUD_STATUSLINE_CMD" ]; then
  echo "  statusline                       — claude-hud (context bar, tools, agents, todos)"
else
  echo "  ~/.claude/statusline-command.sh  — PS1-style statusline with context usage"
fi
echo "  ~/.claude/notify.sh              — ntfy push on Claude notifications"
echo "  ~/.claude/settings.json          — hooks, remote control, statusline, theme"
echo "  Playwright MCP                   — live browser debugging via claude mcp"
echo "  ~/.tmux.conf                     — mouse mode, vi-copy yank"
echo
echo "Restart Claude Code to apply all changes."
if [ -n "${NTFY_URL:-}" ]; then
  echo
  echo "To receive push notifications, subscribe to: $NTFY_URL"
  echo "(use the ntfy app on iOS/Android)"
fi
