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
    gemini)  echo "$HOME/.gemini/skills" ;;
    *)       echo "" ;;
  esac
}

# install_kiro_prompts <repo_dir>
#   Copy prompts/*.md to ~/.kiro/prompts/, substituting <user> with $USER.
#   Idempotent: copies every file in prompts/, overwriting old versions.
install_kiro_prompts() {
  local repo_dir="$1"
  local src="$repo_dir/prompts"
  local target="$HOME/.kiro/prompts"
  [[ -d "$src" ]] || return 0
  mkdir -p "$target"
  local count=0
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    local dest="$target/$(basename "$f")"
    sed "s|/Users/<user>|$HOME|g" "$f" > "$dest"
    count=$((count + 1))
  done
  echo "  ✓ kiro prompts ($count files) → $target"
}

# uninstall_kiro_prompts <repo_dir>
#   Remove prompt files this repo installed from ~/.kiro/prompts/.
#   Only removes files that still exist in the repo's prompts/ dir.
uninstall_kiro_prompts() {
  local repo_dir="$1"
  local src="$repo_dir/prompts"
  local target="$HOME/.kiro/prompts"
  [[ -d "$src" ]] || return 0
  [[ -d "$target" ]] || return 0
  local count=0
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    local dest="$target/$(basename "$f")"
    if [[ -f "$dest" ]]; then
      rm "$dest"
      count=$((count + 1))
    fi
  done
  echo "  ✓ removed kiro prompts ($count files)"
}
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
  record_installed "$name"
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
# Only installs the pip package itself (for future use).
# Skill files are installed via install_github_skill — avoids interactive prompts.
install_pip_skill() {
  local pkg="$1"
  local pip_cmd
  if command -v pip3 &>/dev/null; then
    pip_cmd="pip3"
  elif command -v pip &>/dev/null; then
    pip_cmd="pip"
  else
    echo "  pip not found — skipping pip install for $pkg" >&2
    return 0
  fi
  "$pip_cmd" install --quiet --upgrade "$pkg" 2>/dev/null || true
  echo "  ✓ $pkg (pip package updated)"
}

# install_npm_skill <package>
# Globally install an npm package (e.g. @fission-ai/openspec).
# Idempotent: npm install -g upgrades to latest if already present.
install_npm_skill() {
  local pkg="$1"
  if ! command -v npm &>/dev/null; then
    echo "  npm not found — skipping npm install for $pkg" >&2
    echo "    Install Node.js + npm to enable: https://nodejs.org/" >&2
    return 0
  fi
  npm install -g "$pkg" 2>/dev/null || {
    echo "  WARNING: npm install -g $pkg failed (try: sudo npm install -g $pkg)" >&2
    return 0
  }
  echo "  ✓ $pkg (npm package installed/updated)"
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
    record_installed "$skill_name"
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
# install_runtime_dir <repo_dir>
#   Create ~/.agent-skills-setup/ and copy runtime files (lib.sh, _store.sh)
#   into it. Idempotent.
# ---------------------------------------------------------------------------
install_runtime_dir() {
  local repo_dir="$1"
  local rtdir="$HOME/.agent-skills-setup"
  mkdir -p "$rtdir"
  cp -f "$repo_dir/lib/lib.sh" "$rtdir/lib.sh"
  cp -f "$repo_dir/scripts/credentials/_store.sh" "$rtdir/_store.sh"
  echo "  ✓ runtime → $rtdir"
}

# ---------------------------------------------------------------------------
# record_installed <skill_name>
#   Append a skill name to ~/.agent-skills-setup/installed.txt for offline
#   uninstall. No-op if INSTALLED_LIST is unset.
# ---------------------------------------------------------------------------
record_installed() {
  [[ -n "${INSTALLED_LIST:-}" ]] || return 0
  local name="$1"
  if [[ -f "$INSTALLED_LIST" ]] && grep -Fxq "$name" "$INSTALLED_LIST"; then
    return 0
  fi
  echo "$name" >> "$INSTALLED_LIST"
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

# uninstall_npm_skill <package>
uninstall_npm_skill() {
  local pkg="$1"
  if ! command -v npm &>/dev/null; then return 0; fi
  npm uninstall -g "$pkg" 2>/dev/null || true
  echo "  ✓ $pkg (npm uninstalled)"
}

# uninstall_github_skill <owner/repo> <skills-subpath> <target_dir>
# Reads ~/.agent-skills-setup/installed.txt to know which skills to remove.
# Falls back to network re-fetch only if installed.txt is missing.
uninstall_github_skill() {
  local repo="$1" subpath="$2" target_dir="$3"
  local list="$HOME/.agent-skills-setup/installed.txt"

  if [[ -f "$list" ]]; then
    local count=0
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      if [[ -d "$target_dir/$skill_name" || -L "$target_dir/$skill_name" ]]; then
        remove_skill "$skill_name" "$target_dir"
        count=$((count + 1))
      fi
    done < "$list"
    echo "  ✓ $repo ($count skills removed via installed.txt)"
    return 0
  fi

  # Fallback: network path (legacy behavior preserved for safety)
  echo "  WARNING: $list missing — falling back to network re-fetch" >&2
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
  echo "  ✓ $repo ($count skills removed via fallback)"
}

# uninstall_local_skill <skill_name> <target_dir>
uninstall_local_skill() {
  local name="$1" target_dir="$2"
  remove_skill "$name" "$target_dir"
}

AGENTS=("kiro" "claude" "gemini")

# Accept agent via $1 (kiro|claude|gemini|all). Prompt only if empty.
# Sets global SELECTED_AGENTS array.
select_agents() {
  local choice="${1:-}"

  if [[ -z "$choice" ]]; then
    echo ""
    echo "Which agent(s) to target?"
    echo "  1) Kiro IDE    (~/.kiro/skills/)"
    echo "  2) Claude Code (~/.claude/skills/)"
    echo "  3) Gemini CLI  (~/.gemini/skills/)"
    echo "  4) All of the above"
    echo ""
    read -rp "Choice [1-4]: " input
    case "$input" in
      1) choice="kiro" ;;
      2) choice="claude" ;;
      3) choice="gemini" ;;
      4) choice="all" ;;
      *) echo "Invalid choice, defaulting to claude."; choice="claude" ;;
    esac
  fi

  case "$choice" in
    kiro)    SELECTED_AGENTS=("kiro") ;;
    claude)  SELECTED_AGENTS=("claude") ;;
    gemini)  SELECTED_AGENTS=("gemini") ;;
    all)     SELECTED_AGENTS=("kiro" "claude" "gemini") ;;
    *)       echo "Invalid agent: $choice"; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# wire_hook <skill_name> <repo_dir> <agent_name>
