#!/usr/bin/env bash
# install-agents-md.sh — deploy canonical engineering rules into agent host files.
#
# Writes the contents of agents/engineering-rules.md into a marked block inside
# each host file (~/.claude/CLAUDE.md, ~/.gemini/GEMINI.md, $CODEX_HOME/AGENTS.md).
#
# ~/.gemini/GEMINI.md is the ANTIGRAVITY target, not a legacy gemini-cli leftover:
# Antigravity lives under ~/.gemini/ and its own docs
# (builtin/skills/agy-customizations/docs/rules.md) name GEMINI.md/AGENTS.md as the
# rules filenames. ~/.gemini/config/ is the global root but holds JSON only
# (skills.json, plugins.json, mcp_config.json) -- there is no global rules .md
# convention there. Do not "migrate" this to ~/.gemini/antigravity-cli/GEMINI.md;
# that path is read by nothing.
# For Kiro, the rules are deployed as a steering file
# (~/.kiro/steering/engineering-rules.md).
# Idempotent: a second run replaces the marked block in place.
#
# Every agent in _lib.sh's AGENTS list needs a target here; test_install_agents_md.sh
# asserts that, because codex was declared first-class in the installer while this
# script still wrote only three files, leaving it with no rules at all.
#
# Usage:
#   bash scripts/install-agents-md.sh             # install for all agents
#   bash scripts/install-agents-md.sh --claude    # only Claude Code
#   bash scripts/install-agents-md.sh --antigravity  # only Antigravity CLI
#   bash scripts/install-agents-md.sh --gemini       # alias for --antigravity
#   bash scripts/install-agents-md.sh --kiro      # only Kiro (steering)
#   bash scripts/install-agents-md.sh --codex     # only Codex CLI
#   bash scripts/install-agents-md.sh --uninstall # strip the block from all

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO_DIR/agents/engineering-rules.md"
BEGIN_MARK="<!-- BEGIN agent-skills-setup:engineering-rules -->"
END_MARK="<!-- END agent-skills-setup:engineering-rules -->"

WANT_CLAUDE=1
WANT_GEMINI=1
WANT_KIRO=1
WANT_CODEX=1
ACTION="install"

# Codex reads a global AGENTS.md from its config home, honouring CODEX_HOME
# (default ~/.codex). AGENTS.override.md wins over AGENTS.md at that level, so
# never write the override file — it would shadow a user's own.
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"

# An agent-specific flag means "only this one": zero every target, then the arm
# below re-enables its own. Pairwise zeroing (--claude turning off exactly the
# other two) silently missed each newly added agent.
only() { WANT_CLAUDE=0; WANT_GEMINI=0; WANT_KIRO=0; WANT_CODEX=0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)    only; WANT_CLAUDE=1; shift ;;
    # --gemini kept as an alias: the flag predates the Antigravity rename and
    # is referenced by older notes and by test_install_agents_md.sh.
    --antigravity|--gemini) only; WANT_GEMINI=1; shift ;;
    --kiro)      only; WANT_KIRO=1;   shift ;;
    --codex)     only; WANT_CODEX=1;  shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \?//'
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
[[ $WANT_GEMINI -eq 1 ]] && run "Antigravity CLI" "$HOME/.gemini/GEMINI.md"
[[ $WANT_CODEX  -eq 1 ]] && run "Codex CLI"   "$CODEX_DIR/AGENTS.md"

# Kiro uses steering files instead of a KIRO.md host file.
# Deploy as ~/.kiro/steering/engineering-rules.md (plain copy, no marked block).
if [[ $WANT_KIRO -eq 1 ]]; then
  KIRO_TARGET="$HOME/.kiro/steering/engineering-rules.md"
  mkdir -p "$(dirname "$KIRO_TARGET")"
  if [[ "$ACTION" == "install" ]]; then
    cp "$SOURCE" "$KIRO_TARGET"
    echo "Kiro → $KIRO_TARGET"
    echo "  wrote engineering-rules.md to Kiro steering"
  else
    if [[ -f "$KIRO_TARGET" ]]; then
      rm "$KIRO_TARGET"
      echo "Kiro → removed $KIRO_TARGET"
    else
      echo "Kiro → $KIRO_TARGET not present, skipping"
    fi
  fi
fi

echo "Done."
