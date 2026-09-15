#!/usr/bin/env bash
# test_registry_types.sh — tests for the github-skill and plugin registry types
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1: $2"; fail=$((fail + 1)); }

# shellcheck source=scripts/_lib.sh
source "$SCRIPTS_DIR/_lib.sh"

# --- Fixtures: fake GitHub repos zipped the way codeload serves them -------
FIXDIR="$TMP/fixtures"
mkdir -p "$FIXDIR/multi-skills-main/skills/alpha" "$FIXDIR/multi-skills-main/skills/beta"
echo "alpha skill" > "$FIXDIR/multi-skills-main/skills/alpha/SKILL.md"
echo "beta skill"  > "$FIXDIR/multi-skills-main/skills/beta/SKILL.md"
mkdir -p "$FIXDIR/rootskill-main/scripts"
echo "root skill" > "$FIXDIR/rootskill-main/SKILL.md"
echo "helper"     > "$FIXDIR/rootskill-main/scripts/run.sh"

python3 - "$FIXDIR" <<'EOF'
import os, sys, zipfile
fixdir = sys.argv[1]
for name in ("multi-skills", "rootskill"):
    src = os.path.join(fixdir, f"{name}-main")
    with zipfile.ZipFile(os.path.join(fixdir, f"{name}.zip"), "w") as z:
        for root, _, files in os.walk(src):
            for f in files:
                p = os.path.join(root, f)
                z.write(p, os.path.relpath(p, fixdir))
EOF

# Stub the downloader: serve fixture zips instead of hitting GitHub.
# URL shape: https://github.com/<owner>/<repo>/archive/refs/heads/main.zip
download_file() {
  local url="$1" dest="$2"
  local reponame
  reponame=$(echo "$url" | cut -d/ -f5)
  if [[ -f "$FIXDIR/$reponame.zip" ]]; then
    cp "$FIXDIR/$reponame.zip" "$dest"
  else
    return 1
  fi
}

TARGET="$TMP/skills-target"

# --- Test 1: github-skill installs exactly one skill, not its siblings ---
mkdir -p "$TARGET"
install_github_single_skill "acme/multi-skills" "skills/alpha" "$TARGET" >/dev/null 2>&1
if [[ -f "$TARGET/alpha/SKILL.md" && ! -e "$TARGET/beta" ]]; then
  ok "single skill installed without siblings"
else
  bad "single skill installed without siblings" "expected only alpha/ in $TARGET"
fi

# --- Test 2: re-install is idempotent (no nested dir) ---
install_github_single_skill "acme/multi-skills" "skills/alpha" "$TARGET" >/dev/null 2>&1
if [[ -f "$TARGET/alpha/SKILL.md" && ! -e "$TARGET/alpha/alpha" ]]; then
  ok "re-install does not nest"
else
  bad "re-install does not nest" "found $TARGET/alpha/alpha or missing SKILL.md"
fi

# --- Test 3: name override ---
install_github_single_skill "acme/multi-skills" "skills/beta" "$TARGET" "renamed" >/dev/null 2>&1
if [[ -f "$TARGET/renamed/SKILL.md" && ! -e "$TARGET/beta" ]]; then
  ok "name override installs under custom name"
else
  bad "name override installs under custom name" "expected $TARGET/renamed"
fi

# --- Test 4: repo root as skill ('.') with name ---
install_github_single_skill "acme/rootskill" "." "$TARGET" "linear" >/dev/null 2>&1
if [[ -f "$TARGET/linear/SKILL.md" && -f "$TARGET/linear/scripts/run.sh" ]]; then
  ok "repo-root skill installed under given name"
else
  bad "repo-root skill installed under given name" "expected $TARGET/linear with full content"
fi

# --- Test 5: missing skill path errors without touching target ---
if install_github_single_skill "acme/multi-skills" "skills/nope" "$TARGET" >/dev/null 2>&1; then
  bad "missing skill path errors" "expected nonzero exit"
else
  ok "missing skill path errors"
fi

