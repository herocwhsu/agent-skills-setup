#!/usr/bin/env bash
# state-layer-guard.sh — Stop/SubagentStop hook: block completion if this
# repo's own state layer (feature_list.json, PROGRESS.md, init.sh) goes
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
[[ -f "$REPO_DIR/feature_list.json" ]] || missing+=("feature_list.json")
[[ -f "$REPO_DIR/PROGRESS.md" ]] || missing+=("PROGRESS.md")
[[ -f "$REPO_DIR/init.sh" ]] || missing+=("init.sh")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Blocked: this repo's state layer is missing: ${missing[*]}" >&2
  echo "See docs/harness-creator/lecture-01/ for why these exist." >&2
  exit 2
fi

check_out=$(python3 - <<'PYEOF' "$REPO_DIR/feature_list.json" 2>&1
import json, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    sys.exit(f"JSON_ERROR: {e}")

features = data.get("features", data) if isinstance(data, dict) else data
if not isinstance(features, list):
    sys.exit("SCHEMA_ERROR: feature_list root or 'features' must be a list")

active = [f for f in features if isinstance(f, dict) and f.get("status") in ("active", "in_progress", "doing")]

if len(active) > 1:
    ids = [f.get("id", "unknown") for f in active]
    sys.exit(f"WIP_ERROR: WIP limit violation: {len(active)} features active concurrently: {ids}. Lecture 07 mandates WIP=1.")

for f in active:
    fid = f.get("id", "unknown")
    v = f.get("verification") or f.get("acceptance_criteria")
    if not v or not str(v).strip():
        sys.exit(f"EVIDENCE_ERROR: Completion evidence missing: active feature '{fid}' has no non-empty 'verification' or 'acceptance_criteria' command.")

def has_text(v):
    if isinstance(v, str):
        return bool(v.strip())
    if isinstance(v, (list, tuple)):
        return any(has_text(x) for x in v)
    if isinstance(v, dict):
        return any(has_text(x) for x in v.values())
    return False

unevidenced = [
    f.get("id", "unknown")
    for f in features
    if isinstance(f, dict) and f.get("status") == "done" and not has_text(f.get("evidence"))
]
if unevidenced:
    sys.exit(f"DONE_ERROR: done features without 'evidence': {unevidenced}.")
PYEOF
) || {
  rc=$?
  if grep -q "JSON_ERROR:" <<<"$check_out"; then
    echo "Blocked: feature_list.json is not valid JSON:" >&2
    echo "$check_out" | sed 's/JSON_ERROR: //' >&2
    exit 2
  elif grep -q "WIP_ERROR:" <<<"$check_out"; then
    echo "Blocked by WIP limit: feature_list.json has multiple active features:" >&2
    echo "$check_out" | sed 's/WIP_ERROR: //' >&2
    exit 2
  elif grep -q "DONE_ERROR:" <<<"$check_out"; then
    echo "Blocked: done feature lacks completion evidence:" >&2
    echo "$check_out" | sed 's/DONE_ERROR: //' >&2
    exit 2
  elif grep -q "EVIDENCE_ERROR:" <<<"$check_out"; then
    echo "Blocked: active feature lacks completion evidence:" >&2
    echo "$check_out" | sed 's/EVIDENCE_ERROR: //' >&2
    exit 2
  else
    echo "Blocked: state layer validation error:" >&2
    echo "$check_out" >&2
    exit 2
  fi
}

exit 0
