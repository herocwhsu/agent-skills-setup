#!/usr/bin/env bash
# k8s/yaml-validate.sh — PostToolUse: kustomize build on nearest overlay
# Copy to .claude/hooks/yaml-validate.sh in your repo
set -euo pipefail

input=$(cat)
file=$(echo "$input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
i=d.get('tool_input',{})
print(i.get('path') or i.get('file_path') or '')
" 2>/dev/null)

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ "$file" != *.yaml && "$file" != *.yml ]] && exit 0

DIR="$(dirname "$(realpath "$file")")"
OVERLAY=""
while [[ "$DIR" != "/" ]]; do
  if [[ -f "$DIR/kustomization.yaml" ]]; then
    OVERLAY="$DIR"
    break
  fi
  DIR="$(dirname "$DIR")"
done

[[ -z "$OVERLAY" ]] && exit 0

command -v kubectl &>/dev/null || { echo "  SKIP  kubectl not installed"; exit 0; }

echo "Validating: $OVERLAY"
if ! kubectl kustomize "$OVERLAY" > /dev/null 2>&1; then
  echo "WARNING: kustomize build failed for $OVERLAY" >&2
  kubectl kustomize "$OVERLAY" 2>&1 | sed 's/^/  /' >&2
  exit 2
fi
echo "  OK"
exit 0
