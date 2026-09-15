#!/usr/bin/env bash
# state-layer-guard.sh — Stop/SubagentStop hook: block completion if this
# repo's own state layer (feature_list.json, progress.md, init.sh) goes
# missing or feature_list.json stops parsing as JSON. Without this, deleting
# the state layer regresses the repo back to the state-blind 32/100 baseline
# from the harness-creator audit (docs/harness-creator/lecture-01/) with no
# gate ever noticing.
#
# Deliberately NOT the full validate-harness.mjs scorer: that script lives in
# a different repo, scores prose/structure (a legitimate AGENTS.md reword can
# flip a check), and this repo already accepts capping below 100 rather than
# writing false content to satisfy it (see lecture-01/progress-detail.md).
# This gate only checks the mechanical, unambiguous part: do the files exist,
# does the JSON parse. Exit 2 blocks; exit 0 allows.
set -euo pipefail

REPO_DIR="${STATE_LAYER_GUARD_REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

missing=()
for f in feature_list.json progress.md init.sh; do
  [[ -f "$REPO_DIR/$f" ]] || missing+=("$f")
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Blocked: this repo's state layer is missing: ${missing[*]}" >&2
  echo "See docs/harness-creator/lecture-01/ for why these exist." >&2
  exit 2
fi

json_err=$(mktemp)
trap 'rm -f "$json_err"' EXIT

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$REPO_DIR/feature_list.json" 2>"$json_err"; then
  echo "Blocked: feature_list.json is not valid JSON:" >&2
  cat "$json_err" >&2
  exit 2
fi

exit 0
