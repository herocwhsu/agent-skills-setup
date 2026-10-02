#!/usr/bin/env bash
# setup-tmux-conf.sh — the tmux step of setup-host.sh: appends the lines this
# repo needs to ~/.tmux.conf, only those not already there, never rewriting it.
# Tests: scripts/tests/test_setup_tmux_conf.sh (SETUP_TMUX_UNAME fakes the OS).
set -euo pipefail

TMUX_CONF="$HOME/.tmux.conf"
OS="${SETUP_TMUX_UNAME:-$(uname -s)}"

add_tmux_line() {
  local line="$1"
  if ! grep -qF "$line" "$TMUX_CONF" 2>/dev/null; then
    echo "$line" >> "$TMUX_CONF"
  fi
}

add_tmux_line "set -g mouse on"
# Use xclip on Linux, pbcopy on macOS
if [[ "$OS" == "Darwin" ]]; then
  add_tmux_line "bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel \"pbcopy\""
  add_tmux_line "bind -T copy-mode y send-keys -X copy-pipe-and-cancel \"pbcopy\""
  # tmux's default list minus SSH_CONNECTION. On an SSH attach tmux copies it
  # into the session and every new pane inherits it; agy then skips the login
  # keychain ("Using file-based token storage because SSH session detected")
  # and says "not logged in". The macOS tmux server runs in the GUI session, so
  # the keychain works from every pane. Linux keeps the default: there agy's
  # SSH rule is right, since no unlocked keyring is reachable over SSH.
  add_tmux_line "set -g update-environment \"DISPLAY KRB5CCNAME MSYSTEM SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID WAYLAND_DISPLAY WINDOWID XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE\""
else
  add_tmux_line "bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
  add_tmux_line "bind -T copy-mode y send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
fi