# --- Test 6: uninstall removes by resolved name ---
uninstall_github_single_skill "acme/multi-skills" "skills/alpha" "$TARGET" >/dev/null
uninstall_github_single_skill "acme/rootskill" "." "$TARGET" "linear" >/dev/null
if [[ ! -e "$TARGET/alpha" && ! -e "$TARGET/linear" ]]; then
  ok "uninstall removes single skills"
else
  bad "uninstall removes single skills" "alpha or linear still present"
fi

# --- Plugin type: stub claude CLI that logs its args -----------------------
BIN="$TMP/bin"
CLAUDE_LOG="$TMP/claude.log"
mkdir -p "$BIN" "$TMP/emptybin"
cat > "$BIN/claude" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CLAUDE_LOG"
exit 0
EOF
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"

# --- Test 7: plugin install adds marketplace then installs name@repo ---
: > "$CLAUDE_LOG"
install_claude_plugin "jarrodwatts/claude-hud" "claude-hud" >/dev/null
if grep -qx "plugin marketplace add jarrodwatts/claude-hud" "$CLAUDE_LOG" \
   && grep -qx "plugin install claude-hud@claude-hud" "$CLAUDE_LOG"; then
  ok "plugin install: marketplace add + install with default marketplace name"
else
  bad "plugin install" "unexpected claude calls: $(cat "$CLAUDE_LOG")"
fi

# --- Test 8: explicit marketplace name overrides repo name ---
: > "$CLAUDE_LOG"
install_claude_plugin "anthropics/skills" "webapp-testing" "anthropic-agent-skills" >/dev/null
if grep -qx "plugin install webapp-testing@anthropic-agent-skills" "$CLAUDE_LOG"; then
  ok "plugin install honors explicit marketplace name"
else
  bad "plugin install honors explicit marketplace name" "calls: $(cat "$CLAUDE_LOG")"
fi

# --- Test 9: plugin uninstall ---
: > "$CLAUDE_LOG"
uninstall_claude_plugin "jarrodwatts/claude-hud" "claude-hud" >/dev/null
if grep -qx "plugin uninstall claude-hud@claude-hud" "$CLAUDE_LOG"; then
  ok "plugin uninstall calls claude CLI"
else
  bad "plugin uninstall calls claude CLI" "calls: $(cat "$CLAUDE_LOG")"
fi

# --- Test 10: missing claude CLI skips gracefully (exit 0) ---
if (PATH="$TMP/emptybin" install_claude_plugin "a/b" "c" >/dev/null 2>&1); then
  ok "missing claude CLI skips without failing"
else
  bad "missing claude CLI skips without failing" "expected exit 0"
fi

# --- Test 11: validator accepts well-formed new types ---
GOOD="$TMP/registry-good.txt"
cat > "$GOOD" <<'EOF'
github-skill  anthropics/skills  skills/webapp-testing
github-skill  wrsmith108/linear-claude-skill  .  linear
plugin        anthropics/knowledge-work-plugins  productivity
plugin        anthropics/skills  webapp-testing  anthropic-agent-skills
EOF
if REGISTRY_FILE="$GOOD" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  ok "validator accepts well-formed github-skill/plugin entries"
else
  bad "validator accepts well-formed entries" "expected exit 0"
fi

# --- Test 12: validator rejects malformed new types ---
BAD_REG="$TMP/registry-bad.txt"
cat > "$BAD_REG" <<'EOF'
github-skill  no-slash-repo  skills/x
github-skill  acme/repo
plugin        acme/repo
EOF
if REGISTRY_FILE="$BAD_REG" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  bad "validator rejects malformed entries" "expected nonzero exit"
else
  ok "validator rejects malformed entries"
fi

# --- Test 13: real registry.txt still validates ---
if bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  ok "repo registry.txt validates"
else
  bad "repo registry.txt validates" "validate-registry.sh failed on the real registry"
fi

