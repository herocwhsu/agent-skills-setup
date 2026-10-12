# Run telemetry: metric reliability

Produced by `scripts/run_telemetry.py`, compared by `scripts/run_report.py`. Records live in `docs/telemetry/runs/<run_id>.json`. Checked against 22 session files and 47 subagent transcripts (including 4 nested under `subagents/workflows/`) on 2026-10-12. Spec: `docs/stories/run-telemetry/spec.md`.

| Metric | Status | Source and caveat |
|---|---|---|
| Output tokens, parent | measured | Session `message.usage`, deduplicated by message id. Naive summing overcounted output by 36% in the session where this was built (37,536 against 27,510 on 2026-10-12); the repeated rows were identical. |
| Output tokens, subagent | measured | `subagents/agent-*.jsonl`. Hand count matched the collector exactly on 4 transcripts. |
| Input tokens, summed | measured, not usage | Re-sent context is summed on every turn. Stored but labeled; do not read it as billed or unique. |
| Last and max context size | measured | Final-turn and largest per-turn input: context size, not usage. Rows from the `<synthetic>` model (all-zero usage, written on errors and interrupts) are ignored and counted in `synthetic_rows_ignored`; before this was fixed, 4 sessions reported a context size of 0. |
| `reported_context_total` | measured, a harness figure | Final-turn input plus output. This is the figure the harness reports for a subagent. Not billed usage. |
| Cache read / creation tokens | measured, ambiguous | Every measured cache sum in the 24 records is 0. The record says it cannot tell "no caching" from "not reported". |
| Wall time | measured | First to last timestamp. Includes idle time: one run spans 26 hours. |
| Active turn time | measured where present | Sum of `turn_duration` records. Missing in 13 of 22 sessions. |
| Agent time | measured | Sum of subagent spans. Can exceed wall time because subagents run in parallel. |
| Subagent count, type, description, tool-use id | measured | `meta.json` plus the parent's spawn calls. 5 of 47 transcripts had no parent spawn call (started by a skill or workflow) and are flagged as `spawned_by_parent_call: false`, not dropped. |
| Subagent model | measured | From assistant messages. |
| Subagent outcome | missing | No structured record. Notification text is deliberately not parsed. |
| Context compactions, API errors | measured | Structured records only. My first grep for them matched my own commands, which is why text is not counted. |
| Retries, timeouts (agent-level) | missing | No structured record in session files. |
| Outside-agent attempts | measured from commit `7b79512` | Earlier runs logged successes only, so they are undercounted (the log's earliest rows predate that commit). Each record states how many legacy rows it saw. |
| Gate results | measured when a `--report` file is given, else missing | `harness-verify.sh --report <path>`. No run in the baseline has one. |
| Cost (USD) | missing | No authoritative source. Not estimated from public pricing. |
| Human corrections, rework | missing | No reliable automatic source. |
| Codex, Kiro, agy token usage | missing | All 152 `token_count` events in the local Codex session files have `info: null`. No usable source found for Kiro or agy. |

## Handling rules that came out of review

- A window is half-open: a row at exactly the end timestamp belongs to the next window, so adjacent windows do not both count it.
- If a window includes only part of the rows for one message id, the id is listed in `partial_message_ids` instead of being reported as a clean total.
- Booleans are not token counts; NaN or infinite durations are ignored.
- Free text written to the record (subagent description, agent type) is length-bounded. A label that contains a path shape (absolute path, `~/`, a Windows or UNC path, a unicode slash), a credential shape (`sk-`, `ghp_`, `AKIA`, `xox*-`, a JWT) or a key/password word followed by a value is replaced whole with a redaction marker. This is a shape filter, not a guarantee: a secret in an unusual form could pass, so read the records before publishing them outside the repo.
- Subagent ids come from file names. A plain alphanumeric id is kept; anything else is replaced by a short hash, and two transcripts with the same name in different folders get distinct ids. The session id is shortened to 8 hex characters, or `session` if it is not a UUID. A tool-use id is kept only if it matches `toolu_...`.
- Rows without a timestamp are counted when no window is given, and dropped (and counted in `rows_without_timestamp_excluded`) when a window is given. None exist in the baseline.

## Known ambiguities, not resolved

- The 46,096 figure the harness reports for one subagent is context size plus output. Summing every message's input gives about 307,000. Neither is billed usage, so both are labeled and neither is called cost.
- A conflicting duplicate row (same message id, different numbers) is handled by keeping the higher output row and recording both. It has never occurred in the 22 sessions, so that path is covered only by a synthetic test.
- Time inside a commit window is cut by timestamp. A commit made while a subagent was running attributes that subagent to the window it started in only if the transcript's records fall inside it.
