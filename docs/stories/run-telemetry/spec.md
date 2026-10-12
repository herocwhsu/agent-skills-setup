# Run telemetry: spec

Intake: `~/Project/docs/2026-10-12-harness-improve-prompt.txt` plus the two review notes of 2026-10-12. Goal: tell whether a harness change made the next task of the same difficulty faster, cheaper or more reliable.

## Spec-workflow gates

| Gate | Result |
|---|---|
| 1 Intake | The prompt file above. No Jira or Confluence. |
| 2 Audit | Done by reading the code and session files; findings below. |
| 3 Repo scan | Done: `trace_evaluation.py`, `outside_agent.py`, `harness_benchmark.py`, session files in `~/.claude/projects`. |
| 4 External dependency | Not applicable. The session file format is Claude Code's, read-only, and parsed defensively. |
| 5 Test plan | Section "Tests". |
| 6 Jira | Not applicable. |
| 7 Release | Not applicable. Verified by `harness-verify.sh`. |

## Decisions (made without a human, with the reason)

1. **Tokens only; USD is `missing`.** The field exists, status `missing`, reason `no authoritative source; custom ANTHROPIC_BASE_URL`. No price table in the MVP.
2. **Dedup key is `(scope, message_id)`.** `scope` is the session id for the parent and the `agentId` for a subagent. Verified: 138 repeated ids in this session, all with identical numbers. If two rows for one key differ, the collector keeps the higher `output_tokens` row, sets `conflict: true`, and lists both raw rows. It never picks silently.
3. **Parent and subagent usage are separate scopes and never merged.** The collector reads only structured `usage` records. It does not parse the `subagent_tokens` text in task notifications, which would double-count.
4. **Token fields are raw and labeled.** Per scope: `input_tokens_sum`, `output_tokens_sum`, `cache_read_sum`, `cache_creation_sum`, `last_context_tokens` (input at the final turn), `max_context_tokens` (largest per-turn input). `last_input_tokens + output_tokens_sum` reproduces the harness's reported subagent figure (46,096 checked) and is stored as `reported_context_total` only when output tokens are known (otherwise missing), never as billed usage.
5. **`missing` is never zero.** A metric is `{value, source, status}` with status `measured`, `estimated` or `missing`. A cache field absent from every row is `missing`; a field present with value 0 is a measured 0.
6. **Wall time and agent time are separate fields.** Wall time is first to last timestamp of the parent. `agent_time_ms` sums subagent durations. Parallel subagents make `agent_time_ms` larger than wall time, and both are reported.
7. **Subagent record fields:** `agent_id`, `parent_session_id`, `tool_use_id`, `agent_type`, `description`, `duration_ms`, `tokens`, `message_count`. `model`: taken from the assistant message `model` when present, otherwise `missing`. `outcome`: `missing` unless a structured source is found (the task-notification `status` is text in the parent, so not used).
8. **Retries, timeouts, context compactions:** counted only from structured records. If no such record type exists, the metric is `missing`, not 0. Text matches are not counted (an earlier grep matched my own commands).
9. **Human corrections and rework:** `missing` in the MVP. No reliable automatic source.
10. **Outside-agent attempts:** `cmd_run` logs every attempt (class, duration, exit) in addition to the existing success record. Observability only; return codes and order are unchanged and a test asserts that.
11. **Storage:** one JSON per run at `docs/telemetry/runs/<run_id>.json` (outside the auto-loaded state layer). `run_id` is the session id plus the commit range. `feature_list.json` gets only `execution_summary: {run_id, output_tokens, wall_time_ms, active_turn_time_ms, subagents, subagent_output_tokens}`. Measures are raw figures; a null value means missing. The first draft named `total_tokens_reported`, dropped because it would mix context size with usage.
12. **Window of a run:** a run is the portion of a session between two commits (by timestamp). If a session spans several features, each feature's run covers its commit window. A window with no usage rows yields all metrics `missing`.
13. **`classify` is not widened.** `429` and `rate limit exceeded` stay `error`, because a `rate_limit` result benches an agent for 5 hours to a month and one transient 429 should not do that.

## Metric reliability (target, confirmed against real files after implementation)

| Metric | Expected status | Source |
|---|---|---|
| Input / output / cache tokens, parent | measured | session `message.usage`, deduplicated |
| Same, per subagent | measured | `subagents/agent-*.jsonl` |
| Subagent count, type, description, tool_use_id | measured | `subagents/*.meta.json` |
| Subagent duration | measured | first to last record timestamp in its transcript |
| Wall time | measured | parent timestamps |
| Gate results | measured when a `harness-verify --report` file exists, else missing | report JSON |
| Outside-agent attempts | measured from the commit that adds attempt logging; earlier runs missing | `outside-agent-runs.jsonl` |
| Cost (USD) | missing | none |
| Retries, timeouts, compactions | missing unless structured records exist | to be verified |
| Human correction, rework | missing | none |
| Codex / Kiro / agy token usage | missing | codex `token_count` events seen with `info: null`; no usable source found |

## Tests (written before the code)

Parsing a real-shaped fixture; dedup of identical repeated rows; conflicting duplicate rows (flag plus both raw rows kept); missing vs zero for absent cache fields; incomplete session (no final assistant message); subagent attribution without adding subagent tokens to the parent; wall vs agent time with overlapping subagents; a commit window with no usage rows; malformed lines skipped; outside-agent attempt logging for success, rate limit, auth, timeout, empty output and precheck skip, with an assertion that exit codes and candidate order are unchanged.

## Out of scope

Changing gates, delegation policy or execution behavior; USD estimates; non-Claude token usage; the fixed benchmark (Phase 4, defined separately).
