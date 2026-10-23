#!/usr/bin/env bash
# python/py-guard.sh — Stop hook: ruff + bandit + pip-audit + pytest for changed Python apps
# Copy to .claude/hooks/py-guard.sh in your repo
# Only runs for the app folders in APP_DIRS whose Python files changed.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

# --- repo config --------------------------------------------------------------
APP_DIRS=(".")   # Python app folders, relative to the repo root; "." = the repo itself
# -------------------------------------------------------------------------------

# Turn scope, measured against the merge-base with upstream, NOT HEAD: gating on
# uncommitted changes alone lets a session commit a broken tree, stop, and skip
# every check. No upstream (fresh or local-only branch) falls back to HEAD.
# Tracked changes plus untracked files, one path per line.
changed_paths() {
  local re="$1" base
  base=$(git -C "$REPO_ROOT" merge-base '@{upstream}' HEAD 2>/dev/null || echo HEAD)
  {
    git -C "$REPO_ROOT" diff --name-only "$base" 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | grep -E "$re" | sort -u || true
}

for rel in "${APP_DIRS[@]}"; do
  if [[ "$rel" == "." ]]; then APP_DIR="$REPO_ROOT"; prefix=""; else APP_DIR="$REPO_ROOT/$rel"; prefix="$rel/"; fi
  [[ -d "$APP_DIR" ]] || continue

  changed=$(changed_paths "^${prefix}.*\\.py$")
  [[ -z "$changed" ]] && continue

  echo "=== $rel: ruff ==="
  if command -v ruff &>/dev/null; then
    out=$(ruff check "$APP_DIR/src" 2>&1) \
      || { echo "WARNING: $rel ruff issues" >&2; echo "$out" | head -20 >&2; WARN=1; }
  else
    echo "  SKIP  ruff not installed (pip install ruff)"
  fi

  echo "=== $rel: bandit ==="
  if ! command -v bandit &>/dev/null; then
    echo "  SKIP  bandit not installed (pip install bandit)"
  elif [[ -d "$APP_DIR/src" ]]; then
    out=$(bandit -r "$APP_DIR/src" -ll -q 2>&1) \
      || { echo "WARNING: $rel bandit issues" >&2; echo "$out" | head -20 >&2; WARN=1; }
  fi

  echo "=== $rel: pip-audit ==="
  if ! command -v pip-audit &>/dev/null; then
    echo "  SKIP  pip-audit not installed (pip install pip-audit)"
  elif [[ -f "$APP_DIR/requirements.txt" ]]; then
    # pip-audit exits 1 for findings and for a run that could not audit (offline,
    # unresolvable requirement) alike; only findings block.
    if ! out=$(pip-audit -r "$APP_DIR/requirements.txt" --progress-spinner off 2>&1); then
      if [[ "$out" == *"known vulnerabilit"* ]]; then
        echo "WARNING: $rel vulnerable deps" >&2; echo "$out" | head -20 >&2; WARN=1
      else
        # pip's own "ERROR: ..." line names the bad pin; pip-audit's last line is temp paths.
        reason=$(printf '%s\n' "$out" | grep '^ERROR: ' | tail -1)
        [[ -n "$reason" ]] || reason=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)
        echo "  SKIP  pip-audit could not run: ${reason:0:200}"
      fi
    fi
  fi

  echo "=== $rel: pytest ==="
  if ! command -v pytest &>/dev/null; then
    echo "  SKIP  pytest not installed (pip install pytest)"
  elif [[ -f "$APP_DIR/pytest.ini" || -f "$APP_DIR/pyproject.toml" ]]; then
    out=$( (cd "$APP_DIR" && pytest -q --tb=short) 2>&1 ) \
      || { echo "WARNING: $rel tests failed" >&2; echo "$out" | tail -30 >&2; WARN=1; }
  fi
done

[[ $WARN -eq 0 ]] && exit 0 || exit 2
