#!/usr/bin/env bash
# update-agents.sh — report, and optionally apply, updates for the agent CLIs.
#
# Every agent ships its own update path, so there is no single command to run:
#   claude    self-update    `claude update`
#   codex     self-update    `codex update`
#   hermes    self-update    `hermes update`
#   agy       self-update    `agy update`  (Antigravity CLI -- this is what the
#                            repo's agent name "gemini" targets, via
#                            ~/.gemini/antigravity-cli/skills. The retired
#                            @google/gemini-cli npm package is deliberately not
#                            handled: it was removed in favour of agy.)
#   kiro-cli  NOT SCRIPTABLE it is a macOS app bundle under /Applications, so a
#                            script cannot replace it; reported, never touched.
#
# No npm path is used at all, and that is deliberate. npm resolves its global
# prefix from whichever version manager wins on PATH, which need not be the one
# holding the package: on a machine with both nvm and volta, `npm uninstall -g`
# reported success having removed nothing. Any future npm-installed agent must
# pin --prefix to the root that owns the package rather than trusting npm.
#
# Default is report-only. Upgrading a CLI is hard to reverse and can carry
# breaking changes, so --apply is required to actually change anything.
#
# The currently-running agent is skipped unless --include-self: replacing the
# binary of the process executing this script is the one case with no safe
# outcome. Claude Code also auto-updates itself, so skipping it loses nothing.
set -uo pipefail   # no -e: one agent failing must not abort the rest

APPLY=0
INCLUDE_SELF=0
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)        APPLY=1; shift ;;
    --include-self) INCLUDE_SELF=1; shift ;;
    --agent)        ONLY="$2"; shift 2 ;;
    --agent=*)      ONLY="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Which agent is running this? CLAUDECODE is set by Claude Code itself.
running_agent() {
  [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE:-}" ]] && { echo "claude"; return; }
  echo ""
}
SELF="$(running_agent)"

version_of() {
  command -v "$1" >/dev/null 2>&1 || return 0
  "$1" --version 2>&1 | head -1
}

present() { command -v "$1" >/dev/null 2>&1; }

upgrade_cmd() {
  case "$1" in
    claude)   echo "claude update" ;;
    codex)    echo "codex update" ;;
    hermes)   echo "hermes update" ;;
    agy)      echo "agy update" ;;
    kiro-cli) echo "" ;;   # app bundle: no scriptable path
  esac
}

AGENTS=(claude codex kiro-cli hermes agy)
rc=0
acted=0

for a in "${AGENTS[@]}"; do
  [[ -z "$ONLY" || "$ONLY" == "$a" ]] || continue
  if ! present "$a"; then
    printf '  %-9s not installed\n' "$a"
    continue
  fi

  cur="$(version_of "$a")"
  printf '  %-9s %s\n' "$a" "${cur:-unknown}"

  cmd="$(upgrade_cmd "$a")"
  if [[ -z "$cmd" ]]; then
    echo "            no scriptable update path (macOS app bundle) — update it from the app"
    continue
  fi
  if [[ "$a" == "$SELF" && $INCLUDE_SELF -eq 0 ]]; then
    echo "            skipped: this agent is running this script (--include-self to override)"
    continue
  fi
  if [[ $APPLY -eq 0 ]]; then
    echo "            would run: $cmd"
    continue
  fi

  echo "            running: $cmd"
  if out=$(eval "$cmd" 2>&1); then
    acted=$((acted + 1))
    new="$(version_of "$a")"
    if [[ "$new" != "$cur" ]]; then
      echo "            updated: $cur -> $new"
    else
      echo "            already current"
    fi
  else
    # Non-fatal by design: a network blip on one CLI must not fail a skills install.
    echo "            WARNING: update failed, continuing" >&2
    printf '%s\n' "$out" | tail -3 | sed 's/^/              /' >&2
    rc=1
  fi
done

if [[ $APPLY -eq 0 ]]; then
  echo ""
  echo "  report only — re-run with --apply to install updates"
fi
exit $rc
