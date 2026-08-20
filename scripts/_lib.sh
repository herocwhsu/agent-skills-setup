#!/usr/bin/env bash
# _lib.sh — shared helpers for install/uninstall/update/setup scripts
# Source this file: source "$(dirname "$0")/_lib.sh"

# Detect OS type
# Returns: darwin | linux | unknown
#
# Windows was dropped 2026-08-20. It was carried as a parallel PowerShell
# implementation (install.ps1, setup-credentials.ps1, _store.ps1) that no test
# and no CI job ever executed, on any machine — so it was support in name only,
# and it had already silently diverged from the bash side. Supported targets
# are Linux and macOS, on x86_64 and arm64 alike; nothing here fetches an
# arch-specific binary (GitHub source archives and npm packages only) and every
# external tool is located with `command -v`, never a hardcoded prefix, so
# Apple Silicon's /opt/homebrew and Intel's /usr/local both just work.
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

# Abort with a clear message on an unsupported OS, rather than half-installing.
# A Windows user running this under Git Bash previously got `linux`-ish
# behaviour from some helpers and Windows behaviour from others.
require_supported_os() {
  local os; os=$(detect_os)
  if [[ "$os" == "unknown" ]]; then
    echo "ERROR: unsupported platform '$(uname -s) $(uname -m)'." >&2
    echo "       Supported: Linux and macOS (x86_64 or arm64)." >&2
    echo "       Windows support was removed 2026-08-20 — see README." >&2
    return 1
  fi
  return 0
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
    gemini)  echo "$HOME/.gemini/antigravity-cli/skills" ;;
    codex)   echo "$HOME/.codex/skills" ;;
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

