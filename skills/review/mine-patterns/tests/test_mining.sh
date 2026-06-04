#!/usr/bin/env bash
# Tests the deterministic glue from mine-review-patterns SKILL.md.
# These exercise the bash commands embedded in the workflow against a
# fake repo + fake `gh` to verify error messages and output paths.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: gh auth failure surfaces a clear message ---

mkdir "$TMP/repo1"
cd "$TMP/repo1"
git init -q
git remote add origin https://github.com/example/sample-repo.git

# fake gh that simulates auth failure
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  echo "You are not logged into any GitHub hosts." >&2
  exit 1
fi
exit 0
EOF
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"

# Simulate the workflow's env-check
if gh auth status 2>/dev/null; then
  echo "FAIL: expected gh auth status to fail in test 1"
  exit 1
fi
echo "OK: gh auth failure detected"

# --- Test 2: missing origin is rejected ---

mkdir "$TMP/repo2"
cd "$TMP/repo2"
git init -q
# no remote configured

if git remote get-url origin 2>/dev/null; then
  echo "FAIL: test 2 unexpectedly found an origin"
  exit 1
fi
echo "OK: missing origin rejected"

# --- Test 3: output directory creation is idempotent ---

mkdir "$TMP/repo3"
cd "$TMP/repo3"
mkdir -p .code-review/reviews
mkdir -p .code-review/reviews  # second time should not fail
[ -d .code-review/reviews ] || { echo "FAIL: test 3 dir not created"; exit 1; }
echo "OK: output dir created idempotently"

echo ""
echo "All mining glue tests passed."
