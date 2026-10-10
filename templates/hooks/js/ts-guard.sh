#!/usr/bin/env bash
# js/ts-guard.sh — Stop hook: tsc + vitest + eslint
# Copy to .claude/hooks/ts-guard.sh in your repo
set -euo pipefail

APP_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

command -v node &>/dev/null || { echo "  SKIP  node not installed (brew install node)"; exit 0; }
command -v npm  &>/dev/null || { echo "  SKIP  npm not installed (brew install node)";  exit 0; }

echo "=== TypeScript check ==="
if [[ -f "$APP_DIR/tsconfig.json" ]]; then
  (cd "$APP_DIR" && npx --yes tsc -b --noEmit 2>/dev/null) \
    || { echo "WARNING: TypeScript errors found" >&2; WARN=1; }
else
  echo "  SKIP  no tsconfig.json"
fi

echo ""
echo "=== Vitest ==="
if grep -q '"test"' "$APP_DIR/package.json" 2>/dev/null; then
  (cd "$APP_DIR" && npm test -- --reporter=dot 2>/dev/null) \
    || { echo "WARNING: tests failed" >&2; WARN=1; }
fi

echo ""
echo "=== ESLint ==="
if [[ -f "$APP_DIR/eslint.config.js" || -f "$APP_DIR/.eslintrc.js" ]]; then
  (cd "$APP_DIR" && npx eslint src/ --max-warnings=0 -q 2>/dev/null) \
    || { echo "WARNING: ESLint issues found" >&2; WARN=1; }
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
