#!/usr/bin/env bash
# js/ts-guard.sh — Stop hook: tsc + vitest + eslint for changed frontend apps
# Copy to .claude/hooks/ts-guard.sh in your repo
# Only runs for the app folders in APP_DIRS whose TS/JS files changed.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

# --- repo config --------------------------------------------------------------
APP_DIRS=(".")   # frontend app folders, relative to the repo root; "." = the repo itself
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

command -v node &>/dev/null || { echo "  SKIP  node not installed (brew install node)"; exit 0; }
command -v npm  &>/dev/null || { echo "  SKIP  npm not installed (brew install node)";  exit 0; }

for rel in "${APP_DIRS[@]}"; do
  if [[ "$rel" == "." ]]; then APP_DIR="$REPO_ROOT"; prefix=""; else APP_DIR="$REPO_ROOT/$rel"; prefix="$rel/"; fi
  [[ -d "$APP_DIR" ]] || continue

  changed=$(changed_paths "^${prefix}src/.*\\.(ts|tsx|js|jsx)$")
  [[ -z "$changed" ]] && continue

  echo "=== $rel: tsc ==="
  if [[ -f "$APP_DIR/tsconfig.json" ]]; then
    # plain `tsc -b`: --noEmit is rejected in -b mode (TS6310) when referenced
    # projects disable emit; the tsconfigs already set noEmit themselves
    out=$( (cd "$APP_DIR" && npx --yes tsc -b) 2>&1 ) \
      || { echo "WARNING: $rel TypeScript errors" >&2; echo "$out" | head -20 >&2; WARN=1; }
  fi

  echo "=== $rel: vitest ==="
  if grep -q '"test"' "$APP_DIR/package.json" 2>/dev/null; then
    out=$( (cd "$APP_DIR" && npm test -- --reporter=dot) 2>&1 ) \
      || { echo "WARNING: $rel tests failed" >&2; echo "$out" | tail -25 >&2; WARN=1; }
  fi

  echo "=== $rel: eslint ==="
  if [[ -f "$APP_DIR/eslint.config.js" || -f "$APP_DIR/.eslintrc.js" ]]; then
    out=$( (cd "$APP_DIR" && npx eslint src/ --max-warnings=0 -q) 2>&1 ) \
      || { echo "WARNING: $rel eslint issues" >&2; echo "$out" | head -25 >&2; WARN=1; }
  fi
done

[[ $WARN -eq 0 ]] && exit 0 || exit 2
