#!/usr/bin/env bash
# runtime-drift-guard.sh — Stop/SubagentStop hook: block when the flat runtime
# copies install_runtime_dir makes differ from the repo. They are copies, not
# symlinks, so a repo edit never reaches them until install_runtime_dir runs
# again; lib.sh and _store.sh drifted that way once. Exit 2 blocks; exit 0 allows.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/_lib.sh
source "$REPO_DIR/scripts/_lib.sh"
RT="${RUNTIME_DRIFT_GUARD_RUNTIME_DIR:-$(skills_runtime_dir "$REPO_DIR")}"

if [[ ! -d "$RT" ]]; then
  echo "  SKIP  runtime not installed at $RT"
  exit 0
fi

drift=""
while read -r src dst; do
  if ! cmp -s "$REPO_DIR/$src" "$RT/$dst"; then
    drift="$drift $dst"
  fi
done < <(runtime_files)

if [[ -n "$drift" ]]; then
  echo "Blocked: installed runtime copies in $RT differ from the repo:$drift" >&2
  echo "Sync: source scripts/_lib.sh && install_runtime_dir \"\$PWD\"" >&2
  exit 2
fi
