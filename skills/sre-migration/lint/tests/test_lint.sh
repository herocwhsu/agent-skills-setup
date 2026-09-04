#!/usr/bin/env bash
# Fixture-pair tests for lint/lib/lint.sh.
#
# Each check owns a directory under tests/fixtures/<check-id>/ holding bad.md
# (must be flagged) and good.md (must not be). The should-not-flag half is not
# optional: a check that fires on everything is as useless as one that fires on
# nothing, and false positives are what get a gate ignored.
set -euo pipefail

LINT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/lint.sh"
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Every check whose fixture is a single ticket markdown file. The remaining
# checks need a fixture tree (git state, sample JSON, a tool's --site flag) and
# are not covered here.
CHECKS="not-provided-contradiction empty-operation idempotency-answered unit-drift pii-answered six-operations"

for check in $CHECKS; do
  dir="$FIXTURES/$check"

  if [[ ! -f "$dir/bad.md" || ! -f "$dir/good.md" ]]; then
    bad "$check: fixture pair incomplete"
    continue
  fi

  # --- bad.md must be flagged, non-zero exit, and name the check ---
  out=$(bash "$LINT" --check "$check" "$dir/bad.md" 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    bad "$check: bad.md exited 0 (should be flagged)"
  elif ! printf '%s' "$out" | grep -qF "FAIL [$check]"; then
    # Assert the FINDING format, not the bare id: every check id also appears in
    # usage(), so a usage dump on exit 2 would otherwise read as a real finding.
    bad "$check: bad.md exited $rc but printed no 'FAIL [$check]' (got: $out)"
  else
    ok "$check: bad.md flagged, exit $rc, check named"
  fi

  # --- good.md must NOT be flagged ---
  out=$(bash "$LINT" --check "$check" "$dir/good.md" 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    bad "$check: good.md was flagged (false positive, exit $rc: $out)"
  else
    ok "$check: good.md clean"
  fi
done

# --- sha-on-main: needs repo state, so build a throwaway repo rather than
# --- depending on the work repo being present and on a particular branch ---

SHA_DIR="$FIXTURES/sha-on-main"
if [[ -f "$SHA_DIR/bad.md" && -f "$SHA_DIR/good.md" ]]; then
  tmp=$(mktemp -d)
  (
    cd "$tmp"
    git init -q -b main .
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "on main"
  ) >/dev/null 2>&1
  # origin/main is what the check compares against; point it at the commit.
  real_sha=$(git -C "$tmp" rev-parse HEAD)
  git -C "$tmp" update-ref refs/remotes/origin/main "$real_sha"

  sed "s/__SHA__/$real_sha/" "$SHA_DIR/good.md" > "$tmp/good.md"

  out=$(SRE_MIGRATION_REPO="$tmp" bash "$LINT" --check sha-on-main "$SHA_DIR/bad.md" 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [sha-on-main]"; then
    ok "sha-on-main: absent commit flagged"
  else
    bad "sha-on-main: absent commit not flagged (exit $rc: $out)"
  fi

  out=$(SRE_MIGRATION_REPO="$tmp" bash "$LINT" --check sha-on-main "$tmp/good.md" 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    ok "sha-on-main: commit on origin/main clean"
  else
    bad "sha-on-main: commit on origin/main was flagged (exit $rc: $out)"
  fi

  # Without the repo it must refuse (exit 2), never report a pass it did not run.
  out=$(bash "$LINT" --check sha-on-main "$SHA_DIR/bad.md" 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    bad "sha-on-main: passed with no SRE_MIGRATION_REPO (unrun check read as clean)"
  elif ! printf '%s' "$out" | grep -qF "lint.sh: set SRE_MIGRATION_REPO"; then
    bad "sha-on-main: refused but did not name SRE_MIGRATION_REPO (got: $out)"
  else
    ok "sha-on-main: refuses rather than skipping when repo is unset, naming it"
  fi

  rm -rf "$tmp"
else
  bad "sha-on-main: fixture pair incomplete"
fi

# --- company-id-guard: needs the sample files, so it gets a fixture TREE ---
# A null expected_* on a real target means the tool's abort-on-mismatch does
# nothing: it will write to whatever that id happens to be. Company ids are
# per-environment auto-increment, so an id right in one env is wrong in another.

GUARD_DIR="$FIXTURES/company-id-guard"
TICKET="$FIXTURES/six-operations/good.md"   # body is irrelevant to this check

out=$(SRE_MIGRATION_ITEMS_DIR="$GUARD_DIR/bad-items" bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [company-id-guard]"; then
  ok "company-id-guard: unguarded target flagged"
else
  bad "company-id-guard: unguarded target not flagged (exit $rc: $out)"
fi

# The same id must not claim two different ship-to codes across files.
if printf '%s' "$out" | grep -qF "FAIL [company-id-guard]" &&
  printf '%s' "$out" | grep -qF 'OTHER-999'; then
  ok "company-id-guard: cross-file id/code contradiction reported, naming the value"
else
  bad "company-id-guard: cross-file contradiction not reported (got: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$GUARD_DIR/good-items" bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "company-id-guard: guarded targets clean (incl. null-target template and partial guard)"
else
  bad "company-id-guard: false positive on guarded samples (exit $rc: $out)"
fi

# Unset dir must refuse, never report a pass for a check that did not run.
out=$(bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "company-id-guard: passed with no SRE_MIGRATION_ITEMS_DIR (unrun check read as clean)"
elif ! printf '%s' "$out" | grep -qF "lint.sh: set SRE_MIGRATION_ITEMS_DIR"; then
  # Match the refusal MESSAGE, not the bare var name: usage() prints that too,
  # so a usage dump would otherwise satisfy this.
  bad "company-id-guard: refused but did not name SRE_MIGRATION_ITEMS_DIR (got: $out)"
else
  ok "company-id-guard: refuses when items dir is unset, naming it"
fi

# A different tool shape (JSON object per file, no company_id) must come back
# N/A, and N/A must be DISTINGUISHABLE from "checked and clean" — otherwise a
# whole tool silently reads as verified when nothing was verified.
out=$(SRE_MIGRATION_ITEMS_DIR="$GUARD_DIR/other-tool-items" bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "company-id-guard: object-shaped input flagged (exit $rc: $out)"
elif ! printf '%s' "$out" | grep -qF "N/A [company-id-guard]"; then
  bad "company-id-guard: object-shaped input passed silently, with no N/A line (got: $out)"
else
  ok "company-id-guard: object-shaped input reported N/A, not a silent pass"
fi

# A null guard is acceptable WHEN DOCUMENTED: NOTES.md exists in 4/4 real ticket
# dirs and is where such decisions are recorded. One real file carries null
# guards deliberately, with the note warning that filling them in made the guard
# abort. Flagging that is a false positive; passing it silently hides a real
# unguarded target. So: EXEMPT, reported.
out=$(SRE_MIGRATION_ITEMS_DIR="$GUARD_DIR/exempt-items" bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "company-id-guard: documented null guard flagged (exit $rc: $out)"
elif ! printf '%s' "$out" | grep -qF "EXEMPT [company-id-guard]"; then
  bad "company-id-guard: documented null guard passed with no EXEMPT line (got: $out)"
elif ! printf '%s' "$out" | grep -qF "stage-target-correction.json"; then
  bad "company-id-guard: EXEMPT line does not name the file (got: $out)"
else
  ok "company-id-guard: documented null guard reported EXEMPT, naming the file"
fi

# The discriminating case: a NOTES.md that names the file but justifies nothing
# must NOT earn an exemption, or the exemption is just "having a NOTES.md".
out=$(SRE_MIGRATION_ITEMS_DIR="$GUARD_DIR/undocumented-items" bash "$LINT" --check company-id-guard "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [company-id-guard]"; then
  ok "company-id-guard: NOTES.md without a null justification earns no exemption"
else
  bad "company-id-guard: unjustified null guard was exempted (exit $rc: $out)"
fi

# --- notes-present: NOTES.md exists in 4/4 real ticket dirs and is where target
# --- reasoning lives. The rule is deliberately narrow: every PROD items file
# --- must be named. Requiring EVERY file would flag 4 shipped files in one real
# --- dir that are correct as written, and only one of the four dirs uses
# --- per-file "## `name.json`" sections at all.

NOTES_DIR="$FIXTURES/notes-present"

out=$(SRE_MIGRATION_ITEMS_DIR="$NOTES_DIR/good-items" bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "notes-present: prod file documented thematically is clean"
else
  bad "notes-present: false positive on documented prod file (exit $rc: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$NOTES_DIR/bad-items" bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [notes-present]" &&
  printf '%s' "$out" | grep -qF "prod-target-correction.json"; then
  ok "notes-present: undocumented prod target flagged, naming the file"
else
  bad "notes-present: undocumented prod target not flagged (exit $rc: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$NOTES_DIR/missing-notes" bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [notes-present]"; then
  ok "notes-present: absent NOTES.md flagged"
else
  bad "notes-present: absent NOTES.md not flagged (exit $rc: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$NOTES_DIR/partial-items" bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "notes-present: undocumented NON-prod files do not fail (real shipped shape)"
else
  bad "notes-present: flagged undocumented non-prod files (exit $rc: $out)"
fi

# A dir with no prod file at all is N/A, not a pass: nothing was verified, and
# saying "clean" would imply otherwise.
out=$(SRE_MIGRATION_ITEMS_DIR="$NOTES_DIR/devonly-items" bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "notes-present: dev-only dir flagged (exit $rc: $out)"
elif ! printf '%s' "$out" | grep -qF "N/A [notes-present]"; then
  bad "notes-present: dev-only dir passed silently, no N/A line (got: $out)"
else
  ok "notes-present: dev-only dir reported N/A, not a silent pass"
fi

# Unset dir must refuse, like company-id-guard: an unrun check must never read
# as clean.
out=$(bash "$LINT" --check notes-present "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "notes-present: passed with no SRE_MIGRATION_ITEMS_DIR (unrun check read as clean)"
elif ! printf '%s' "$out" | grep -qF "lint.sh: set SRE_MIGRATION_ITEMS_DIR"; then
  bad "notes-present: refused but did not name SRE_MIGRATION_ITEMS_DIR (got: $out)"
else
  ok "notes-present: refuses when items dir is unset, naming it"
fi

# --- env-samples-complete: the DEPLOYED envs (dev/stage/prod) need a sample.
# --- `local` is deliberately excluded: it resolves to http://localhost:8080, a
# --- developer's machine, and one shipped dir has no local file. A missing env
# --- can also be legitimate, so NOTES.md can exempt it — one shipped dir has no
# --- dev file because dev holds no data for that customer at all.

ENV_DIR="$FIXTURES/env-samples-complete"

out=$(SRE_MIGRATION_ITEMS_DIR="$ENV_DIR/complete-items" bash "$LINT" --check env-samples-complete "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "env-samples-complete: dev/stage/prod present and no local file is clean"
else
  bad "env-samples-complete: false positive on complete dir (exit $rc: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$ENV_DIR/missing-dev-items" bash "$LINT" --check env-samples-complete "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && printf '%s' "$out" | grep -qF "FAIL [env-samples-complete]" &&
  printf '%s' "$out" | grep -qF "dev"; then
  ok "env-samples-complete: unexplained missing dev flagged, naming the env"
else
  bad "env-samples-complete: unexplained missing dev not flagged (exit $rc: $out)"
fi

out=$(SRE_MIGRATION_ITEMS_DIR="$ENV_DIR/documented-missing-items" bash "$LINT" --check env-samples-complete "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "env-samples-complete: documented missing env flagged (exit $rc: $out)"
elif ! printf '%s' "$out" | grep -qF "EXEMPT [env-samples-complete]"; then
  bad "env-samples-complete: documented missing env passed with no EXEMPT line (got: $out)"
else
  ok "env-samples-complete: documented missing env reported EXEMPT"
fi

# An empty dir cannot be a checked-in fixture — git does not track empty
# directories, so it would silently vanish and this assertion would break.
empty_dir=$(mktemp -d)
out=$(SRE_MIGRATION_ITEMS_DIR="$empty_dir" bash "$LINT" --check env-samples-complete "$TICKET" 2>&1) && rc=0 || rc=$?
rmdir "$empty_dir"
if [[ "$rc" -ne 0 ]]; then
  bad "env-samples-complete: empty dir flagged (exit $rc: $out)"
elif ! printf '%s' "$out" | grep -qF "N/A [env-samples-complete]"; then
  bad "env-samples-complete: empty dir passed silently, no N/A line (got: $out)"
else
  ok "env-samples-complete: dir with no items files reported N/A"
fi

out=$(bash "$LINT" --check env-samples-complete "$TICKET" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "env-samples-complete: passed with no SRE_MIGRATION_ITEMS_DIR (unrun check read as clean)"
elif ! printf '%s' "$out" | grep -qF "lint.sh: set SRE_MIGRATION_ITEMS_DIR"; then
  bad "env-samples-complete: refused but did not name the var (got: $out)"
else
  ok "env-samples-complete: refuses when items dir is unset, naming it"
fi

# --- the items-file schema must actually be enforced, not decorative ---
# harness-creator shipped a schema no validator ever read; it looked like a
# guarantee and checked nothing. Assert every required field the schema names is
# present in the generic template sample.

SCHEMA="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scaffold/templates/items-file.schema.json"
if python3 - "$SCHEMA" <<'PYCHECK'
import json, sys
schema = json.load(open(sys.argv[1]))
req = schema["items"]["required"]
for guard in ("expected_name", "expected_ship_to_code"):
    if guard not in req:
        print(f"schema does not require {guard}")
        sys.exit(1)
sys.exit(0)
PYCHECK
then
  ok "items-file schema requires the expected_* guards"
else
  bad "items-file schema does not require the expected_* guards"
fi

# --- an unknown check id must be an error, not a silent pass ---
# Otherwise a typo in a check name reads as "all clear" forever.
if bash "$LINT" --check no-such-check "$FIXTURES/empty-operation/good.md" >/dev/null 2>&1; then
  bad "unknown check id exited 0 (a typo would read as a pass)"
else
  ok "unknown check id is an error"
fi

echo ""
echo "sre-migration lint: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
