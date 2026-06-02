#!/usr/bin/env bash
# Tests the macOS tuning script by mocking macOS-specific commands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
TUNE_MACOS="$SCRIPT_DIR/tune_macos.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Mocking defaults, killall, and sudo
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/defaults" <<'EOF'
#!/usr/bin/env bash
echo "defaults $@" >> "$MOCK_LOG"
EOF

cat > "$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
echo "killall $@" >> "$MOCK_LOG"
EOF

# sudo might be used for purge
cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $@" >> "$MOCK_LOG"
EOF

chmod +x "$MOCK_BIN"/*
export PATH="$MOCK_BIN:$PATH"
export MOCK_LOG="$TMP/mock.log"
touch "$MOCK_LOG"

# --- Test 1: Script existence ---
if [ ! -f "$TUNE_MACOS" ]; then
    echo "FAIL: $TUNE_MACOS does not exist"
    exit 1
fi

# --- Test 2: Execution and calls ---
bash "$TUNE_MACOS"

grep -q "defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false" "$MOCK_LOG" || { echo "FAIL: NSAutomaticWindowAnimationsEnabled not set"; exit 1; }
grep -q "defaults write com.apple.dock expose-animation-duration -float 0.1" "$MOCK_LOG" || { echo "FAIL: expose-animation-duration not set"; exit 1; }
grep -q "defaults write com.apple.finder QLInlinePreview -bool false" "$MOCK_LOG" || { echo "FAIL: QLInlinePreview not set"; exit 1; }
grep -q "defaults write com.apple.dock launchanim -bool false" "$MOCK_LOG" || { echo "FAIL: launchanim not set"; exit 1; }
grep -q "killall Dock" "$MOCK_LOG" || { echo "FAIL: Dock not restarted"; exit 1; }
grep -q "killall Finder" "$MOCK_LOG" || { echo "FAIL: Finder not restarted"; exit 1; }
grep -q "sudo purge" "$MOCK_LOG" || { echo "FAIL: sudo purge not called"; exit 1; }

echo "OK: macOS tuning script called all expected commands."
