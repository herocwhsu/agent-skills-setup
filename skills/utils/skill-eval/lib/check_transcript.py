#!/usr/bin/env python3
"""
check_transcript.py — mechanical eval pass over a skill transcript.

Scans a plain-text transcript for "<PREFIX>_STATUS: <STATE>" marker lines
and flags anomalies, so a human doesn't have to re-read the whole exchange
to answer binary questions (did it check the cache, did it fall back, did
it ignore a hit it found).

Usage:
    python3 check_transcript.py <MARKER_PREFIX> <transcript_file>

Example:
    python3 check_transcript.py DOMAIN_NOTES /tmp/eval-transcript.txt

This is a heuristic tool, not a certified test runner — it counts lines
that look like tool-call boundaries (a crude proxy), and it can't read the
transcript's actual meaning. Always follow up with the human-judgment step
described in utils/skill-eval/IMPL.md.
"""
import re
import sys


TOOL_CALL_MARKERS = (
    "[tool:",
    "tool_call",
    "> $",       # shell prompt echoes, common in saved terminal transcripts
    "$ ",
)


def count_tool_calls(lines, start, end):
    """Crude proxy: count lines between two marker indices that look like
    tool invocations. Real transcripts vary in format, so this is a rough
    count meant to catch orders-of-magnitude differences (1 vs 10), not an
    exact count."""
    count = 0
    for line in lines[start:end]:
        low = line.lower()
        if any(m.lower() in low for m in TOOL_CALL_MARKERS):
            count += 1
    return count


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    prefix, path = sys.argv[1], sys.argv[2]
    marker_re = re.compile(rf"{re.escape(prefix)}_STATUS:\s*(\S+)")

    with open(path, encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()

    hits = []
    for i, line in enumerate(lines):
        m = marker_re.search(line)
        if m:
            hits.append((i, m.group(1)))

    if not hits:
        print(f"No {prefix}_STATUS markers found in {path}.")
        print("Either the skill under test doesn't emit status markers yet,")
        print("or this transcript doesn't cover a run of it.")
        sys.exit(0)

    print(f"{prefix}_STATUS markers found: {len(hits)}\n")
    print(f"{'line':>6}  {'state':<20}  {'calls_before':<14}  {'calls_after':<12}  flag")
    print("-" * 80)

    for pos, (idx, state) in enumerate(hits):
        prev_idx = hits[pos - 1][0] if pos > 0 else 0
        next_idx = hits[pos + 1][0] if pos + 1 < len(hits) else len(lines)

        calls_before = count_tool_calls(lines, prev_idx, idx)
        calls_after = count_tool_calls(lines, idx, next_idx)
        flag = ""

        state_upper = state.upper()
        if "MISS" in state_upper and calls_after == 0:
            flag = "\u26a0 MISS with no visible fallback investigation"
        elif "HIT" in state_upper and calls_after > 3:
            flag = "\u26a0 HIT found but many tool calls happened anyway (cache ignored?)"
        elif "APPENDED" in state_upper and calls_before == 0:
            flag = "\u26a0 APPENDED with no preceding investigation (fabricated note?)"
        elif "SPOT_CHECK_SKIPPED" in state_upper:
            flag = "note: spot-check was skipped \u2014 verify this was justified"

        print(f"{idx:>6}  {state:<20}  {calls_before:<14}  {calls_after:<12}  {flag}")

    print("\nThis is a mechanical pass only. Read the flagged lines in the")
    print("original transcript and apply human judgment per utils/skill-eval/IMPL.md Step 3.")


if __name__ == "__main__":
    main()
