#!/usr/bin/env bash
# secret-scan.sh — Stop hook: gitleaks secret scan (+ osv-scanner where npm lockfiles exist)
# Shared with the sibling repo — only the "repo config" block below may differ.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- repo config --------------------------------------------------------------
OSV_NPM_SCAN_DIR="$REPO_ROOT"   # dir to search for package-lock.json; empty = skip osv scan
RELEVANT_RE='.'   # any change at all: a credential can land in any file
# -------------------------------------------------------------------------------

# Turn scope. A turn that changed nothing in scope has nothing to scan; sweeping
# the tree anyway cost seconds and a blocked turn on every read-only turn
# (measured 2026-08-25, when eight consecutive turns were blocked by findings
# none of them caused). Compared against the merge-base with upstream, NOT HEAD:
# gating on uncommitted changes alone lets a session commit a broken tree, stop,
# and skip every check -- pre-commit covers formatting and shellcheck, not
# kustomize, checkov, semgrep or gitleaks. No upstream (fresh or local-only
# branch) falls back to HEAD, the best signal available there.
changed_paths() {
  local re="$1" base
  base=$(git -C "$REPO_ROOT" merge-base '@{upstream}' HEAD 2>/dev/null || echo HEAD)
  {
    git -C "$REPO_ROOT" diff --name-only "$base" 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  } | grep -E "$re" | sort -u || true
}

if [[ -z "$(changed_paths "$RELEVANT_RE")" ]]; then
  echo "  SKIP  turn changed nothing in scope"
  exit 0
fi


WARN=0

echo "=== Gitleaks secret scan ==="
if command -v gitleaks &>/dev/null; then
  # NB: gitleaks 8.x has no -q flag (an invalid flag exits 1 and read as a
  # permanent false "secrets found"); quiet via --no-banner + log-level.
  if ! out=$(gitleaks detect --source "$REPO_ROOT" --no-git --redact --no-banner --log-level error 2>&1); then
    echo "WARNING: gitleaks found potential secrets — review before committing" >&2
    echo "$out" | head -30 >&2
    WARN=1
  else
    echo "  OK  gitleaks"
  fi
else
  echo "  SKIP  gitleaks not installed"
fi

if [[ -n "$OSV_NPM_SCAN_DIR" ]]; then
  echo ""
  echo "=== OSV dependency scan ==="
  if command -v osv-scanner &>/dev/null; then
    # osv-scanner v2 syntax; no -q flag. Scoped to npm lockfiles only: on
    # requirements.txt osv RESOLVES transitive deps at their minimum versions
    # and reports phantom ancient CVEs — pip-audit in py-guard owns Python.
    LOCKFILES=()
    while IFS= read -r lf; do LOCKFILES+=(-L "$lf"); done \
      < <(find "$OSV_NPM_SCAN_DIR" -maxdepth 2 -name package-lock.json 2>/dev/null)
    if [[ ${#LOCKFILES[@]} -eq 0 ]]; then
      echo "  SKIP  no npm lockfiles found"
    elif ! out=$(osv-scanner scan source "${LOCKFILES[@]}" 2>&1); then
      echo "WARNING: osv-scanner found vulnerable dependencies" >&2
      echo "$out" | tail -30 >&2
      WARN=1
    else
      echo "  OK  osv-scanner"
    fi
  else
    echo "  SKIP  osv-scanner not installed"
  fi
fi

[[ $WARN -eq 0 ]] && exit 0 || exit 2
