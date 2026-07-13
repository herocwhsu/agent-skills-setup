#!/usr/bin/env bash
# init-repo.sh — scaffold .claude/hooks/ for a repo from the hook template library
#
# Usage:
#   bash scripts/init-repo.sh <profile> [/path/to/target/repo]
#
# Profiles:
#   python-api   — Python FastAPI/Flask backend (ruff, bandit, pip-audit, pytest, migrations)
#   react        — React/TS frontend (prettier, tsc, vitest, eslint)
#   go-api       — Go backend (gosec, govulncheck)
#   k8s          — Kubernetes/Kustomize infra (yaml-validate, checkov, placeholder-guard)
#   full         — all of the above
#
# Common hooks (secret-scan, semgrep, grype, sh-check) are always included.
#
# The target repo gets .claude/hooks/ populated and .claude/settings.json created.
# Existing files are NOT overwritten unless --force is passed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$(cd "$SCRIPT_DIR/../hooks" && pwd)"

PROFILE="${1:-}"
TARGET="${2:-$(pwd)}"
FORCE="${FORCE:-0}"

usage() {
  echo "Usage: $0 <profile> [/path/to/repo]"
  echo "Profiles: python-api, react, go-api, k8s, full"
  exit 1
}

[[ -z "$PROFILE" ]] && usage
[[ ! -d "$TARGET" ]] && { echo "ERROR: target dir not found: $TARGET" >&2; exit 1; }

DEST="$TARGET/.claude/hooks"
mkdir -p "$DEST"

copy_hook() {
  local src="$1"
  local dst="$DEST/$(basename "$src")"
  if [[ -f "$dst" && "$FORCE" != "1" ]]; then
    echo "  SKIP  $(basename "$src") (already exists — use FORCE=1 to overwrite)"
  else
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  OK    $(basename "$src")"
  fi
}

echo "=== Copying hooks for profile: $PROFILE ==="
echo ""

# always: common hooks
echo "--- common ---"
copy_hook "$HOOKS_SRC/common/secret-scan.sh"
copy_hook "$HOOKS_SRC/common/semgrep-guard.sh"
copy_hook "$HOOKS_SRC/common/grype-guard.sh"
copy_hook "$HOOKS_SRC/common/sh-check.sh"
copy_hook "$HOOKS_SRC/check-tools.sh"

case "$PROFILE" in
  python-api|full)
    echo ""
    echo "--- python ---"
    copy_hook "$HOOKS_SRC/python/ruff-fix.sh"
    copy_hook "$HOOKS_SRC/python/py-guard.sh"
    copy_hook "$HOOKS_SRC/python/migration-guard.sh"
    ;&
esac

case "$PROFILE" in
  react|full)
    echo ""
    echo "--- js/ts ---"
    copy_hook "$HOOKS_SRC/js/ts-fix.sh"
    copy_hook "$HOOKS_SRC/js/ts-guard.sh"
    ;&
esac

case "$PROFILE" in
  go-api|full)
    echo ""
    echo "--- go ---"
    copy_hook "$HOOKS_SRC/go/gosec-guard.sh"
    copy_hook "$HOOKS_SRC/go/govulncheck-guard.sh"
    ;&
esac

case "$PROFILE" in
  k8s|full)
    echo ""
    echo "--- k8s ---"
    copy_hook "$HOOKS_SRC/k8s/yaml-validate.sh"
    copy_hook "$HOOKS_SRC/k8s/placeholder-guard.sh"
    copy_hook "$HOOKS_SRC/k8s/checkov-guard.sh"
    ;;
esac

# write settings.json if missing
SETTINGS="$TARGET/.claude/settings.json"
if [[ -f "$SETTINGS" && "$FORCE" != "1" ]]; then
  echo ""
  echo "SKIP  settings.json (already exists)"
else
  echo ""
  echo "Writing settings.json..."
  cat > "$SETTINGS" <<'EOF'
{
  "permissions": {
    "deny": [
      "Bash(git push --force*)",
      "Bash(git push -f*)",
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/secrets.*)"
    ]
  }
}
EOF
  echo "  OK    settings.json"
fi

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Run: bash $DEST/check-tools.sh"
echo "     to see which tools are installed on this machine."
echo ""
echo "  2. Edit $SETTINGS to add hook wiring:"
echo "     - PostToolUse: ruff-fix.sh, ts-fix.sh, migration-guard.sh, sh-check.sh"
echo "     - Stop: py-guard.sh, ts-guard.sh, semgrep-guard.sh, grype-guard.sh, secret-scan.sh"
echo ""
echo "  3. Commit .claude/ to the repo so all team members get the same hooks."
