#!/usr/bin/env bash
# lint.sh — gate a drafted migration ticket against the checks that got real
# tickets bounced. One check per invocation via --check, so each fixture pair
# exercises exactly one rule.
#
# Exit 0 clean, 1 check failed, 2 usage error.
set -euo pipefail

# The operation list comes from the shared ticket template, which draft/ also
# renders from. Hardcoding it here is what lets a linter drift from the drafter:
# rename an operation in the template and a hardcoded list silently stops
# checking it. Override for testing via SRE_MIGRATION_TEMPLATE.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SRE_MIGRATION_TEMPLATE:-$LIB_DIR/../../draft/templates/migration-ticket.md.tmpl}"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "lint.sh: ticket template not found: $TEMPLATE" >&2
  exit 2
fi

# Bold list headers in the 各操作說明 section are the operations.
# sed -E (ERE) not -n with \+ : BSD sed has no \+ in basic regex, so the GNU
# form silently matches nothing here and the check set comes back empty.
OPERATIONS=$(sed -nE 's/^[[:space:]]*\*+[[:space:]]*\*\*([a-z][a-z-]*)\*\*.*/\1/p' "$TEMPLATE" | awk '!seen[$0]++' | tr '\n' ' ')
if [[ -z "${OPERATIONS// /}" ]]; then
  echo "lint.sh: no operations found in template: $TEMPLATE" >&2
  exit 2
fi

usage() {
  cat >&2 <<'USAGE'
Usage: lint.sh --check <check-id> <ticket.md>

Checks operating on the ticket body alone:
  not-provided-contradiction  an operation declares 是否提供：No yet its output is attached
  empty-operation             a provided operation has an empty 說明
  idempotency-answered        an operation does not answer 可否重複執行
  unit-drift                  the same quantity appears with two different units
  pii-answered                PII is not answered Yes/No/不確定
  six-operations              fewer than six operations are addressed

Checks needing repo state (set SRE_MIGRATION_REPO):
  sha-on-main                 the referenced commit is not on origin/main

Checks needing the items files (set SRE_MIGRATION_ITEMS_DIR):
  company-id-guard            a target company_id has no expected_* guard
  notes-present               a prod items file is not named in NOTES.md
  env-samples-complete        a deployed env (dev/stage/prod) has no sample
USAGE
}

fail() { echo "FAIL [$CHECK] $1" >&2; FAILED=1; }

# Real tickets write an operation as a bold list header with its fields indented
# beneath it:
#
#   * **precheck**
#     是否提供：Yes
#     說明：確認目標 company 存在，列印 name/region 供人工核對
#     可否重複執行：Yes
#
# A value may wrap onto continuation lines, and 是否提供 may carry markdown bold
# (`**No**`). Per the template, an operation answering No may legitimately omit
# 說明 and 可否重複執行 — "若為 No，需說明原因，且底下可忽略".

op_present() {
  grep -qE "^[[:space:]]*\*+[[:space:]]*\*\*$2\*\*" "$1"
}

# op_field <file> <op> <label> — the field's value, empty when absent.
op_field() {
  awk -v op="$2" -v label="$3" '
    $0 ~ "^[ \t]*\\*+[ \t]*\\*\\*" op "\\*\\*" { inop = 1; next }
    inop && ($0 ~ "^[ \t]*\\*+[ \t]*\\*\\*" || $0 ~ "^#") { inop = 0 }
    inop && index($0, label "：") > 0 {
      line = $0
      sub(".*" label "：", "", line)
      gsub(/\*/, "", line)
      gsub(/^[ \t]+/, "", line); gsub(/[ \t]+$/, "", line)
      print line
      exit
    }
  ' "$1"
}

# provided <file> <op> — true when 是否提供 answers Yes.
provided() {
  case "$(op_field "$1" "$2" '是否提供')" in
    Yes*|yes*|Y*) return 0 ;;
    *) return 1 ;;
  esac
}

# declines <file> <op> — true when 是否提供 answers No.
declines() {
  case "$(op_field "$1" "$2" '是否提供')" in
    No*|no*|N*) return 0 ;;
    *) return 1 ;;
  esac
}

