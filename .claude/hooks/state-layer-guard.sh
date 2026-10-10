#!/usr/bin/env bash
# state-layer-guard.sh — Stop/SubagentStop hook: block completion if this
# repo's own state layer (feature_list.json, PROGRESS.md, init.sh) goes
# missing, feature_list.json stops parsing as JSON, WIP limit is violated,
# completion evidence is missing, or an active feature violates declared
# sprint contract scope exclusions (feat-045).
#
# Exit 2 blocks; exit 0 allows.
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

# Detect changed files for exclusion checking (overridable via STATE_LAYER_GUARD_CHANGED_FILES)
CHANGED_FILES="${STATE_LAYER_GUARD_CHANGED_FILES:-}"
if [[ -z "${STATE_LAYER_GUARD_CHANGED_FILES+x}" ]]; then
  if [[ -f "$REPO_DIR/scripts/get-changed-files.sh" ]]; then
    CHANGED_FILES=$(bash "$REPO_DIR/scripts/get-changed-files.sh" 2>/dev/null || true)
  elif git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CHANGED_FILES=$(git -C "$REPO_DIR" diff --name-only HEAD 2>/dev/null || true)
  fi
fi

check_out=$(python3 - <<'PYEOF' "$REPO_DIR/feature_list.json" "$CHANGED_FILES" 2>&1
import fnmatch, json, sys

feature_file = sys.argv[1]
changed_files_raw = sys.argv[2] if len(sys.argv) > 2 else ""
changed_files = [line.strip() for line in changed_files_raw.splitlines() if line.strip()]

try:
    with open(feature_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    sys.exit(f"JSON_ERROR: {e}")

features = data.get("features", data) if isinstance(data, dict) else data
if not isinstance(features, list):
    sys.exit("SCHEMA_ERROR: feature_list root or 'features' must be a list")

# Validate archive_references if present
archived_features = []
if isinstance(data, dict) and "archive_references" in data:
    arch_refs = data["archive_references"]
    if not isinstance(arch_refs, list) or not all(isinstance(r, str) and r.strip() for r in arch_refs):
        sys.exit("ARCHIVE_ERROR: 'archive_references' must be a list of non-empty string file paths.")
    from pathlib import Path
    repo_root = Path(feature_file).resolve().parent
    for ref in arch_refs:
        ref_path = (repo_root / ref).resolve()
        if not ref_path.is_file():
            sys.exit(f"ARCHIVE_ERROR: Referenced archive file does not exist: '{ref}'.")
        try:
            with open(ref_path, "r", encoding="utf-8") as rf:
                ref_data = json.load(rf)
        except Exception as e:
            sys.exit(f"ARCHIVE_ERROR: Archive file '{ref}' is not valid JSON: {e}.")
        ref_feats = ref_data.get("features", ref_data) if isinstance(ref_data, dict) else ref_data
        if not isinstance(ref_feats, list):
            sys.exit(f"ARCHIVE_ERROR: Archive file '{ref}' must contain a list of features.")
        archived_features.extend(ref_feats)

# Validate exclusions schema across all features
for f in features:
    if isinstance(f, dict) and "exclusions" in f:
        ex = f.get("exclusions")
        if not isinstance(ex, list) or not all(isinstance(x, str) for x in ex):
            sys.exit(f"SCHEMA_ERROR: 'exclusions' in feature '{f.get('id')}' must be a list of strings.")

active = [f for f in features if isinstance(f, dict) and f.get("status") in ("active", "in_progress", "doing")]

if len(active) > 1:
    ids = [f.get("id", "unknown") for f in active]
    sys.exit(f"WIP_ERROR: WIP limit violation: {len(active)} features active concurrently: {ids}. Lecture 07 mandates WIP=1.")

for f in active:
    fid = f.get("id", "unknown")
    v = f.get("verification") or f.get("acceptance_criteria")
    if not v or not str(v).strip():
        sys.exit(f"EVIDENCE_ERROR: Completion evidence missing: active feature '{fid}' has no non-empty 'verification' or 'acceptance_criteria' command.")

    # Scope exclusions enforcement
    exclusions = f.get("exclusions", [])
    if exclusions and isinstance(exclusions, list):
        for pattern in exclusions:
            if not isinstance(pattern, str) or not pattern.strip():
                continue
            pat = pattern.strip()
            for cf in changed_files:
                if fnmatch.fnmatch(cf, pat) or fnmatch.fnmatch(cf, f"*/{pat}"):
                    sys.exit(f"EXCLUSION_ERROR: File '{cf}' modified in violation of exclusion pattern '{pat}' for active feature '{fid}'.")

def has_text(v):
    if isinstance(v, str):
        return bool(v.strip())
    if isinstance(v, (list, tuple)):
        return any(has_text(x) for x in v)
    if isinstance(v, dict):
        return any(has_text(x) for x in v.values())
    return False

all_features = features + archived_features
unevidenced = [
    f.get("id", "unknown")
    for f in all_features
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
  elif grep -q "SCHEMA_ERROR:" <<<"$check_out"; then
    echo "Blocked: feature_list.json schema violation:" >&2
    echo "$check_out" | sed 's/SCHEMA_ERROR: //' >&2
    exit 2
  elif grep -q "ARCHIVE_ERROR:" <<<"$check_out"; then
    echo "Blocked: state layer archive reference error:" >&2
    echo "$check_out" | sed 's/ARCHIVE_ERROR: //' >&2
    echo "WHY: feature_list.json references an archive file that is missing, invalid, or violates schema." >&2
    echo "FIX: Ensure all files in 'archive_references' exist and contain valid JSON features." >&2
    exit 2
  elif grep -q "WIP_ERROR:" <<<"$check_out"; then
    echo "Blocked by WIP limit: feature_list.json has multiple active features:" >&2
    echo "$check_out" | sed 's/WIP_ERROR: //' >&2
    exit 2
  elif grep -q "EXCLUSION_ERROR:" <<<"$check_out"; then
    echo "Blocked: active feature scope exclusion violated:" >&2
    echo "$check_out" | sed 's/EXCLUSION_ERROR: //' >&2
    echo "WHY: Sprint contract in feature_list.json explicitly excluded this path to prevent scope creep." >&2
    echo "FIX: Revert changes to excluded file, or update feature exclusions if scope expansion was authorized." >&2
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
