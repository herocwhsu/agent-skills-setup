#!/usr/bin/env bash
# install-agents-md.sh — deploy canonical engineering rules into agent host files.
#
# Writes the contents of agents/engineering-rules.md into a marked block inside
# each host file (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md). Idempotent: a second
# run replaces the marked block in place; the rest of the host file is untouched.
#
# Usage:
#   bash scripts/install-agents-md.sh             # install for both
#   bash scripts/install-agents-md.sh --claude    # only Claude Code
#   bash scripts/install-agents-md.sh --gemini    # only Gemini CLI
#   bash scripts/install-agents-md.sh --uninstall # strip the block from both

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO_DIR/agents/engineering-rules.md"
BEGIN_MARK="<!-- BEGIN agent-skills-setup:engineering-rules -->"
END_MARK="<!-- END agent-skills-setup:engineering-rules -->"

WANT_CLAUDE=1
WANT_GEMINI=1
ACTION="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)    WANT_GEMINI=0; shift ;;
    --gemini)    WANT_CLAUDE=0; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$SOURCE" ]] || { echo "Source not found: $SOURCE" >&2; exit 1; }

# write_block <target_file>
#   - if marked block exists: replace it
#   - else if file exists: append (with leading blank line separator)
#   - else: create file containing only the marked block
write_block() {
  local target="$1"
  mkdir -p "$(dirname "$target")"

  if [[ -f "$target" ]] && grep -qF "$BEGIN_MARK" "$target"; then
    python3 - "$target" "$SOURCE" "$BEGIN_MARK" "$END_MARK" <<'PY'
import sys, pathlib
target, src, begin, end = sys.argv[1:]
text = pathlib.Path(target).read_text()
body = pathlib.Path(src).read_text().rstrip() + "\n"
b = text.index(begin)
e = text.index(end) + len(end)
new = text[:b] + begin + "\n" + body + end + text[e:]
pathlib.Path(target).write_text(new)
PY
    echo "  refreshed block in $target"
    return
  fi

  {
    if [[ -s "$target" ]]; then
      cat "$target"
      tail -c 1 "$target" | od -An -c | grep -q '\\n' || echo
      echo
    fi
    echo "$BEGIN_MARK"
    cat "$SOURCE"
    echo "$END_MARK"
  } > "$target.tmp"
  mv "$target.tmp" "$target"
  echo "  wrote block to $target"
}

# strip_block <target_file>
strip_block() {
  local target="$1"
  [[ -f "$target" ]] || { echo "  $target not present, skipping"; return; }
  grep -qF "$BEGIN_MARK" "$target" || { echo "  no marked block in $target, skipping"; return; }
  python3 - "$target" "$BEGIN_MARK" "$END_MARK" <<'PY'
import sys, pathlib
target, begin, end = sys.argv[1:]
p = pathlib.Path(target)
text = p.read_text()
b = text.index(begin)
e = text.index(end) + len(end)
# Eat one surrounding newline on each side so we don't leave a double-blank.
if b > 0 and text[b-1] == "\n":
    b -= 1
if e < len(text) and text[e] == "\n":
    e += 1
remainder = text[:b] + text[e:]
if remainder.strip() == "":
    p.unlink()
else:
    p.write_text(remainder)
PY
  echo "  removed block from $target"
}

run() {
  local label="$1" target="$2"
  echo "$label → $target"
  if [[ "$ACTION" == "install" ]]; then
    write_block "$target"
  else
    strip_block "$target"
  fi
}

[[ $WANT_CLAUDE -eq 1 ]] && run "Claude Code" "$HOME/.claude/CLAUDE.md"
[[ $WANT_GEMINI -eq 1 ]] && run "Gemini CLI"  "$HOME/.gemini/GEMINI.md"

echo "Done."
