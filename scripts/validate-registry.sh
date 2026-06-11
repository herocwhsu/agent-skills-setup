#!/usr/bin/env bash
# validate-registry.sh — check every local/local-optional entry in registry.txt
# has a corresponding skills/<name>/SKILL.md.
# Usage: bash scripts/validate-registry.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$REPO_DIR/registry.txt"
SKILLS_DIR="$REPO_DIR/skills"

errors=0

while IFS=' ' read -r type id rest; do
  case "$type" in
    ""|\#*) continue ;;
    local)
      skill_md="$SKILLS_DIR/$id/SKILL.md"
      if [[ ! -f "$skill_md" ]]; then
        echo "  ERROR: registry entry '$id' has no SKILL.md at $skill_md" >&2
        errors=$((errors + 1))
      fi
      ;;
    # local-optional entries are intentionally absent on some hosts — skip validation
    local-optional) continue ;;
  esac
done < "$REGISTRY"

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "Registry validation failed: $errors error(s). Fix registry.txt or create missing SKILL.md files." >&2
  exit 1
fi

echo "  ✓ registry.txt valid — all local entries have SKILL.md"
