---
subcommand: skill-eval
group: utils
slash: /utils-skill-eval <skill-name> <transcript-file>
output: ./eval/<skill-name>/<date>.md
---

# utils/skill-eval — Skill Regression Check

Checks whether a skill run behaved correctly by mechanically scanning the
transcript for status markers and tool-call counts, instead of a human
re-reading the whole exchange. Reduces the human review surface to only the
part that actually requires judgment: is the *content* the skill produced
any good.

## Why this exists

Most skill-quality questions ("did it check the cache first", "did it skip
the redundant archaeology", "did it spot-check a stale note") are binary and
already visible in tool call order/count — a human doesn't need to read
transcript prose to answer them. Only content-quality questions ("is this
new note specific enough to be useful") need actual human judgment.

This skill automates the first category and produces a short report that
narrows the second category down to a couple of lines to read.

## Prerequisites

- Skills being evaluated emit machine-checkable status markers
  (`<SKILL>_STATUS: <STATE>` — see `repo/domain-notes/IMPL.md` for the
  pattern: `DOMAIN_NOTES_STATUS: HIT|MISS|SPOT_CHECK_DONE|SPOT_CHECK_SKIPPED|APPENDED`).
  If a skill doesn't emit status lines yet, add them before evaluating it —
  don't try to eval status-less skills by prose reading.
- A transcript to scan: a saved copy of the session, or the output of
  `session_search` for the run being evaluated.

## Workflow

### Step 1 — Get the transcript

If evaluating a run from the current session, save the relevant tool outputs
to a file. If evaluating a past run, use `session_search` to pull it:

```
session_search(query="<skill trigger keyword>", limit=1)
```

Save the message window to a plain text file, e.g. `/tmp/eval-transcript.txt`.

### Step 2 — Run the check script

```bash
python3 ~/.kiro/skills/utils/skill-eval/lib/check_transcript.py <skill-name-prefix> /tmp/eval-transcript.txt
```

(or the `~/.claude/skills/...` path — both resolve to the same file via the
symlink into `agent-skills-setup`.)

Where `<skill-name-prefix>` is the marker prefix, e.g. `DOMAIN_NOTES` for
`repo/domain-notes`. The script (`lib/check_transcript.py`) does three
mechanical things:

1. Extracts every `<PREFIX>_STATUS: <STATE>` line in order
2. Counts tool calls between the first and last marker (proxy for "how much
   work did this take" — a HIT with a high tool-call count is suspicious,
   it means the skill found the cache but didn't actually use it)
3. Flags anomalies: a MISS immediately followed by zero fallback tool calls
   (means the skill dead-ended instead of falling back), a HIT followed by
   many tool calls anyway (cache found but ignored), an APPENDED with no
   preceding investigation (means the note might be fabricated instead of
   observed)

Output is a short table, not prose — pipe it straight into the report.

### Step 3 — Human judgment (the only manual part)

Read the script's output. It will point at specific line ranges to look at
— usually just the new domain-notes entry text (a few lines) or the final
answer given to the user. Judge only:

- Is a new note specific (names functions/files/rules) or vague?
- Did a stale-note spot-check correctly catch that the note was wrong, if
  the case was designed to be stale?
- Is the final answer to the user actually correct (spot check against the
  ground truth for the test case)?

This should take under a minute per case — the mechanical checks already
ruled out the "didn't even try" and "ignored the cache" failure modes.

### Step 4 — Write the report

```
./eval/<skill-name>/<YYYY-MM-DD>.md
```

Use the template in **Report format** below. Keep it short — a table of
cases with pass/fail plus one line of human judgment per case, and one
closing sentence: better / worse / no change vs the last eval, or n/a if
this is the first eval.

## Report format

```markdown
# Eval: <skill-name> — <YYYY-MM-DD>

| Case | Mechanical check | Human judgment |
|---|---|---|
| <case 1 name> | <PASS/FAIL from script, e.g. "HIT, 1 tool call"> | <one line> |
| <case 2 name> | ... | ... |

## Conclusion
<Better / worse / no change vs previous eval, and why, in 1-2 sentences.>
```

## When to run this

- After editing a skill's IMPL.md or SKILL.md — before considering the edit
  done, not after it's already been used for real several times
- When a skill "feels" like it's misbehaving but you can't pin down why —
  run it against 2-3 real cases and read the mechanical breakdown
- NOT for every single skill invocation — this is a point-in-time regression
  check when something changed, not continuous monitoring. Continuous
  tracing/monitoring of production LLM calls is a different concern, covered
  by the `llm-observability` skill.

## Common mistakes

| Mistake | Fix |
|---|---|
| Evaluating a skill with no status markers by re-reading prose | Add status markers to the skill first (see Prerequisites) — don't eval blind |
| Treating this as continuous monitoring | It's a point-in-time regression check after an edit, not a dashboard. Use `llm-observability` for continuous tracing of production LLM call sites |
| Grading with another LLM call | Don't — the whole point is these skills produce human-readable artifacts (markdown reports) meant for human review anyway. Adding an LLM grader is another thing that can be wrong |
| Running against synthetic/invented test cases only | Prefer real past stories/investigations as test cases — they're free (already happened) and the "baseline" cost is already known from memory/session_search |