# --- Test 14: validator accepts well-formed plugin-optional entries ---
GOOD_OPT="$TMP/registry-good-optional.txt"
cat > "$GOOD_OPT" <<'EOF'
plugin-optional  anthropics/knowledge-work-plugins  productivity
plugin-optional  anthropics/knowledge-work-plugins  product-management
EOF
if REGISTRY_FILE="$GOOD_OPT" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  ok "validator accepts well-formed plugin-optional entries"
else
  bad "validator accepts well-formed plugin-optional entries" "expected exit 0"
fi

# --- Test 15: validator rejects malformed plugin-optional entries ---
BAD_OPT="$TMP/registry-bad-optional.txt"
cat > "$BAD_OPT" <<'EOF'
plugin-optional  no-slash-repo
EOF
if REGISTRY_FILE="$BAD_OPT" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  bad "validator rejects malformed plugin-optional entries" "expected nonzero exit"
else
  ok "validator rejects malformed plugin-optional entries"
fi

# --- Test 16: is_plugin_opt_in gates on --with-plugin membership ---
PLUGIN_OPT_IN=()
if is_plugin_opt_in "productivity"; then
  bad "is_plugin_opt_in empty array" "expected false with no opt-ins"
else
  ok "is_plugin_opt_in empty array returns false"
fi

PLUGIN_OPT_IN=("productivity")
if is_plugin_opt_in "productivity"; then
  ok "is_plugin_opt_in true for requested plugin"
else
  bad "is_plugin_opt_in true for requested plugin" "expected true for 'productivity'"
fi
if is_plugin_opt_in "product-management"; then
  bad "is_plugin_opt_in false for non-requested plugin" "expected false for 'product-management'"
else
  ok "is_plugin_opt_in false for non-requested plugin"
fi

# --- @ref pinning: owner/repo@ref fetches archive/<ref>.zip, not HEAD ------
URL_LOG="$TMP/urls.log"
download_file() {
  echo "$1" >> "$URL_LOG"
  local url="$1" dest="$2"
  local reponame
  reponame=$(echo "$url" | cut -d/ -f5)
  if [[ -f "$FIXDIR/$reponame.zip" ]]; then
    cp "$FIXDIR/$reponame.zip" "$dest"
  else
    return 1
  fi
}

# --- Test 17: github-skill with @ref fetches that ref, not HEAD ---
: > "$URL_LOG"
install_github_single_skill "acme/multi-skills@deadbeef1234" "skills/alpha" "$TARGET" >/dev/null 2>&1
if grep -qx "https://github.com/acme/multi-skills/archive/deadbeef1234.zip" "$URL_LOG"; then
  ok "github-skill @ref fetches archive/<ref>.zip"
else
  bad "github-skill @ref fetches archive/<ref>.zip" "got: $(cat "$URL_LOG")"
fi

# --- Test 18: github-skill without @ref still fetches HEAD (unchanged) ---
: > "$URL_LOG"
install_github_single_skill "acme/multi-skills" "skills/alpha" "$TARGET" >/dev/null 2>&1
if grep -qx "https://github.com/acme/multi-skills/archive/HEAD.zip" "$URL_LOG"; then
  ok "github-skill without @ref still fetches HEAD"
else
  bad "github-skill without @ref still fetches HEAD" "got: $(cat "$URL_LOG")"
fi

# --- Test 19: github (multi-skill installer) with @ref fetches that ref ---
: > "$URL_LOG"
install_github_skill "acme/multi-skills@deadbeef1234" "skills" "$TMP/target-pinned" >/dev/null 2>&1
if grep -qx "https://github.com/acme/multi-skills/archive/deadbeef1234.zip" "$URL_LOG"; then
  ok "github @ref fetches archive/<ref>.zip"
else
  bad "github @ref fetches archive/<ref>.zip" "got: $(cat "$URL_LOG")"
fi

# --- Test 20: @ref does not leak into the installed skill name ---
if [[ -f "$TARGET/alpha/SKILL.md" && ! -e "$TARGET/alpha@deadbeef1234" ]]; then
  ok "@ref pin is stripped from the installed skill name"
else
  bad "@ref pin is stripped from the installed skill name" "unexpected entries under $TARGET"
fi

