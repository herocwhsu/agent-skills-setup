#!/usr/bin/env bash
# test_tmux_yank.sh — tests for infra/tmux-yank/lib/tmux-yank.sh
#
# The script is an installer: brew/apt/git/tmux all have side effects, so every
# one is mocked on PATH and HOME is redirected to a temp dir. What is actually
# asserted is the ~/.tmux.conf handling — create when absent, patch when the
# tmux-yank plugin line is missing, leave alone when already present.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/lib/tmux-yank.sh"
PASS=0
FAIL=0

ok()  { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL  $1: $2"; FAIL=$((FAIL + 1)); }

# A sandbox with every external command the installer calls stubbed out.
make_sandbox() {
  local dir="$1"
  mkdir -p "$dir/bin" "$dir/.tmux/plugins/tpm/bin"

  # tmux must report a version and pretend a server is already running, so the
  # script does not try to create and kill a real session.
  cat > "$dir/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -V) echo "tmux 3.4" ;;
  list-sessions) exit 0 ;;
  *) exit 0 ;;
esac
EOF

  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/git"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/brew"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/sudo"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/bin/apt-get"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dir/.tmux/plugins/tpm/bin/install_plugins"
  chmod +x "$dir/bin/"* "$dir/.tmux/plugins/tpm/bin/install_plugins"
}

run_script() {
  local home="$1"
  HOME="$home" PATH="$home/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$SCRIPT" 2>&1 || true
}

# --- creates a conf when none exists ----------------------------------------
tmp=$(mktemp -d); make_sandbox "$tmp"
out=$(run_script "$tmp")
if [[ -f "$tmp/.tmux.conf" ]] && grep -q "tmux-yank" "$tmp/.tmux.conf"; then
  ok "creates ~/.tmux.conf with the tmux-yank plugin when absent"
else
  bad "creates ~/.tmux.conf with the tmux-yank plugin when absent" "conf missing or lacks plugin:
$out"
fi

# The fallback conf must keep OSC 52 off: it races pbcopy and overwrites the
# clipboard on macOS, which is the whole point of the skill.
if grep -q "set-clipboard off" "$tmp/.tmux.conf"; then
  ok "fallback conf disables OSC 52 so pbcopy stays authoritative"
else
  bad "fallback conf disables OSC 52 so pbcopy stays authoritative" "not found in conf"
fi
rm -rf "$tmp"

# --- patches an existing conf that lacks the plugin -------------------------
tmp=$(mktemp -d); make_sandbox "$tmp"
printf "set -g mouse on\nrun '~/.tmux/plugins/tpm/tpm'\n" > "$tmp/.tmux.conf"
out=$(run_script "$tmp")
if grep -q "tmux-yank" "$tmp/.tmux.conf"; then
  ok "adds the tmux-yank plugin line to an existing conf"
else
  bad "adds the tmux-yank plugin line to an existing conf" "plugin line not added:
$out"
fi
# The plugin must be declared before tpm runs, or tpm never loads it.
plugin_line=$(grep -n "tmux-yank" "$tmp/.tmux.conf" 2>/dev/null | head -1 | cut -d: -f1 || true)
tpm_line=$(grep -n "tpm/tpm" "$tmp/.tmux.conf" 2>/dev/null | head -1 | cut -d: -f1 || true)
if [[ -n "$plugin_line" && -n "$tpm_line" && "$plugin_line" -lt "$tpm_line" ]]; then
  ok "inserts the plugin line before the tpm run line"
else
  bad "inserts the plugin line before the tpm run line" "plugin at ${plugin_line:-?}, tpm at ${tpm_line:-?}"
fi
# The user's own settings must survive the patch.
if grep -q "set -g mouse on" "$tmp/.tmux.conf"; then
  ok "preserves existing settings when patching"
else
  bad "preserves existing settings when patching" "mouse setting lost"
fi
rm -rf "$tmp"

# --- appends when there is no tpm run line to anchor to ---------------------
tmp=$(mktemp -d); make_sandbox "$tmp"
printf "set -g mouse on\n" > "$tmp/.tmux.conf"
out=$(run_script "$tmp")
if grep -q "tmux-yank" "$tmp/.tmux.conf" && grep -q "tpm/tpm" "$tmp/.tmux.conf"; then
  ok "appends plugin and tpm run line when no anchor exists"
else
  bad "appends plugin and tpm run line when no anchor exists" "got:
$(cat "$tmp/.tmux.conf")"
fi
rm -rf "$tmp"

# --- idempotent when the plugin is already declared -------------------------
tmp=$(mktemp -d); make_sandbox "$tmp"
printf "set -g @plugin 'tmux-plugins/tmux-yank'\nrun '~/.tmux/plugins/tpm/tpm'\n" > "$tmp/.tmux.conf"
before=$(cat "$tmp/.tmux.conf")
out=$(run_script "$tmp")
if [[ "$(cat "$tmp/.tmux.conf")" == "$before" ]]; then
  ok "leaves a conf that already declares tmux-yank untouched"
else
  bad "leaves a conf that already declares tmux-yank untouched" "conf was modified:
$(diff <(printf '%s' "$before") "$tmp/.tmux.conf" || true)"
fi
# Re-running must not accumulate duplicate plugin lines.
count=$(grep -c "tmux-yank" "$tmp/.tmux.conf" 2>/dev/null || true)
if [[ "${count:-0}" -eq 1 ]]; then
  ok "does not duplicate the plugin line on re-run"
else
  bad "does not duplicate the plugin line on re-run" "found ${count:-0} occurrences"
fi
rm -rf "$tmp"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
