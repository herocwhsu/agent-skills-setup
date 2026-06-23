---
name: infra-tmux-yank
description: Install tmux + TPM + tmux-yank for system clipboard integration on macOS and Linux. Fully automated.
---

# /infra-tmux-yank

Set up tmux clipboard integration end-to-end. Handles everything automatically:
installs tmux, TPM, clipboard backend (platform-specific), and the tmux-yank plugin.

## Usage

Ask Claude to:
- "Set up tmux clipboard" → runs the install script
- "Install tmux-yank" → same

Claude will call:
```bash
bash ~/.claude/skills/infra/tmux-yank/lib/tmux-yank.sh
```

## What it does (in order)

| Step | Action |
|---|---|
| 1 | Install tmux if missing (brew on macOS, apt on Linux) |
| 2 | Install clipboard backend on Linux (xclip for X11, wl-clipboard for Wayland) |
| 3 | Install TPM to `~/.tmux/plugins/tpm` |
| 4 | Create `~/.tmux.conf` if missing, or patch existing one to add tmux-yank |
| 5 | Install all plugins non-interactively via TPM |
| 6 | Verify and report |

## Platform clipboard backends

| Platform | Backend | Installed by |
|---|---|---|
| macOS | `pbcopy` / `pbpaste` | built-in |
| Linux X11 | `xclip` | script |
| Linux Wayland | `wl-copy` | script |

> **Note:** `set-clipboard on` (OSC 52) is intentionally disabled on macOS. Enabling it causes the terminal's OSC 52 handler to race with `pbcopy` and overwrite the clipboard with a different value. `pbcopy` is the sole clipboard path on macOS.

## After setup

| Action | Binding |
|---|---|
| Enter copy mode | `prefix + Enter` |
| Start selection | `v` |
| Copy to system clipboard | `y` |
| Copy current command | `Y` |
| Mouse drag to select | auto-copies to system clipboard |
| Double-click word | auto-copies word to system clipboard |
| Triple-click line | auto-copies line to system clipboard |
