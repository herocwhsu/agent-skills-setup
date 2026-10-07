#!/usr/bin/env bash
# usage: hidden_accept.sh <repo> ; CMD inside repo resolved below
repo="$1"; cd "$repo" || exit 1
if [ -d wordstat ]; then CMD=(python3 -m wordstat); else CMD=(python3 wordstat.py); fi
t=$(mktemp -d); pass=0; fail=0
printf 'The cat and the dog. The END, the end!\nA cat; a Dog.\n' > "$t/in.txt"
printf 'the\na\n' > "$t/stop.txt"
check() { local name="$1" want="$2"; shift 2; local got; got=$("$@" 2>&1); if printf '%s' "$got" | grep -qE -- "$want"; then pass=$((pass+1)); echo "PASS $name"; else fail=$((fail+1)); echo "FAIL $name :: $(printf '%s' "$got" | tr '\n' '|' | cut -c1-120)"; fi; }
check F1-count '(^|[^0-9])13([^0-9]|$)' "${CMD[@]}" "$t/in.txt"
check F2-top 'the[^a-z0-9]+4' "${CMD[@]}" "$t/in.txt" --top 1
check F2-tie 'a[^a-z0-9]+2.*cat[^a-z0-9]+2' sh -c "$(printf '%q ' "${CMD[@]}") $t/in.txt --top 3 | tr '\n' ' '"
check F3-stop '(^|[^0-9])7([^0-9]|$)' "${CMD[@]}" "$t/in.txt" --stop "$t/stop.txt"
check F4-json '"?13' sh -c "$(printf '%q ' "${CMD[@]}") $t/in.txt --json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(json.dumps(d))'"
check F5-stdin '(^|[^0-9])13([^0-9]|$)' sh -c "$(printf '%q ' "${CMD[@]}") - < $t/in.txt"
check F6-minlen '(^|[^0-9])11([^0-9]|$)' "${CMD[@]}" "$t/in.txt" --min-len 3
check F6-combo '(^|[^0-9])7([^0-9]|$)' "${CMD[@]}" "$t/in.txt" --min-len 3 --stop "$t/stop.txt"
echo "RESULT $repo pass=$pass fail=$fail"; rm -rf "$t"
