#!/usr/bin/env bash
# setup-host.sh — configure Claude Code host environment
# Run after install.sh to set up statusline, notifications, MCP, and remote control.
#
# Usage:
#   bash scripts/setup-host.sh                  # interactive
#   NTFY_URL=https://ntfy.example.com/topic \
#   NTFY_TOKEN=tk_xxx \
#     bash scripts/setup-host.sh               # non-interactive
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"
CLAUDE_DIR="$HOME/.claude"

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
step "Installing statusline script"
mkdir -p "$CLAUDE_DIR"
cp "$CONFIG_DIR/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
green "  ✓ $CLAUDE_DIR/statusline-command.sh"

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
echo "  ~/.claude/statusline-command.sh  — PS1-style statusline with context usage"
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
