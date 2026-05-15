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

# ---------------------------------------------------------------------------
# Registry-based install handlers
# ---------------------------------------------------------------------------

# install_pip_skill <package> <target_dir>
install_pip_skill() {
  local pkg="$1"
  local pip_cmd
  if command -v pip3 &>/dev/null; then
    pip_cmd="pip3"
  elif command -v pip &>/dev/null; then
    pip_cmd="pip"
  else
    echo "  pip not found — use github fallback for $pkg" >&2
    return 1
  fi
  "$pip_cmd" install --quiet --upgrade "$pkg"
  if command -v agent-superpowers &>/dev/null; then
    agent-superpowers install --skip-existing 2>/dev/null || true
  fi
  echo "  ✓ $pkg (pip)"
}

# install_github_skill <owner/repo> <skills-subpath> <target_dir>
install_github_skill() {
  local repo="$1" subpath="$2" target_dir="$3"
  local reponame="${repo##*/}"
  local zip extract branch_dir
  zip=$(mktemp /tmp/agent-skills-XXXXXX.zip)
  extract=$(mktemp -d /tmp/agent-skills-extract-XXXXXX)

  download_file "https://github.com/${repo}/archive/refs/heads/main.zip" "$zip" || {
    rm -f "$zip"; rm -rf "$extract"; return 1
  }
  unzip -q "$zip" -d "$extract"
  rm -f "$zip"

  branch_dir=$(find "$extract" -maxdepth 1 -type d -name "${reponame}-*" | head -1)
  if [[ -z "$branch_dir" ]]; then
    echo "  ERROR: extracted dir not found for $repo" >&2
    rm -rf "$extract"; return 1
  fi

  local src_dir="${branch_dir}/${subpath}"
  if [[ ! -d "$src_dir" ]]; then
    echo "  ERROR: subpath '$subpath' not found in $repo" >&2
    rm -rf "$extract"; return 1
  fi

  mkdir -p "$target_dir"
  local count=0
  for skill_dir in "$src_dir"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    cp -r "$skill_dir" "$target_dir/$skill_name"
    count=$((count + 1))
  done
  rm -rf "$extract"
  echo "  ✓ $repo ($count skills)"
}

# install_local_skill <skill_name> <repo_dir> <target_dir>
install_local_skill() {
  local name="$1" repo_dir="$2" target_dir="$3"
  local src="${repo_dir}/skills/${name}"
  if [[ ! -d "$src" ]]; then
    echo "  WARNING: local skill '$name' not found at $src" >&2
    return 1
  fi
  install_skill "$src" "$target_dir"
}

# ---------------------------------------------------------------------------
# Registry-based uninstall handlers
# ---------------------------------------------------------------------------

# uninstall_pip_skill <package>
uninstall_pip_skill() {
  local pkg="$1"
  local pip_cmd
  if command -v pip3 &>/dev/null; then pip_cmd="pip3"
  elif command -v pip &>/dev/null; then pip_cmd="pip"
  else return 0; fi
  "$pip_cmd" uninstall -y "$pkg" 2>/dev/null || true
  echo "  ✓ $pkg (pip uninstalled)"
}

# uninstall_github_skill <owner/repo> <skills-subpath> <target_dir>
# Re-fetches zip to determine which skill dirs to remove.
uninstall_github_skill() {
  local repo="$1" subpath="$2" target_dir="$3"
  local reponame="${repo##*/}"
  local zip extract branch_dir
  zip=$(mktemp /tmp/agent-skills-XXXXXX.zip)
  extract=$(mktemp -d /tmp/agent-skills-extract-XXXXXX)

  download_file "https://github.com/${repo}/archive/refs/heads/main.zip" "$zip" || {
    echo "  WARNING: could not fetch $repo; skipping uninstall." >&2
    rm -f "$zip"; rm -rf "$extract"; return 0
  }
  unzip -q "$zip" -d "$extract"
  rm -f "$zip"

  branch_dir=$(find "$extract" -maxdepth 1 -type d -name "${reponame}-*" | head -1)
  local src_dir="${branch_dir}/${subpath}"
  local count=0
  if [[ -d "$src_dir" ]]; then
    for skill_dir in "$src_dir"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      remove_skill "$skill_name" "$target_dir"
      count=$((count + 1))
    done
  fi
  rm -rf "$extract"
  echo "  ✓ $repo ($count skills removed)"
}

# uninstall_local_skill <skill_name> <target_dir>
uninstall_local_skill() {
  local name="$1" target_dir="$2"
  remove_skill "$name" "$target_dir"
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
