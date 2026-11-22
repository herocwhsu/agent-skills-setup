#!/usr/bin/env bash
# Tests that install_runtime_dir ships the cve-audit collector to a private,
# stable runtime path and that uninstall removes only what setup owns.
#
# HOME is redirected to a throwaway dir: nothing here touches the real runtime
# dir, ~/.claude, or ~/.codex.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMP=$(cd -P "$TMP" && pwd)

fails=0
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

export HOME="$TMP/home"
mkdir -p "$HOME/.claude" "$HOME/.codex/rules"
printf '{"permissions":{"allow":["Bash(ls)"]}}' > "$HOME/.claude/settings.json"
before_claude=$(shasum "$HOME/.claude/settings.json")

# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"
RT="$(skills_runtime_dir "$REPO_DIR")"
CA="$RT/cve-audit"

install_runtime_dir "$REPO_DIR" >/dev/null 2>&1

for f in aws_eks collector evidence kube providers report safe_runtime; do
  [[ -f "$CA/lib/$f.py" ]] && ok "runtime has lib/$f.py" || bad "runtime lacks lib/$f.py"
done
[[ -f "$CA/setup.py" ]] && ok "runtime has setup.py" || bad "runtime lacks setup.py"

check "cve-audit runtime dir is 0700" "700" "$(stat -f '%Lp' "$CA" 2>/dev/null || stat -c '%a' "$CA")"

mismatch=""
while read -r src dst; do
  case "$dst" in cve-audit/*) cmp -s "$REPO_DIR/$src" "$RT/$dst" || mismatch="$mismatch $dst" ;; esac
done < <(runtime_files)
check "runtime copies match the repo (drift guard sees them)" "" "$mismatch"

if PYTHONDONTWRITEBYTECODE=1 python3 -I -c "
import sys; sys.path[:0] = ['$CA/lib', '$CA']
import collector, setup" 2>/dev/null; then ok "runtime copy imports on its own"; else bad "runtime copy does not import on its own"; fi

out=$(python3 -B "$CA/lib/collector.py" assess --bogus 2>&1 || true)
case "$out" in *"unrecognized arguments"*|*"required"*) ok "collector rejects unknown options" ;; *) bad "collector accepted an unknown option: $out" ;; esac

out=$(python3 -B "$CA/setup.py" plan --agent kiro --runtime-dir "$CA")
case "$out" in PROMPT*"always prompts"*) ok "setup plan: Kiro always prompts" ;; *) bad "unexpected kiro plan: $out" ;; esac
out=$(python3 -B "$CA/setup.py" plan --agent claude --runtime-dir "$CA")
case "$out" in PROMPT*) ok "setup plan: Claude keeps prompts" ;; *) bad "unexpected claude plan: $out" ;; esac

out=$(python3 -B "$CA/setup.py" remove-permissions --runtime-dir "$CA")
check "remove-permissions with nothing installed is a no-op" "nothing to remove" "$out"

printf '# the user'"'"'s own\n' > "$HOME/.codex/rules/default.rules"
before_codex=$(shasum "$HOME/.codex/rules/default.rules")

# uninstall.sh itself is not run here: it would call real npm/pip. Its cve-audit step is
# checked by shape, and setup's remove-permissions is exercised above and in test_setup.py.
if grep -q 'setup.py" remove-permissions --runtime-dir "\$CVE_AUDIT_RT"' "$REPO_DIR/scripts/uninstall.sh"; then ok "uninstall.sh calls setup's remove-permissions"; else bad "uninstall.sh does not remove setup-owned permissions"; fi

check "foreign Claude settings untouched" "$before_claude" "$(shasum "$HOME/.claude/settings.json")"
check "foreign Codex rules untouched" "$before_codex" "$(shasum "$HOME/.codex/rules/default.rules")"

echo
if [[ "$fails" -eq 0 ]]; then echo "Results: all passed"; else echo "Results: $fails failed"; exit 1; fi
