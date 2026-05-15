#!/usr/bin/env bash
# _lib.sh — shared helpers for install/uninstall/update/setup scripts
# Source this file: source "$(dirname "$0")/_lib.sh"

# Detect OS type
# Returns: darwin | linux-gui | linux-headless | windows
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)
      if command -v secret-tool &>/dev/null; then
        echo "linux-gui"
      else
        echo "linux-headless"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}

# Check if a command exists; print warning if not
# Usage: check_cmd curl "install curl via: brew install curl"
check_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    echo "WARNING: '$cmd' not found.${hint:+ $hint}" >&2
    return 1
  fi
}

# Download a URL to a file; tries curl then wget
# Usage: download_file <url> <dest>
download_file() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -q "$url" -O "$dest"
  else
    echo "ERROR: neither curl nor wget found. Install one and retry." >&2
    return 1
  fi
}

# Agent skills directory for a given agent name
# Usage: agent_skills_dir kiro
agent_skills_dir() {
  local agent="$1"
  case "$agent" in
    kiro)    echo "$HOME/.kiro/skills" ;;
    claude)  echo "$HOME/.claude/skills" ;;
    copilot) echo "$HOME/.copilot/skills" ;;
    codex)   echo "$HOME/.codex/skills" ;;
    *)       echo "" ;;
  esac
}

# Install a single skill dir into a target skills dir
# Uses symlink on Unix, copy on Windows
# Usage: install_skill <skill_src_dir> <skills_target_dir>
install_skill() {
  local src="$1" target_dir="$2"
  local name
  name=$(basename "$src")
  mkdir -p "$target_dir"
  if [[ "$(detect_os)" == "windows" ]]; then
    cp -r "$src" "$target_dir/$name"
  else
    ln -sfn "$src" "$target_dir/$name"
  fi
  echo "  ✓ $name"
}

# Remove a single skill from a target skills dir (safe: only removes if it's
# a symlink pointing into this repo, or a dir — never touches unrelated files)
# Usage: remove_skill <skill_name> <skills_target_dir>
remove_skill() {
  local name="$1" target_dir="$2"
  local path="$target_dir/$name"
  if [[ -L "$path" ]] || [[ -d "$path" ]]; then
    rm -rf "$path"
    echo "  ✓ removed $name"
  fi
}

AGENTS=("kiro" "claude" "copilot" "codex")

# Prompt user to select one or more agents
# Sets global SELECTED_AGENTS array
select_agents() {
  echo ""
  echo "Which agent(s) to target?"
  echo "  1) Kiro        (~/.kiro/skills/)"
  echo "  2) Claude Code (~/.claude/skills/)"
  echo "  3) Copilot     (~/.copilot/skills/)"
  echo "  4) Codex       (~/.codex/skills/)"
  echo "  5) All of the above"
  echo ""
  read -rp "Choice [1-5]: " choice
  case "$choice" in
    1) SELECTED_AGENTS=("kiro") ;;
    2) SELECTED_AGENTS=("claude") ;;
    3) SELECTED_AGENTS=("copilot") ;;
    4) SELECTED_AGENTS=("codex") ;;
    5) SELECTED_AGENTS=("kiro" "claude" "copilot" "codex") ;;
    *) echo "Invalid choice, defaulting to kiro."; SELECTED_AGENTS=("kiro") ;;
  esac
}
