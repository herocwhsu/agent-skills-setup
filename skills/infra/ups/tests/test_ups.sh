#!/usr/bin/env bash
# UPS skill tests — run as: bash tests/test_ups.sh
set -euo pipefail
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; ((PASS++)); }
fail(){ echo "FAIL: $1"; ((FAIL++)); }

# placeholder — real tests added in Task 5
echo "No tests yet"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
