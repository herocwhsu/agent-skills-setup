#!/usr/bin/env bash
# check-tools.sh — inventory which hook tools are installed on this host
# Run after cloning a repo with .claude/hooks/ to see what needs installing
# Usage: bash .claude/hooks/check-tools.sh
set -euo pipefail

OK=0
MISSING=0

check() {
  local name="$1"
  local cmd="$2"
  local install_hint="$3"
  if command -v "$cmd" &>/dev/null; then
    local ver
    ver=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
    printf "  \033[32mOK\033[0m   %-20s %s\n" "$name" "$ver"
    OK=$((OK + 1))
  else
    printf "  \033[33mMISS\033[0m %-20s %s\n" "$name" "$install_hint"
    MISSING=$((MISSING + 1))
  fi
}

echo "=== Hook tool inventory ==="
echo ""
echo "--- Always required ---"
check "git"        "git"        "(should already be installed)"
check "python3"    "python3"    "(should already be installed)"
check "bash"       "bash"       "(should already be installed)"

echo ""
echo "--- Security scanners ---"
check "gitleaks"   "gitleaks"   "brew install gitleaks"
check "semgrep"    "semgrep"    "brew install semgrep"
check "grype"      "grype"      "brew install grype"
check "checkov"    "checkov"    "brew install checkov"
check "osv-scanner" "osv-scanner" "brew install osv-scanner"

echo ""
echo "--- Python tools ---"
check "ruff"       "ruff"       "pip install ruff"
check "bandit"     "bandit"     "pip install bandit"
check "pip-audit"  "pip-audit"  "pip install pip-audit"
check "pytest"     "pytest"     "pip install pytest"

echo ""
echo "--- Go tools ---"
check "gosec"      "gosec"      "go install github.com/securego/gosec/v2/cmd/gosec@latest"
check "govulncheck" "govulncheck" "go install golang.org/x/vuln/cmd/govulncheck@latest"

echo ""
echo "--- Shell tools ---"
check "shellcheck" "shellcheck" "brew install shellcheck"

echo ""
echo "--- K8s tools ---"
check "kubectl"    "kubectl"    "brew install kubectl"
check "kustomize"  "kustomize"  "brew install kustomize"

echo ""
echo "--- Node/JS tools ---"
check "node"       "node"       "brew install node"
check "npm"        "npm"        "brew install node"

echo ""
echo "=== Summary: $OK installed, $MISSING missing ==="
if [[ $MISSING -gt 0 ]]; then
  echo "Missing tools are skipped gracefully by hooks — install to enable those checks."
fi
exit 0