[[ "${1:-}" == "--check" ]] || { usage; exit 2; }
CHECK="${2:-}"
FILE="${3:-}"
[[ -n "$CHECK" && -n "$FILE" ]] || { usage; exit 2; }
[[ -f "$FILE" ]] || { echo "lint.sh: no such file: $FILE" >&2; exit 2; }

FAILED=0

case "$CHECK" in
  not-provided-contradiction)
    # Declaring an operation unavailable while attaching its output means one of
    # the two is wrong. A reviewer caught exactly this and sent the ticket back.
    for op in $OPERATIONS; do
      op_present "$FILE" "$op" || continue
      declines "$FILE" "$op" || continue
      if grep -qE "^#+ *$op 輸出" "$FILE"; then
        fail "$op: declares 是否提供：No but attaches '$op 輸出'"
      fi
    done
    ;;

  empty-operation)
    # A provided operation with no 說明 is what got a ticket filed with every
    # description blank and no commands at all.
    for op in $OPERATIONS; do
      op_present "$FILE" "$op" || continue
      provided "$FILE" "$op" || continue
      [[ -n "$(op_field "$FILE" "$op" '說明')" ]] ||
        fail "$op: 是否提供：Yes but 說明 is empty"
    done
    ;;

  idempotency-answered)
    # Re-running a non-idempotent migrate corrupts data additively, so the
    # answer cannot be left implicit.
    for op in $OPERATIONS; do
      op_present "$FILE" "$op" || continue
      # A declined operation may omit it: "若為 No，需說明原因，且底下可忽略".
      provided "$FILE" "$op" || continue
      [[ -n "$(op_field "$FILE" "$op" '可否重複執行')" ]] ||
        fail "$op: 可否重複執行 is unanswered"
    done
    ;;

  unit-drift)
    # One ticket drifted between 回收 13 年 and 回收 13 pcs. Same number, two
    # units, and no way for a reviewer to tell which was meant.
    for n in $(grep -oE '[0-9]+ *(年|pcs)' "$FILE" | grep -oE '[0-9]+' | sort -u); do
      if grep -qE "$n *年" "$FILE" && grep -qE "$n *pcs" "$FILE"; then
        fail "quantity $n appears as both 年 and pcs"
      fi
    done
    ;;

  pii-answered)
    # 不確定 is a valid answer, deliberately deferred to SRE. Silence is not.
    answer=$(awk '
      /^#+ *涉及 PII/ { inpii = 1; next }
      inpii && /^#+ / { exit }
      inpii { print }
    ' "$FILE")
    # The template asks for Yes/No/不確定, but both accepted tickets answered in
    # prose ("非個人資料，但屬計費/庫存正確性敏感資料") and no reviewer ever
    # bounced one for it. Demanding the keyword would flag work SRE accepted,
    # and a gate that flags accepted work gets ignored. So require a
    # determination, in either form.
    case "$answer" in
      *Yes*|*No*|*不確定*) : ;;
      *個人資料*|*機敏資料*|*敏感資料*|*PII*) : ;;
      *) fail "PII is not determined — answer Yes/No/不確定, or state what kind of data is involved" ;;
    esac
    ;;

  six-operations)
    # The template names six. rollback is the logical inverse; restore is a
    # whole-restore from the backup. Omitting one silently is the failure.
    for op in $OPERATIONS; do
      op_present "$FILE" "$op" || fail "$op is not addressed"
    done
    ;;

  sha-on-main)
    # A ticket was bounced with "script 是不是還沒有放?" because the referenced
    # commit was not on main yet. SRE cannot run what they cannot fetch.
    sha=$(sed -n 's/^[[:space:]]*Commit SHA[：:][[:space:]]*//p' "$FILE" |
      sed 's/[^0-9a-fA-F].*$//' | head -1)
    if [[ -z "$sha" ]]; then
      fail "no 'Commit SHA：' found in 程式碼位置"
    elif [[ -z "${SRE_MIGRATION_REPO:-}" ]]; then
      # Refusing is the point: silently skipping would report a pass for a
      # check that never ran.
      echo "lint.sh: set SRE_MIGRATION_REPO to the work repo to check $sha" >&2
      exit 2
    elif ! git -C "$SRE_MIGRATION_REPO" cat-file -e "$sha^{commit}" 2>/dev/null; then
      fail "commit $sha does not exist in $SRE_MIGRATION_REPO"
    elif ! git -C "$SRE_MIGRATION_REPO" merge-base --is-ancestor "$sha" origin/main 2>/dev/null; then
      fail "commit $sha is not on origin/main — SRE cannot fetch it"
    fi
    ;;

  company-id-guard)
    # A non-null company_id with both guards null disables the tool's
    # abort-on-mismatch: it will write to whatever that id happens to be in that
    # environment. Ids are per-environment auto-increment, and the tool writes
    # additively, so a wrong target silently corrupts real stock. One filed
    # ticket named one id in its description while its SQL targeted another.
    if [[ -z "${SRE_MIGRATION_ITEMS_DIR:-}" ]]; then
      echo "lint.sh: set SRE_MIGRATION_ITEMS_DIR to the tool's templates/<jira-id>/ dir" >&2
      exit 2
    fi
    if [[ ! -d "$SRE_MIGRATION_ITEMS_DIR" ]]; then
      echo "lint.sh: SRE_MIGRATION_ITEMS_DIR is not a directory: $SRE_MIGRATION_ITEMS_DIR" >&2
      exit 2
    fi
    # Process substitution, not a pipe: a pipe would run the loop in a subshell
    # and FAILED would not survive it.
    guard_err=$(mktemp)
    while IFS= read -r finding; do
      [[ -n "$finding" ]] && fail "$finding"
    done < <(python3 - "$SRE_MIGRATION_ITEMS_DIR" 2>"$guard_err" <<'PYGUARD'
import glob, json, os, sys

items_dir = sys.argv[1]
codes = {}
skipped = []
exempt = []
inspected = 0


def notes_exemption(base):
    """The justifying sentence when NOTES.md documents this file's null guards.

    A null guard is acceptable when the ticket's NOTES.md says why — one real
    file carries nulls deliberately, because filling them in made the guard
    abort on a disposable test account. But merely NAMING the file is not a
    justification, or the exemption degrades into "has a NOTES.md". Require the
    section to speak about the guard fields AND about their being null.
    """
    notes = os.path.join(items_dir, "NOTES.md")
    if not os.path.exists(notes):
        return None
    try:
        with open(notes) as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None

    section, in_section = [], False
    for line in lines:
        if line.startswith("## "):
            if in_section:
                break
            in_section = base in line
            continue
        if in_section:
            section.append(line)
    if not section:
        return None

    body = "\n".join(section)
    lowered = body.lower()
    speaks_to_null = any(t in lowered for t in ("null", "on purpose", "intentionally")) \
        or any(t in body for t in ("刻意", "故意", "保持空"))
    speaks_to_guard = "expected_name" in body or "expected_ship_to_code" in body
    if not (speaks_to_null and speaks_to_guard):
        return None

    for line in section:
        text = line.strip().strip("*").strip()
        if text:
            return text[:110]
    return "documented in NOTES.md"

for path in sorted(glob.glob(os.path.join(items_dir, "*.json"))):
    base = os.path.basename(path)
    if base.endswith(".schema.json"):
        continue
    try:
        with open(path) as fh:
            entries = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("%s: unreadable (%s)" % (base, exc.__class__.__name__))
        continue
    if not isinstance(entries, list):
        # A tool whose input is a JSON object (e.g. one SAP request per file) has
        # no items array and no company_id semantics at all. That is a different
        # tool shape, not a malformed items file. Flagging it would fire on 14
        # shipped files that are correct as written, and a check that flags
        # accepted work gets ignored.
        skipped.append(base)
        continue
    inspected += 1
    for idx, item in enumerate(entries):
        if not isinstance(item, dict):
            continue
        cid = item.get("company_id")
        if cid is None:
            continue  # a generic template has no target, so nothing to guard
        name = item.get("expected_name")
        code = item.get("expected_ship_to_code")
        if name is None and code is None:
            reason = notes_exemption(base)
            if reason is not None:
                exempt.append((base, idx, cid, reason))
            else:
                print("%s item %d: company_id %s has neither expected_name nor "
                      "expected_ship_to_code, so abort-on-mismatch cannot protect it"
                      % (base, idx, cid))
        if code is not None:
            codes.setdefault(cid, {}).setdefault(code, []).append(base)

for cid in sorted(codes):
    by_code = codes[cid]
    if len(by_code) > 1:
        detail = "; ".join("%s in %s" % (c, ",".join(by_code[c])) for c in sorted(by_code))
        print("company_id %s claims conflicting expected_ship_to_code: %s" % (cid, detail))

for base, idx, cid, reason in exempt:
    sys.stderr.write("EXEMPT: %s item %d (company_id %s) — documented: %s\n"
                     % (base, idx, cid, reason))

if inspected == 0:
    # Distinct from "checked and clean": say so on stderr, which the caller
    # surfaces as N/A rather than as a pass.
    sys.stderr.write(
        "N/A: no items-file (JSON array) inputs in %s; %d object-shaped file(s) "
        "belong to a tool without company_id items\n" % (items_dir, len(skipped)))
PYGUARD
    )
    if [[ -s "$guard_err" ]]; then
      while IFS= read -r note; do
        case "$note" in
          N/A:*)    echo "N/A [$CHECK] ${note#N/A: }" ;;
          EXEMPT:*) echo "EXEMPT [$CHECK] ${note#EXEMPT: }" ;;
        esac
      done < "$guard_err"
    fi
    rm -f "$guard_err"
    ;;

  notes-present)
    # NOTES.md exists in 4/4 real ticket directories and is where the target
    # reasoning lives — which query resolved the id, in which environment, on
    # what date. Ids are per-environment auto-increment, so that reasoning is the
    # only record of why a given id is the right one.
    #
    # The rule is deliberately narrow: every PROD items file must be named.
    # Requiring every file would flag 4 shipped files in one real directory that
    # are correct as written, and only one of the four directories uses per-file
    # "## `name.json`" sections at all — the rest document thematically
    # ("## Input files", "## Why the prod file has no expected_name").
    if [[ -z "${SRE_MIGRATION_ITEMS_DIR:-}" ]]; then
      echo "lint.sh: set SRE_MIGRATION_ITEMS_DIR to the tool's templates/<jira-id>/ dir" >&2
      exit 2
    fi
    if [[ ! -d "$SRE_MIGRATION_ITEMS_DIR" ]]; then
      echo "lint.sh: SRE_MIGRATION_ITEMS_DIR is not a directory: $SRE_MIGRATION_ITEMS_DIR" >&2
      exit 2
    fi
    notes_err=$(mktemp)
    while IFS= read -r finding; do
      [[ -n "$finding" ]] && fail "$finding"
    done < <(python3 - "$SRE_MIGRATION_ITEMS_DIR" 2>"$notes_err" <<'PYNOTES'
import glob, os, sys

items_dir = sys.argv[1]
notes_path = os.path.join(items_dir, "NOTES.md")

prod_files = []
for path in sorted(glob.glob(os.path.join(items_dir, "*.json"))):
    base = os.path.basename(path)
    if base.endswith(".schema.json"):
        continue
    # "prod" appears as a prefix in one tool and a suffix in the other, so match
    # anywhere in the name rather than pinning a position.
    if "prod" in base.lower():
        prod_files.append(base)

if not prod_files:
    sys.stderr.write(
        "N/A: no prod items file in %s, so there is no prod target to document\n"
        % items_dir)
    sys.exit(0)

if not os.path.exists(notes_path):
    print("NOTES.md is absent; %d prod items file(s) have no recorded target "
          "reasoning (%s)" % (len(prod_files), ", ".join(prod_files)))
    sys.exit(0)

try:
    with open(notes_path) as fh:
        notes = fh.read()
except OSError as exc:
    print("NOTES.md is unreadable (%s)" % exc.__class__.__name__)
    sys.exit(0)

for base in prod_files:
    if base not in notes:
        print("%s is a prod items file but NOTES.md never names it, so its "
              "target reasoning is unrecorded" % base)
PYNOTES
    )
    if [[ -s "$notes_err" ]]; then
      while IFS= read -r note; do
        case "$note" in
          N/A:*) echo "N/A [$CHECK] ${note#N/A: }" ;;
        esac
      done < "$notes_err"
    fi
    rm -f "$notes_err"
    ;;

  env-samples-complete)
    # The DEPLOYED environments need a sample: dev, stage, prod. `local` is
    # deliberately excluded — it resolves to http://localhost:8080, a developer's
    # own machine, and one shipped ticket dir has no local file at all.
    #
    # A missing deployed env can also be legitimate: one shipped dir has no dev
    # file because dev holds no data for that customer to resolve against
    # (`WHERE customer_no='...'` returns nothing there), and mechanism testing
    # used an ad-hoc file instead. So NOTES.md can exempt a specific env, the
    # same way it can exempt a null guard.
    if [[ -z "${SRE_MIGRATION_ITEMS_DIR:-}" ]]; then
      echo "lint.sh: set SRE_MIGRATION_ITEMS_DIR to the tool's templates/<jira-id>/ dir" >&2
      exit 2
    fi
    if [[ ! -d "$SRE_MIGRATION_ITEMS_DIR" ]]; then
      echo "lint.sh: SRE_MIGRATION_ITEMS_DIR is not a directory: $SRE_MIGRATION_ITEMS_DIR" >&2
      exit 2
    fi
    env_err=$(mktemp)
    while IFS= read -r finding; do
      [[ -n "$finding" ]] && fail "$finding"
    done < <(python3 - "$SRE_MIGRATION_ITEMS_DIR" 2>"$env_err" <<'PYENV'
import glob, os, re, sys

items_dir = sys.argv[1]
DEPLOYED = ("dev", "stage", "prod")

present = {}
count = 0
for path in sorted(glob.glob(os.path.join(items_dir, "*.json"))):
    base = os.path.basename(path)
    if base.endswith(".schema.json"):
        continue
    count += 1
    # Match a hyphen/dot-delimited token, not a substring: "development" must not
    # count as dev, and env appears as a prefix in one tool and a suffix in the
    # other.
    tokens = set(re.split(r"[-_.]", os.path.splitext(base)[0].lower()))
    for env in DEPLOYED:
        if env in tokens:
            present.setdefault(env, []).append(base)

if count == 0:
    sys.stderr.write("N/A: no items files in %s, so there is no per-environment "
                     "coverage to check\n" % items_dir)
    sys.exit(0)

notes = ""
notes_path = os.path.join(items_dir, "NOTES.md")
if os.path.exists(notes_path):
    try:
        with open(notes_path) as fh:
            notes = fh.read()
    except OSError:
        notes = ""


def exempted(env):
    """True when NOTES.md explains this environment having no file.

    Mentioning the env is not enough — every NOTES.md quotes the
    `--site <dev|stage|prod>` usage, so a bare mention would exempt everything.
    Require an absence statement in the same sentence as the env name.
    """
    if not notes:
        return None
    absence = ("no %s file" % env, "no %s items" % env, "not exist", "無 %s" % env,
               "has no data", "no data", "returns nothing", "沒有")
    for sentence in re.split(r"(?<=[.。])\s+|\n\n", notes):
        low = sentence.lower()
        if env not in low:
            continue
        if any(tok in low for tok in absence):
            return " ".join(sentence.split())[:110]
    return None


for env in DEPLOYED:
    if env in present:
        continue
    reason = exempted(env)
    if reason is not None:
        sys.stderr.write("EXEMPT: no %s items file — documented: %s\n" % (env, reason))
    else:
        print("no items file for the %s environment, and NOTES.md does not "
              "explain its absence" % env)
PYENV
    )
    if [[ -s "$env_err" ]]; then
      while IFS= read -r note; do
        case "$note" in
          N/A:*)    echo "N/A [$CHECK] ${note#N/A: }" ;;
          EXEMPT:*) echo "EXEMPT [$CHECK] ${note#EXEMPT: }" ;;
        esac
      done < "$env_err"
    fi
    rm -f "$env_err"
    ;;

  *)
    # A typo in a check id must not read as "all clear".
    echo "lint.sh: unknown check: $CHECK" >&2
    usage
    exit 2
    ;;
esac

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "OK [$CHECK] $FILE"
