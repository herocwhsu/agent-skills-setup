#!/usr/bin/env bash
# semgrep-guard.sh — Stop hook: SAST scan on repo source
# Shared with the sibling repo — only the "repo config" block below may differ.
set -euo pipefail
command -v semgrep &>/dev/null || { echo "  SKIP  semgrep not installed"; exit 0; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- repo config --------------------------------------------------------------
SCAN_DIR="$REPO_ROOT"                                      # directory semgrep scans
CONFIGS=(p/security-audit p/secrets)                       # add p/python p/typescript p/kubernetes ... for your stack
EXCLUDES=(node_modules .git .venv dist)
RELEVANT_RE='^.*\.(py|ts|tsx|js|jsx|go|ya?ml)$|.*\.sh$'      # a turn touching none of these skips the scan
# -------------------------------------------------------------------------------

# Turn scope. A turn that changed nothing in scope has nothing to scan; sweeping
# the tree anyway cost seconds and a blocked turn on every read-only turn
# (measured 2026-08-25, when eight consecutive turns were blocked by findings
# none of them caused). Compared against the merge-base with upstream, NOT HEAD:
# gating on uncommitted changes alone lets a session commit a broken tree, stop,
# and skip every check -- pre-commit covers formatting and shellcheck, not
# kustomize, checkov, semgrep or gitleaks. No upstream (fresh or local-only
# branch) falls back to HEAD, the best signal available there.
changed_paths() {
  local re="$1" base
  base=$(git -C "$REPO_ROOT" merge-base '@{upstream}' HEAD 2>/dev/null || echo HEAD)
  {
    git -C "$REPO_ROOT" diff --name-only "$base" 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | grep -E "$re" | sort -u || true
}

if [[ -z "$(changed_paths "$RELEVANT_RE")" ]]; then
  echo "  SKIP  turn changed nothing in scope"
  exit 0
fi


WARN=0

echo "=== Semgrep SAST ==="
# --baseline-commit HEAD: only findings introduced by uncommitted changes fail
# the hook — pre-existing findings are a backlog, not a per-Stop blocker.
CONFIG_ARGS=(); for c in "${CONFIGS[@]}"; do CONFIG_ARGS+=(--config "$c"); done
EXCLUDE_ARGS=(); for e in "${EXCLUDES[@]}"; do EXCLUDE_ARGS+=(--exclude "$e"); done
# --baseline-commit against the same merge-base the gate uses: with HEAD, a
# finding inside an unpushed commit is invisible exactly when the gate opened
# because of that commit. Capture and re-emit on STDERR -- only stderr reaches
# the model on exit 2, so 2>/dev/null threw away every file:line and left the
# loop a bare WARNING it could not act on.
SG_BASE=$(git -C "$REPO_ROOT" merge-base '@{upstream}' HEAD 2>/dev/null || echo HEAD)
if ! SG_OUT=$(semgrep scan \
    "${CONFIG_ARGS[@]}" \
    --error --quiet \
    --baseline-commit "$SG_BASE" \
    "${EXCLUDE_ARGS[@]}" \
    "$SCAN_DIR" 2>&1); then
  echo "semgrep findings:" >&2
  { printf '%s\n' "$SG_OUT" | head -40 || true; } >&2
  WARN=1
else
  echo "  OK  semgrep"
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
