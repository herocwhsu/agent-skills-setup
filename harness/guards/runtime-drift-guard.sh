#!/usr/bin/env bash
# runtime-drift-guard.sh — Stop/SubagentStop hook: block when installed copies of
# repo files differ from the repo. They are copies, not symlinks, so a repo edit
# never reaches them until install runs again; lib.sh and _store.sh drifted that
# way once, and the AGY statusline copy ran an older script after a later edit.
# Covers the flat runtime copies (install_runtime_dir) and each installed
# statusline-command.sh that its settings.json names. Exit 2 blocks; 0 allows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"
RT="${RUNTIME_DRIFT_GUARD_RUNTIME_DIR:-$(skills_runtime_dir "$REPO_DIR")}"

drift=""
if [[ ! -d "$RT" ]]; then
  echo "  SKIP  runtime not installed at $RT"
else
  while read -r src dst; do
    if ! cmp -s "$REPO_DIR/$src" "$RT/$dst"; then
      drift="$drift $dst"
    fi
  done < <(runtime_files)
fi

# Block only on what `bash scripts/install.sh` can repair. install.sh refuses a
# linked worktree or a non-default branch, copies config/statusline-command.sh, and
# refreshes only the agents in the saved selection; outside those, report nothing.
# With no saved selection a non-interactive install.sh selects claude alone.
selected() {  # <agent>: true when install.sh would refresh it
  local sel
  sel=$(cat "$RT/agent-selection.txt" 2>/dev/null || true)
  [[ -n "$sel" ]] || sel="claude"
  [[ "$sel" == "all" || ",$sel," == *",$1,"* ]]
}

sl_drift=""
if [[ -n "${HOME:-}" && -f "$REPO_DIR/config/statusline-command.sh" ]] \
   && require_main_checkout "$REPO_DIR" >/dev/null 2>&1 \
   && command -v jq >/dev/null 2>&1; then
  for entry in "gemini:$HOME/.gemini/antigravity-cli" "claude:$HOME/.claude"; do
    agent="${entry%%:*}"; dir="${entry#*:}"
    copy="$dir/statusline-command.sh"
    selected "$agent" || continue
    # The statusLine command must be exactly "bash <copy>", as install_statusline writes it;
    # a foreign command, another key, a longer path or unreadable JSON is not ours.
    jq -e --arg c "bash $copy" '.statusLine | type == "object" and .command == $c' \
      "$dir/settings.json" >/dev/null 2>&1 || continue
    # install_statusline finds the copy by a literal match of its path in the raw file; a path
    # the file stores escaped (non-ASCII, quote, backslash) is invisible to it, so it cannot repair.
    grep -qF "$copy" "$dir/settings.json" 2>/dev/null || continue
    if ! cmp -s "$REPO_DIR/config/statusline-command.sh" "$copy"; then
      sl_drift="$sl_drift $copy"
    fi
  done
fi

if [[ -n "$drift" || -n "$sl_drift" ]]; then
  [[ -n "$drift" ]] && echo "Blocked: installed runtime copies in $RT differ from the repo:$drift" >&2
  [[ -n "$sl_drift" ]] && echo "Blocked: installed statusline scripts differ from config/statusline-command.sh:$sl_drift" >&2
  echo "Sync: bash scripts/install.sh" >&2
  exit 2
fi
