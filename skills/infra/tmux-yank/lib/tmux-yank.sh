#!/usr/bin/env bash
# tmux-yank.sh — install tmux + TPM + tmux-yank end-to-end
set -euo pipefail

OS="$(uname -s)"

# --- 1. Install tmux ----------------------------------------------------------
if ! command -v tmux &>/dev/null; then
  echo "==> Installing tmux..."
  if [[ "$OS" == "Darwin" ]]; then
    brew install tmux
  elif [[ "$OS" == "Linux" ]]; then
    sudo apt-get update -qq && sudo apt-get install -y tmux
  else
    echo "ERROR: unsupported OS: $OS" >&2; exit 1
  fi
else
  echo "  tmux already installed ($(tmux -V))"
fi

# --- 2. Install clipboard backend (Linux only) --------------------------------
if [[ "$OS" == "Linux" ]]; then
  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    if ! command -v wl-copy &>/dev/null; then
      echo "==> Installing wl-clipboard (Wayland)..."
      sudo apt-get install -y wl-clipboard
    else
      echo "  wl-clipboard already installed"
    fi
  else
    if ! command -v xclip &>/dev/null; then
      echo "==> Installing xclip (X11)..."
      sudo apt-get install -y xclip
    else
      echo "  xclip already installed"
    fi
  fi
fi

# --- 3. Install TPM -----------------------------------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
  echo "==> Installing TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  echo "  TPM already installed"
fi

# --- 4. Ensure ~/.tmux.conf exists -------------------------------------------
TMUX_CONF="$HOME/.tmux.conf"
if [[ ! -f "$TMUX_CONF" ]]; then
  echo "==> ~/.tmux.conf not found — creating from repo template..."
  SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  if [[ -f "$SKILL_DIR/lib/tmux.conf.template" ]]; then
    cp "$SKILL_DIR/lib/tmux.conf.template" "$TMUX_CONF"
  else
    # Minimal fallback
    cat > "$TMUX_CONF" <<'EOF'
set -g mouse on
set -g mode-keys vi

# OSC 52 disabled: pbcopy is the authoritative clipboard path on macOS.
# Enabling set-clipboard causes OSC 52 to race with pbcopy and overwrite it.
set -g set-clipboard off

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @yank_action 'copy-pipe-and-cancel'

# Double/triple click → copy word/line to system clipboard (pbcopy)
bind-key -T root DoubleClick1Pane \
  select-pane -t = \; \
  if-shell -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" { send-keys -M } \
  { copy-mode -H ; send-keys -X select-word ; run-shell -d 0.3 ; send-keys -X copy-pipe-and-cancel "pbcopy" }
bind-key -T root TripleClick1Pane \
  select-pane -t = \; \
  if-shell -F "#{||:#{pane_in_mode},#{mouse_any_flag}}" { send-keys -M } \
  { copy-mode -H ; send-keys -X select-line ; run-shell -d 0.3 ; send-keys -X copy-pipe-and-cancel "pbcopy" }

run '~/.tmux/plugins/tpm/tpm'
EOF
  fi
  echo "  created $TMUX_CONF"
else
  # Ensure tmux-yank plugin line is present
  if ! grep -q "tmux-yank" "$TMUX_CONF"; then
    echo "==> Adding tmux-yank to existing ~/.tmux.conf..."
    # Insert before the tpm run line, or append
    if grep -q "run '~/.tmux/plugins/tpm/tpm'" "$TMUX_CONF"; then
      sed -i.bak "s|run '~/.tmux/plugins/tpm/tpm'|set -g @plugin 'tmux-plugins/tmux-yank'\nrun '~/.tmux/plugins/tpm/tpm'|" "$TMUX_CONF"
    else
      printf "\nset -g @plugin 'tmux-plugins/tmux-yank'\nrun '~/.tmux/plugins/tpm/tpm'\n" >> "$TMUX_CONF"
    fi
    echo "  patched $TMUX_CONF"
  else
    echo "  tmux-yank already in ~/.tmux.conf"
  fi
fi

# --- 5. Install plugins non-interactively ------------------------------------
echo "==> Installing tmux plugins..."
# Start a detached server if none is running
if ! tmux list-sessions &>/dev/null 2>&1; then
  tmux new-session -d -s _install
  KILL_SESSION=1
else
  KILL_SESSION=0
fi

tmux source-file "$TMUX_CONF" 2>/dev/null || true
"$TPM_DIR/bin/install_plugins"

if [[ "${KILL_SESSION:-0}" -eq 1 ]]; then
  tmux kill-session -t _install 2>/dev/null || true
fi

# --- 6. Verify ----------------------------------------------------------------
echo ""
echo "==> Verification"
echo "  tmux:      $(tmux -V)"
echo "  TPM:       $TPM_DIR"
if [[ -d "$HOME/.tmux/plugins/tmux-yank" ]]; then
  echo "  tmux-yank: installed"
else
  echo "  tmux-yank: MISSING — run 'prefix + I' inside tmux to install manually"
fi
echo ""
echo "Done. Restart tmux (or open a new session) for changes to take effect."
echo "In copy mode: press 'y' to copy selection to system clipboard."
