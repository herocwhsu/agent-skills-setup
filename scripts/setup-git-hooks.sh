#!/usr/bin/env bash
# setup-git-hooks.sh — install repo-level git hooks into .git/hooks/
# Ensures CLI commits and pushes are validated by harness gates.
set -euo pipefail

REPO_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
GIT_DIR="$REPO_DIR/.git"

if [[ ! -d "$GIT_DIR" ]]; then
  echo "setup-git-hooks.sh: not a git checkout or .git is missing; skipping." >&2
  exit 0
fi

HOOKS_DIR="$GIT_DIR/hooks"
mkdir -p "$HOOKS_DIR"

# 1. pre-commit hook: runs static and syntax guards
cat << 'EOF' > "$HOOKS_DIR/pre-commit"
#!/usr/bin/env bash
# Installed by scripts/setup-git-hooks.sh — Layer 1 static/syntax gate
set -euo pipefail
REPO_DIR="$(git rev-parse --show-toplevel)"

echo "==> [git pre-commit] checking bash compatibility..."
bash "$REPO_DIR/.claude/hooks/bash-compat-guard.sh"

echo "==> [git pre-commit] checking state layer..."
bash "$REPO_DIR/.claude/hooks/state-layer-guard.sh"

echo "==> [git pre-commit] checking clean state..."
bash "$REPO_DIR/.claude/hooks/clean-state-guard.sh"
EOF
chmod +x "$HOOKS_DIR/pre-commit"

# 2. pre-push hook: runs full verification suite
cat << 'EOF' > "$HOOKS_DIR/pre-push"
#!/usr/bin/env bash
# Installed by scripts/setup-git-hooks.sh — Layer 3 system verification gate
set -euo pipefail
REPO_DIR="$(git rev-parse --show-toplevel)"

echo "==> [git pre-push] running harness verification..."
exec bash "$REPO_DIR/scripts/harness-verify.sh"
EOF
chmod +x "$HOOKS_DIR/pre-push"

echo "Installed .git/hooks/pre-commit and .git/hooks/pre-push"
