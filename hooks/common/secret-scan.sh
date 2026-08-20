#!/usr/bin/env bash
# common/secret-scan.sh — Stop hook: gitleaks + osv-scanner
# Copy to .claude/hooks/secret-scan.sh in your repo
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WARN=0

# `--source .` (not an absolute path) matters: gitleaks bakes --source into
# each finding's fingerprint, so an absolute path produces a fingerprint
# like /Users/you/repo/file:rule:line that can never match a .gitleaksignore
# entry committed as file:rule:line (portable across every contributor's
# checkout). cd first so --source . and osv-scanner's default ignore-path
# lookup both resolve relative to the repo root regardless of caller's cwd.
cd "$REPO_ROOT"

echo "=== Gitleaks secret scan ==="
if command -v gitleaks &>/dev/null; then
  # No -q/--quiet flag exists in gitleaks v8 — passing one is a hard CLI
  # error (exit 1), which this loop used to misreport as "leaks found."
  if ! gitleaks detect --source . --no-git --redact 2>/dev/null; then
    echo "WARNING: gitleaks found potential secrets — review before committing" >&2
    WARN=1
  else
    echo "  OK  gitleaks"
  fi
else
  echo "  SKIP  gitleaks not installed (brew install gitleaks)"
fi

echo ""
echo "=== OSV dependency scan ==="
if command -v osv-scanner &>/dev/null; then
  # osv-scanner v2 restructured its CLI into subcommands ("scan source ...")
  # and dropped -q in favor of --verbosity; the old `scan --recursive ... -q`
  # invocation just printed usage and exited 0 without scanning anything.
  osv_out=$(osv-scanner scan source --recursive . --verbosity error 2>&1) && osv_status=0 || osv_status=$?
  if [[ $osv_status -eq 0 ]]; then
    echo "  OK  osv-scanner"
  elif [[ "$osv_out" == *"No package sources found"* ]]; then
    # Not a failure — this repo has no lockfile/manifest osv-scanner
    # recognizes (no package.json, requirements.txt, etc). It exits non-zero
    # for "nothing to scan" the same as it would for real findings, so without
    # this check a repo like this one would warn on every single run forever.
    echo "  OK  osv-scanner (no scannable dependency manifests found)"
  else
    echo "WARNING: osv-scanner found vulnerable dependencies" >&2
    WARN=1
  fi
else
  echo "  SKIP  osv-scanner not installed (brew install osv-scanner)"
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