#   Merge a skill's hook.json into the agent's settings.json.
# ---------------------------------------------------------------------------
wire_hook() {
  local skill="$1" repo_dir="$2" agent="${3:-claude}"
  local hook_path settings

  # Try flat path first (legacy), then search one level deep (group/subcommand layout).
  if [[ -f "$repo_dir/skills/$skill/hook.json" ]]; then
    hook_path="$repo_dir/skills/$skill/hook.json"
  else
    # Search for hook.json inside any group subdirectory.
    hook_path=$(find "$repo_dir/skills" -maxdepth 3 -name "hook.json" \
      -path "*/$skill/hook.json" 2>/dev/null | head -1)
  fi

  case "$agent" in
    gemini) settings="$HOME/.gemini/settings.json" ;;
    *)      settings="$HOME/.claude/settings.json" ;;
  esac

  if [[ -z "$hook_path" || ! -f "$hook_path" ]]; then
    echo "  ERROR: $skill has no hook.json (searched flat and group layouts)" >&2
    return 1
  fi

  if [[ "$skill" == "polish-input" ]]; then
    local pkg="anthropic"
    if [[ "$agent" == "gemini" ]]; then
      pkg="google-generativeai google-auth"
    fi

    echo "  Installing required SDK via pip..."
    local pip_cmd
    if command -v pip3 &>/dev/null; then
      pip_cmd="pip3"
    elif command -v pip &>/dev/null; then
      pip_cmd="pip"
    else
      echo "  WARNING: pip not found — skipping SDK install" >&2
      pip_cmd=""
    fi
    if [[ -n "$pip_cmd" ]]; then
      "$pip_cmd" install --user --quiet $pkg --break-system-packages 2>/dev/null || {
        echo "  WARNING: $pip_cmd install $pkg failed. Hook will fail open." >&2
      }
    fi
  fi

  echo "  Merging $skill hook into $settings..."
  local skills_dir
  skills_dir=$(agent_skills_dir "$agent")
  local tmp_hook
  tmp_hook=$(mktemp /tmp/hook-XXXXXX.json)
  sed "s|\${AGENT_SKILLS_DIR}|${skills_dir}|g" "$hook_path" > "$tmp_hook"
  python3 "$repo_dir/scripts/_settings_merge.py" --merge "$tmp_hook" "$settings"
  rm -f "$tmp_hook"
  echo "  Hook wired."
}

# ---------------------------------------------------------------------------
# unwire_hook <skill_name> <repo_dir> <agent_name>
#   Remove a skill's hook entry from the agent's settings.json. Idempotent.
# ---------------------------------------------------------------------------
unwire_hook() {
  local skill="$1" repo_dir="$2" agent="${3:-claude}"
  local hook_path settings

  # Try flat path first (legacy), then search one level deep (group/subcommand layout).
  if [[ -f "$repo_dir/skills/$skill/hook.json" ]]; then
    hook_path="$repo_dir/skills/$skill/hook.json"
  else
    hook_path=$(find "$repo_dir/skills" -maxdepth 3 -name "hook.json" \
      -path "*/$skill/hook.json" 2>/dev/null | head -1)
  fi

  case "$agent" in
    gemini) settings="$HOME/.gemini/settings.json" ;;
    *)      settings="$HOME/.claude/settings.json" ;;
  esac

  if [[ -z "$hook_path" || ! -f "$hook_path" ]]; then
    echo "  WARNING: $skill has no hook.json; nothing to remove." >&2
    return 0
  fi
  if [[ ! -f "$settings" ]]; then
    echo "  No $settings; nothing to remove."
    return 0
  fi

  echo "  Removing $skill hook from $settings..."
  local skills_dir
  skills_dir=$(agent_skills_dir "$agent")
  local tmp_hook
  tmp_hook=$(mktemp /tmp/hook-XXXXXX.json)
  sed "s|\${AGENT_SKILLS_DIR}|${skills_dir}|g" "$hook_path" > "$tmp_hook"
  python3 "$repo_dir/scripts/_settings_merge.py" --remove "$tmp_hook" "$settings"
  rm -f "$tmp_hook"
}
