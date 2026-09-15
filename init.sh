#!/usr/bin/env bash
# init.sh — standard startup/verification entrypoint for agents working in this
# repo. Delegates to scripts/harness-verify.sh rather than re-implementing the
# gates: that script is already the single source of truth (same checks run as
# Stop hooks), and a second implementation here would drift from it the first
# time either one changed. See AGENTS.md for the rest of the startup workflow.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
exec bash "$REPO_DIR/scripts/harness-verify.sh" "$@"
