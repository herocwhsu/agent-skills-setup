---
name: infra-tmux-yank
description: Set up tmux + TPM + tmux-yank for system clipboard integration on macOS and Linux
---

# /infra-tmux-yank

Install tmux, TPM, and tmux-yank so copy-mode selections sync to the system
clipboard on macOS (pbcopy), Linux X11 (xclip/xsel), and Wayland (wl-copy).
Also enables OSC 52 passthrough for clipboard over SSH.

## Steps

### 1 — Detect OS and install tmux

```bash
OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
  if ! command -v tmux &>/dev/null; then
    brew install tmux
  fi
elif [[ "$OS" == "Linux" ]]; then
  if ! command -v tmux &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y tmux
  fi
  # Install clipboard backend
  if [[ -n "$WAYLAND_DISPLAY" ]]; then
    sudo apt-get install -y wl-clipboard
  else
    sudo apt-get install -y xclip
  fi
fi
echo "tmux $(tmux -V)"
```

### 2 — Install TPM

```bash
if [[ ! -d ~/.tmux/plugins/tpm ]]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  echo "TPM installed"
else
  echo "TPM already present"
fi
```

### 3 — Verify ~/.tmux.conf has tmux-yank

Confirm these lines are present in `~/.tmux.conf` (the repo's tmux.conf
already includes them):

```
set -g @plugin 'tmux-plugins/tmux-yank'
run '~/.tmux/plugins/tpm/tpm'
```

### 4 — Install plugins

If tmux is already running:
```bash
tmux source ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins
```

If starting fresh, start a server and install:
```bash
tmux new-session -d -s _setup
tmux source-file ~/.tmux.conf
~/.tmux/plugins/tpm/bin/install_plugins
tmux kill-session -t _setup
```

### 5 — Verify

```bash
ls ~/.tmux/plugins/tmux-yank/ && echo "tmux-yank installed"
```

## Usage after setup

| Action | Binding |
|---|---|
| Enter copy mode | `prefix + Enter` |
| Start selection | `v` |
| Copy to system clipboard | `y` |
| Copy current command line | `Y` |
| Mouse drag + copy | drag then `y` |
| Paste (outside tmux) | `Cmd+V` / `Ctrl+Shift+V` |

## Platform notes

| Platform | Clipboard backend | Extra package |
|---|---|---|
| macOS | `pbcopy` / `pbpaste` | none (built-in) |
| Linux X11 | `xclip` | `apt install xclip` |
| Linux Wayland | `wl-copy` | `apt install wl-clipboard` |
| SSH (OSC 52) | terminal passthrough | iTerm2, WezTerm, Alacritty, Ghostty |
