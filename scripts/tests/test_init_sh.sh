#!/usr/bin/env bash
# Tests for init.sh: builds .venv from requirements-dev.txt when it is missing,
# then hands off to scripts/harness-verify.sh.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

pass=0
ok()  { echo "  PASS  $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL  $1"; [[ -n "${2:-}" ]] && echo "        $2"; exit 1; }

# A fake repo holding the real init.sh, a stub verify script, and a stub python3
# whose `-m venv DIR` makes DIR/bin/pip. PIP_FAIL=1 makes that pip exit non-zero.
make_repo() {
  local d="$1"
  mkdir -p "$d/scripts" "$d/stubbin"
  cp "$REPO_DIR/init.sh" "$d/init.sh"
  echo "requests==0.0.0" > "$d/requirements-dev.txt"
  printf '#!/usr/bin/env bash\necho "verify ran"\n' > "$d/scripts/harness-verify.sh"
  cat > "$d/stubbin/python3" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "Python ${STUB_PY_VERSION:-3.14.7}"; exit 0; fi
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  mkdir -p "$3/bin"
  cat > "$3/bin/pip" <<'PIP'
#!/usr/bin/env bash
echo "pip $*" >> "$(dirname "$0")/../pip.log"
[[ "${PIP_FAIL:-0}" == "1" ]] && exit 1
exit 0
PIP
  chmod +x "$3/bin/pip"
  exit 0
fi
exec /usr/bin/env -i /usr/bin/python3 "$@"
STUB
  chmod +x "$d/stubbin/python3"
}

# --- 1. missing .venv is built from requirements-dev.txt, then verify runs ---
d="$TMP/r1"; make_repo "$d"
out=$(PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) \
  || bad "init.sh exits 0 when the venv builds" "$out"
[[ -x "$d/.venv/bin/pip" ]] && ok ".venv is created when missing" \
  || bad ".venv is created when missing" "$out"grep -q "install.* -r $d/requirements-dev.txt" "$d/.venv/pip.log" \
  && ok "pip installs requirements-dev.txt" \
  || bad "pip installs requirements-dev.txt" "$(cat "$d/.venv/pip.log" 2>&1)"
[[ "$out" == *"verify ran"* ]] && ok "hands off to harness-verify.sh after the build" \
  || bad "hands off to harness-verify.sh after the build" "$out"

# --- 2. an existing .venv is left alone ---
rm -f "$d/.venv/pip.log"
out=$(PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) || bad "second run exits 0" "$out"
[[ ! -f "$d/.venv/pip.log" ]] && ok "existing .venv is not rebuilt" \
  || bad "existing .venv is not rebuilt" "$(cat "$d/.venv/pip.log")"

# --- 3. a failed build exits non-zero, leaves no half-built .venv, skips verify ---
d="$TMP/r3"; make_repo "$d"
status=0
out=$(PIP_FAIL=1 PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) || status=$?
[[ $status -ne 0 ]] && ok "failed build exits non-zero" \
  || bad "failed build exits non-zero" "$out"
[[ ! -d "$d/.venv" ]] && ok "failed build leaves no .venv behind" \
  || bad "failed build leaves no .venv behind"
[[ "$out" != *"verify ran"* ]] && ok "failed build does not run the gates" \
  || bad "failed build does not run the gates" "$out"

# --- 4. no requirements-dev.txt: nothing to build, verify still runs ---
d="$TMP/r4"; make_repo "$d"; rm "$d/requirements-dev.txt"
out=$(PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) || bad "no manifest exits 0" "$out"
[[ ! -d "$d/.venv" && "$out" == *"verify ran"* ]] && ok "no manifest: skips the build, runs verify" \
  || bad "no manifest: skips the build, runs verify" "$out"

# --- 5. python3 differs from .python-version: fail before the build ---
d="$TMP/r5"; make_repo "$d"; echo "3.14.7" > "$d/.python-version"
status=0
out=$(STUB_PY_VERSION=3.12.1 PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) || status=$?
[[ $status -ne 0 && "$out" == *"3.12.1"* && "$out" == *"3.14.7"* ]] \
  && ok "version mismatch exits non-zero and names both versions" \
  || bad "version mismatch exits non-zero and names both versions" "status $status: $out"
[[ ! -d "$d/.venv" && "$out" != *"verify ran"* ]] \
  && ok "version mismatch builds nothing and runs no gates" \
  || bad "version mismatch builds nothing and runs no gates" "$out"

# --- 6. matching .python-version still builds ---
d="$TMP/r6"; make_repo "$d"; echo "3.14.7" > "$d/.python-version"
out=$(STUB_PY_VERSION=3.14.7 PATH="$d/stubbin:$PATH" bash "$d/init.sh" 2>&1) \
  || bad "matching version builds" "$out"
[[ -x "$d/.venv/bin/pip" && "$out" == *"verify ran"* ]] && ok "matching version builds and verifies" \
  || bad "matching version builds and verifies" "$out"

# --- 7. terminated mid-build: no half-built .venv is left for the next run to trust ---
d="$TMP/r7"; make_repo "$d"
cat > "$d/stubbin/python3" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "Python 3.14.7"; exit 0; fi
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  mkdir -p "$3/bin"
  printf '#!/usr/bin/env bash\ntouch "%s/pip-started"\nsleep 30\n' "$(dirname "$3")" > "$3/bin/pip"
  chmod +x "$3/bin/pip"
  exit 0
fi
exit 0
STUB
PATH="$d/stubbin:$PATH" bash "$d/init.sh" >"$TMP/r7.out" 2>&1 &
pid=$!
for _ in $(seq 1 100); do [[ -f "$d/pip-started" ]] && break; sleep 0.1; done
[[ -f "$d/pip-started" ]] || bad "interrupt test setup: pip never started" "$(cat "$TMP/r7.out")"
pkill -TERM -P "$pid" 2>/dev/null || true
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
[[ ! -d "$d/.venv" ]] && ok "terminated mid-build leaves no .venv behind" \
  || bad "terminated mid-build leaves no .venv behind" "$(ls -A "$d/.venv")"

echo "Results: $pass passed"
