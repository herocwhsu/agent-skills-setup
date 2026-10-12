#!/usr/bin/env bash
# state-layer-guard.sh — Stop/SubagentStop hook: block completion if this
# repo's own state layer (feature_list.json, PROGRESS.md, init.sh) goes
# missing, feature_list.json stops parsing as JSON, WIP limit is violated,
# completion evidence is missing, or an active feature violates declared
# sprint contract scope exclusions (feat-045).
#
# The feature_list.json checks live in scripts/state_layer_check.py.
# Exit 2 blocks; exit 0 allows.
set -euo pipefail

GUARD_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_DIR="${STATE_LAYER_GUARD_REPO_DIR:-$GUARD_ROOT}"

missing=()
[[ -f "$REPO_DIR/feature_list.json" ]] || missing+=("feature_list.json")
[[ -f "$REPO_DIR/PROGRESS.md" ]] || missing+=("PROGRESS.md")
[[ -f "$REPO_DIR/init.sh" ]] || missing+=("init.sh")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Blocked: this repo's state layer is missing: ${missing[*]}" >&2
  echo "See docs/harness-creator/lecture-01/ for why these exist." >&2
  exit 2
fi

# Detect changed files for exclusion checking (overridable via STATE_LAYER_GUARD_CHANGED_FILES)
CHANGED_FILES="${STATE_LAYER_GUARD_CHANGED_FILES:-}"
if [[ -z "${STATE_LAYER_GUARD_CHANGED_FILES+x}" ]]; then
  if [[ -f "$REPO_DIR/scripts/get-changed-files.sh" ]]; then
    CHANGED_FILES=$(bash "$REPO_DIR/scripts/get-changed-files.sh" 2>/dev/null || true)
  elif git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CHANGED_FILES=$(git -C "$REPO_DIR" diff --name-only HEAD 2>/dev/null || true)
  fi
fi

if ! check_err=$(python3 "$GUARD_ROOT/scripts/state_layer_check.py" "$REPO_DIR/feature_list.json" "$CHANGED_FILES" 2>&1 >/dev/null); then
  if ! grep -q '^Blocked' <<<"$check_err"; then
    echo "Blocked: state layer validation error:" >&2
  fi
  echo "$check_err" >&2
  exit 2
fi