# --- Test 21: validator accepts a pinned github/github-skill entry ---
GOOD_PIN="$TMP/registry-good-pin.txt"
cat > "$GOOD_PIN" <<'EOF'
github        obra/superpowers@b36e0829c6d0140e93cfef2ca599b1b07d4a7797  skills
github-skill  anthropics/skills@34040c9c568585f6929bedeaad110ad08f079624  skills/webapp-testing
EOF
if REGISTRY_FILE="$GOOD_PIN" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  ok "validator accepts pinned github/github-skill entries"
else
  bad "validator accepts pinned github/github-skill entries" "expected exit 0"
fi

# --- Test 22: validator still rejects a pinned entry missing owner/repo shape ---
BAD_PIN="$TMP/registry-bad-pin.txt"
cat > "$BAD_PIN" <<'EOF'
github-skill  no-slash-repo@deadbeef  skills/x
EOF
if REGISTRY_FILE="$BAD_PIN" bash "$SCRIPTS_DIR/validate-registry.sh" >/dev/null 2>&1; then
  bad "validator rejects malformed pinned entry" "expected nonzero exit"
else
  ok "validator rejects malformed pinned entry"
fi

# --- @ref pinning on uninstall: the pin must not leak into the resolved name -
# uninstall_github_single_skill derives its default name from skill-path (or
# reponame for "."), both computed from repo_ref with @ref already stripped.
# uninstall_github_skill's fallback path (installed.txt missing) strips @ref
# the same way before matching the extracted "<reponame>-*" dir; if the ref
# leaked through, that match would fail silently and nothing would be removed.

# --- Test 23: uninstall_github_single_skill resolves name with an @ref pin ---
# Uses skill_path "." deliberately: the resolved default name then comes from
# reponame ("${repo##*/}"), which is only correct if repo_ref's @ref was
# actually stripped first. A skill_path like "skills/alpha" would resolve to
# "alpha" via basename() regardless of repo_ref, so it can't catch a broken
# strip — this caught exactly that gap in an earlier draft of this test.
mkdir -p "$TARGET/multi-skills"; echo "root skill" > "$TARGET/multi-skills/SKILL.md"
uninstall_github_single_skill "acme/multi-skills@deadbeef1234" "." "$TARGET" >/dev/null
if [[ ! -e "$TARGET/multi-skills" ]]; then
  ok "uninstall_github_single_skill resolves name with @ref pin"
else
  bad "uninstall_github_single_skill resolves name with @ref pin" "multi-skills still present in $TARGET"
fi

# --- Test 24: uninstall_github_skill fallback resolves @ref for both the
# fetch URL and the extracted-dir match, and actually removes the skills ---
UNINSTALL_TARGET="$TMP/target-uninstall-pinned"
mkdir -p "$UNINSTALL_TARGET/alpha" "$UNINSTALL_TARGET/beta"
echo "alpha skill" > "$UNINSTALL_TARGET/alpha/SKILL.md"
echo "beta skill"  > "$UNINSTALL_TARGET/beta/SKILL.md"
FAKE_REPO_DIR="$TMP/fake-repo-no-installed-list"
mkdir -p "$FAKE_REPO_DIR"
echo "registry-types-test-$$" > "$FAKE_REPO_DIR/.skills-repo-id"
: > "$URL_LOG"
out=$(REPO_DIR="$FAKE_REPO_DIR" uninstall_github_skill "acme/multi-skills@deadbeef1234" "skills" "$UNINSTALL_TARGET" 2>&1)
if grep -qx "https://github.com/acme/multi-skills/archive/deadbeef1234.zip" "$URL_LOG" \
   && [[ ! -e "$UNINSTALL_TARGET/alpha" && ! -e "$UNINSTALL_TARGET/beta" ]]; then
  ok "uninstall_github_skill fallback resolves @ref for fetch and dir match"
else
  bad "uninstall_github_skill fallback resolves @ref for fetch and dir match" \
      "urls: $(cat "$URL_LOG"); out: $out; target: $(ls "$UNINSTALL_TARGET" 2>/dev/null)"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