# install_kiro_agent_config <skills_target_dir>
#   Write ~/.kiro/agents/default.json with the correct name and resource list.
#   Lists every SKILL.md found under the skills dir (symlink-following).
#   Idempotent: overwrites on every install to pick up new/removed groups.
install_kiro_agent_config() {
  local skills_dir="$1"
  local agents_dir="$HOME/.kiro/agents"
  local out="$agents_dir/default.json"
  local steering_entry='    "file://~/.kiro/steering/engineering-rules.md"'

  mkdir -p "$agents_dir"

  # Collect SKILL.md paths under skills_dir (follow symlinks), sort
  local entries=()
  entries+=("$steering_entry")
  while IFS= read -r skill_md; do
    [[ -n "$skill_md" ]] || continue
    local rel="${skill_md/#$HOME/~}"
    entries+=("    \"skill://$rel\"")
  done < <(find -L "$skills_dir" -maxdepth 2 -name "SKILL.md" 2>/dev/null | sort)

  local count="${#entries[@]}"

  # Write JSON without negative array index (bash 3.2 compat)
  {
    echo '{'
    echo '    "name": "kiro_default",'
    echo '    "description": "Default Kiro agent with spec-gated workflow skills.",'
    echo '    "resources": ['
    local i=0
    for entry in "${entries[@]}"; do
      i=$((i + 1))
      if [[ "$i" -eq "$count" ]]; then
        echo "$entry"
      else
        echo "$entry,"
      fi
    done
    echo '    ]'
    echo '}'
  } > "$out"

  python3 -c "import json; json.load(open('$out'))" 2>/dev/null \
    || { echo "  ERROR: generated $out is invalid JSON" >&2; return 1; }

  echo "  ✓ kiro agent config → $out ($count resources)"
}
# Usage: install_skill <skill_src_dir> <skills_target_dir>
# Always a symlink: both supported platforms have them, and a link keeps the
# installed skill tracking the repo instead of going stale as a copy would.
install_skill() {
  local src="$1" target_dir="$2"
  local name
  name=$(basename "$src")
  mkdir -p "$target_dir"
  ln -sfn "$src" "$target_dir/$name"
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

  download_file "https://github.com/${repo}/archive/HEAD.zip" "$zip" || {
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

# install_github_single_skill <owner/repo> <skill-path> <target_dir> [name]
#   Install exactly one skill directory from a GitHub repo (vs.
#   install_github_skill, which installs every dir under the subpath).
#   <skill-path> is the skill dir inside the repo; "." means the repo root
#   itself is the skill. [name] overrides the installed dir name; defaults
#   to basename of <skill-path>, or the repo name when skill-path is ".".
install_github_single_skill() {
  local repo="$1" skill_path="$2" target_dir="$3" name="${4:-}"
  local reponame="${repo##*/}"

  if [[ -z "$name" ]]; then
    if [[ "$skill_path" == "." ]]; then
      name="$reponame"
    else
      name=$(basename "$skill_path")
    fi
  fi

  local zip extract branch_dir
  zip=$(mktemp /tmp/agent-skills-XXXXXX.zip)
  extract=$(mktemp -d /tmp/agent-skills-extract-XXXXXX)

  download_file "https://github.com/${repo}/archive/HEAD.zip" "$zip" || {
    rm -f "$zip"; rm -rf "$extract"; return 1
  }
  unzip -q "$zip" -d "$extract"
  rm -f "$zip"

  branch_dir=$(find "$extract" -maxdepth 1 -type d -name "${reponame}-*" | head -1)
  if [[ -z "$branch_dir" ]]; then
    echo "  ERROR: extracted dir not found for $repo" >&2
    rm -rf "$extract"; return 1
  fi

  local src_dir="${branch_dir}/${skill_path}"
  if [[ ! -d "$src_dir" ]]; then
    echo "  ERROR: skill path '$skill_path' not found in $repo" >&2
    rm -rf "$extract"; return 1
  fi
  if [[ ! -f "$src_dir/SKILL.md" ]]; then
    echo "  WARNING: no SKILL.md at '$skill_path' in $repo — installing anyway" >&2
  fi

  mkdir -p "$target_dir"
  rm -rf "${target_dir:?}/${name}"
  cp -r "$src_dir" "$target_dir/$name"
  record_installed "$name"
  rm -rf "$extract"
  echo "  ✓ $repo → $name"
}

# install_claude_plugin <owner/repo> <plugin-name> [marketplace-name]
#   Install a Claude Code plugin via the claude CLI. Claude-Code-only —
#   callers must gate on agent == claude. [marketplace-name] defaults to the
#   repo name; pass it when the repo's marketplace.json declares a different
#   name (e.g. anthropics/skills → anthropic-agent-skills).
install_claude_plugin() {
  local repo="$1" plugin="$2" marketplace="${3:-${1##*/}}"
  if ! command -v claude &>/dev/null; then
    echo "  claude CLI not found — skipping plugin ${plugin}" >&2
    return 0
  fi
  # marketplace add errors when already added — safe to ignore
  claude plugin marketplace add "$repo" >/dev/null 2>&1 || true
  if claude plugin install "${plugin}@${marketplace}" >/dev/null 2>&1; then
    echo "  ✓ ${plugin}@${marketplace} (claude plugin)"
  else
    echo "  WARNING: claude plugin install ${plugin}@${marketplace} failed — install manually via /plugin menu" >&2
  fi
  return 0
}

# is_plugin_opt_in <plugin-name>
#   True if <plugin-name> is present in the caller's PLUGIN_OPT_IN array
#   (populated by install.sh from repeated --with-plugin flags). Used to
#   gate "plugin-optional" registry entries, which are skipped by default.
is_plugin_opt_in() {
  local name="$1" p
  [[ ${#PLUGIN_OPT_IN[@]} -eq 0 ]] && return 1
  for p in "${PLUGIN_OPT_IN[@]}"; do
    [[ "$p" == "$name" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# prune_dead_skill_links <target_dir> <repo_dir>
#
# Remove symlinks in the agent's skills dir that point into this repo's skills/
# and no longer resolve. Installing is purely additive, and both uninstall.sh
# and the installed.txt manifest are driven from registry.txt, so a skill
# DROPPED from the registry leaves a dangling link that nothing ever cleans:
# after the 561abae regrouping, seven sat in ~/.claude/skills and eight in
# ~/.codex/skills. An agent listing its skills dir sees those names and cannot
# read them.
#
# Deliberately narrow — only broken links whose target is under repo_dir. A
# user's own symlinks, and every real directory, are left alone.
prune_dead_skill_links() {
  local target_dir="$1" repo_dir="$2"
  [[ -d "$target_dir" ]] || return 0
  local link target n=0
  while IFS= read -r -d '' link; do
    target=$(readlink "$link")
    [[ "$target" == "$repo_dir"/skills/* ]] || continue
    rm -f "$link"
    echo "  pruned dead link: $(basename "$link") -> $target"
    n=$((n+1))
    # `command find`: Claude Code installs a shell FUNCTION named find that
    # routes through its native binary, and when that binary is broken the
    # wrapper prints an error and returns nothing — silently, with status 0.
    # Exported into a script it would make this prune a no-op that reports
    # success. Bit me while verifying this very function on 2026-08-20.
  done < <(command find "$target_dir" -maxdepth 1 -xtype l -print0)
  [[ $n -eq 0 ]] || echo "  ($n dead link(s) removed from $target_dir)"
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

# install_local_optional_skill <skill_name> <repo_dir> <target_dir>
#   Like install_local_skill but silently skips when the skill dir is absent.
#   Use for host-specific or optional skills that may not exist on all machines.
install_local_optional_skill() {
  local name="$1" repo_dir="$2" target_dir="$3"
  local src="${repo_dir}/skills/${name}"
  if [[ ! -d "$src" ]]; then
    echo "  skipping optional skill '$name' (not present on this host)" >&2
    return 0
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

  download_file "https://github.com/${repo}/archive/HEAD.zip" "$zip" || {
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

# uninstall_github_single_skill <owner/repo> <skill-path> <target_dir> [name]
#   Removes the single skill by its resolved name — no network needed.
uninstall_github_single_skill() {
  local repo="$1" skill_path="$2" target_dir="$3" name="${4:-}"
  local reponame="${repo##*/}"
  if [[ -z "$name" ]]; then
    if [[ "$skill_path" == "." ]]; then
      name="$reponame"
    else
      name=$(basename "$skill_path")
    fi
  fi
  remove_skill "$name" "$target_dir"
}

# uninstall_claude_plugin <owner/repo> <plugin-name> [marketplace-name]
uninstall_claude_plugin() {
  local repo="$1" plugin="$2" marketplace="${3:-${1##*/}}"
  command -v claude &>/dev/null || return 0
  claude plugin uninstall "${plugin}@${marketplace}" >/dev/null 2>&1 || true
  echo "  ✓ ${plugin}@${marketplace} (claude plugin removed)"
}

# uninstall_local_skill <skill_name> <target_dir>
uninstall_local_skill() {
  local name="$1" target_dir="$2"
  remove_skill "$name" "$target_dir"
}

# uninstall_local_optional_skill <skill_name> <target_dir>
uninstall_local_optional_skill() {
  local name="$1" target_dir="$2"
  remove_skill "$name" "$target_dir"
}

AGENTS=("kiro" "claude" "gemini" "codex")

# Accept agent via $1 (kiro|claude|gemini|codex|all, or a comma-separated list
# such as "claude,codex"). Prompt only if empty.
# Sets global SELECTED_AGENTS array.
#
# The list form exists because a host can legitimately run more than one agent
# and only one of them was ever kept up to date: install.sh records the choice
# for update.sh to replay, that record held a single token, so on a claude+codex
# host update.sh silently refreshed whichever was installed last and let the
# other rot. Found 2026-08-20 with ~/.codex/skills 11 weeks stale.
select_agents() {
  local choice="${1:-}"

  if [[ -z "$choice" ]]; then
    echo ""
    echo "Which agent(s) to target?"
    echo "  1) Kiro IDE    (~/.kiro/skills/)"
    echo "  2) Claude Code (~/.claude/skills/)"
    echo "  3) Antigravity CLI (~/.gemini/antigravity-cli/skills/)"
    echo "  4) Codex CLI   (~/.codex/skills/)"
    echo "  5) All of the above"
    echo ""
    echo "  (or type a comma-separated list, e.g. claude,codex)"
    echo ""
    read -rp "Choice [1-5 or list]: " input
    # Bare Enter (or EOF) keeps the long-standing default. A *typo*, by
    # contrast, no longer silently becomes claude — it is parsed as an agent
    # list and rejected below.
    [[ -n "$input" ]] || input=2
    case "$input" in
      1) choice="kiro" ;;
      2) choice="claude" ;;
      3) choice="gemini" ;;
      4) choice="codex" ;;
      5) choice="all" ;;
      # Not an error: anything else is treated as a literal agent list and
      # validated below, so "claude,codex" at the prompt works too.
      *) choice="$input" ;;
    esac
  fi

  local -a requested=()
  local a seen
  IFS=',' read -ra requested <<< "$choice"

  SELECTED_AGENTS=()
  for a in "${requested[@]}"; do
    a="${a//[[:space:]]/}"
    [[ -n "$a" ]] || continue
    if [[ "$a" == "all" ]]; then
      SELECTED_AGENTS=("${AGENTS[@]}")
      break
    fi
    # Validate against the agent list, so adding an agent needs one edit here.
    printf '%s\n' "${AGENTS[@]}" | grep -qx -- "$a" \
      || { echo "Invalid agent: $a (valid: ${AGENTS[*]}, all)" >&2; exit 1; }
    # De-duplicate: "claude,claude" must not install twice.
    seen=""
    for existing in "${SELECTED_AGENTS[@]:-}"; do
      [[ "$existing" == "$a" ]] && seen=1 && break
    done
    [[ -n "$seen" ]] || SELECTED_AGENTS+=("$a")
  done

  [[ ${#SELECTED_AGENTS[@]} -gt 0 ]] \
    || { echo "No agent selected (got: '$choice')" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# wire_hook <skill_name> <repo_dir> <agent_name>
#   Merge a skill's hook.json into the agent's settings.json.
# ---------------------------------------------------------------------------
wire_hook() {
  local skill="$1" repo_dir="$2" agent="${3:-claude}"
  local hook_path settings

  # polish-input is unsupported on gemini (Antigravity CLI). Its OAuth
  # subscription token can only be spent through the agy agent loop, not a
  # text-in/text-out endpoint: the public Generative Language API rejects the
  # token (403 insufficient scope) and cloudcode-pa returns 403
  # SUBSCRIPTION_REQUIRED (#3501, enterprise-license-gated). With no reachable
  # low-latency backend the hook would only ever fail open, so skip wiring it.
  if [[ "$skill" == "polish-input" && "$agent" == "gemini" ]]; then
    echo "  polish-input unsupported on gemini (no reachable low-latency backend) — skipped" >&2
    return 0
  fi

  # Codex has no settings.json hook mechanism at all — it configures via
  # ~/.codex/config.toml, which has no equivalent of Claude Code's hook events.
  # Skipped explicitly rather than falling through: the case below defaults
  # unknown agents to Claude's settings.json, so without this a codex target
  # would silently install its hooks into Claude Code's config instead.
  if [[ "$agent" == "codex" ]]; then
    echo "  hooks unsupported on codex (no settings.json equivalent) — skipped" >&2
    return 0
  fi

  # Try flat path first (legacy), then search one level deep (group/subcommand layout).
  if [[ -f "$repo_dir/skills/$skill/hook.json" ]]; then
    hook_path="$repo_dir/skills/$skill/hook.json"
  else
    # Search for hook.json inside any group subdirectory.
    hook_path=$(find "$repo_dir/skills" -maxdepth 3 -name "hook.json" \
      -path "*/$skill/hook.json" 2>/dev/null | head -1)
  fi

  case "$agent" in
    gemini)      settings="$HOME/.gemini/antigravity-cli/settings.json" ;;
    claude|kiro) settings="$HOME/.claude/settings.json" ;;
    *)           echo "  ERROR: no hook settings path known for agent '$agent'" >&2; return 1 ;;
  esac

  if [[ -z "$hook_path" || ! -f "$hook_path" ]]; then
    echo "  ERROR: $skill has no hook.json (searched flat and group layouts)" >&2
    return 1
  fi

  if [[ "$skill" == "polish-input" ]]; then
    # Only non-gemini agents reach here (gemini+polish-input is skipped above),
    # so the required SDK is always the Anthropic client.
    local pkg="anthropic"

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
    gemini)      settings="$HOME/.gemini/antigravity-cli/settings.json" ;;
    claude|kiro) settings="$HOME/.claude/settings.json" ;;
    *)           echo "  ERROR: no hook settings path known for agent '$agent'" >&2; return 1 ;;
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
