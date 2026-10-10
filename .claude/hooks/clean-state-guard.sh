#!/usr/bin/env bash
# clean-state-guard.sh — Stop/SubagentStop & pre-commit hook: enforces
# Clean-State Invariant 4 ("No Stale Artifacts") from Lecture 12.
#
# Blocks completion or commit if the workspace contains leftover scratch files,
# temporary backup files, debug logs in source directories, or uncommitted .env
# credential files.
#
# Exit 2 blocks with a 3-part diagnostic (WHAT + WHY + FIX); exit 0 allows.
set -euo pipefail

REPO_DIR="${CLEAN_STATE_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Detect candidate files in workspace (or use seam override if provided)
candidates=""
if [[ -n "${CLEAN_STATE_GUARD_FILES+x}" ]]; then
  candidates="$CLEAN_STATE_GUARD_FILES"
else
  # Check git untracked and modified files if inside git repo
  if git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --others: untracked; --modified: modified; exclude-standard handles .gitignore
    candidates=$(git -C "$REPO_DIR" ls-files --others --modified --exclude-standard 2>/dev/null || true)
  else
    # Fallback to finding files if not in git
    candidates=$(find "$REPO_DIR" -maxdepth 3 -type f 2>/dev/null | while read -r f; do
      echo "${f#"$REPO_DIR"/}"
    done)
  fi
fi

# Run portable python scanner to evaluate candidate files
violations=$(python3 - <<'PYEOF' "$candidates" 2>&1
import fnmatch, os, sys

raw_files = sys.argv[1] if len(sys.argv) > 1 else ""
files = [f.strip() for f in raw_files.splitlines() if f.strip()]

# Ignored paths
IGNORED_PARTS = {".git", ".venv", "node_modules", ".pytest_cache", "__pycache__", ".mypy_cache", ".system_generated"}

# Prohibited patterns
SCRATCH_PATTERNS = ["scratch.*", "temp.*", "debug.*", "WIP.md", "IN_PROGRESS.md", "test-manual.*"]
BACKUP_PATTERNS = ["*.tmp", "*.bak", "*.swp", "*~"]
ENV_PATTERNS = [".env", ".env.local", ".env.production", ".env.staging"]

violations = []

for rel_path in files:
    parts = set(rel_path.split(os.sep))
    if parts & IGNORED_PARTS:
        continue
    base = os.path.basename(rel_path)

    # 1. Scratch / WIP markers
    if any(fnmatch.fnmatch(base.lower(), pat.lower()) for pat in SCRATCH_PATTERNS):
        violations.append((rel_path, "uncommitted scratch or WIP marker"))
        continue

    # 2. Backup / editor temp files
    if any(fnmatch.fnmatch(base, pat) for pat in BACKUP_PATTERNS):
        violations.append((rel_path, "temporary backup or editor swap file"))
        continue

    # 3. Environment secret files (excluding example/template)
    if base in ENV_PATTERNS and not base.endswith((".example", ".template")):
        violations.append((rel_path, "environment file with potential secrets"))
        continue

    # 4. Stray log files in source/scripts/skills/hooks trees
    if base.endswith(".log"):
        if any(p in parts for p in ("src", "lib", "app", "scripts", "skills", ".claude", "hooks")):
            violations.append((rel_path, "stray debug log in source tree"))
            continue

for path, reason in violations:
    print(f"{path} ({reason})")
PYEOF
)

if [[ -n "$violations" ]]; then
  echo "Blocked: workspace violates Clean-State Invariant 4 (No Stale Artifacts)" >&2
  echo "" >&2
  echo "WHAT: Found stale, temporary, or uncommitted scratch artifacts:" >&2
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "      - $line" >&2
  done <<< "$violations"
  echo "" >&2
  echo "WHY:  Every session must leave a clean state. Leaving debug debris, temporary" >&2
  echo "      backups, or scratch markers pollutes the repository and creates confusion" >&2
  echo "      for the next agent session (Lecture 12)." >&2
  echo "" >&2
  echo "FIX:  Delete temporary files or commit intentional changes:" >&2
  echo "      rm -f <file>" >&2
  echo "      Or run automated session cleanup: bash scripts/session-clean.sh" >&2
  exit 2
fi

exit 0
