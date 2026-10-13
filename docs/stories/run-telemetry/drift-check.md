# Item 13: drift check, design note (research only, nothing changed in the repo)

## 1. What already covers part of it
- `commit-evidence.sh` (Stop, `harness/guards/commit-evidence.sh:72-85`): once per new commit range it blocks with `git log` and `git show --stat`. Catches unverified commit claims. Does not check the commit against the request. `harness/guards/tests/test_commit_evidence.sh:51-83` pins "blocks once, never twice".
- Stop/SubagentStop guards in `.claude/settings.json` (types, tests, bash-compat, secrets, state layer, runtime drift): code and state defects only. `state_layer_check.py:104-135` enforces per-feature `exclusions`, but 0 of 7 features set one.
- `stop-verify.sh:27`: runs harness-verify for AGY and Codex. Same limits.
- Skills `requesting-code-review` (reviewer gets plan and SHAs, never the session history) and `subagent-driven-development` (spec-compliance review per task): the only spec-vs-work checks, and prose the agent can skip.
- `agents/engineering-rules.md` "Outside agents": one branch-level review at the end, none for docs and state files. The only direction-drift backstop today.

## 2. Signals without a model (measured on this session, 5,110 rows)
- Hook blocks: 21 Stop-hook feedback rows (17 commit-evidence, 2 bash-compat, 1 tests, 1 state-layer). Easy to find.
- Reply to a commit-evidence block: 5 of 17 followed by a tool call, 12 of 17 by text only. Text-only often reported a check already done, so "answered without a command" would flag about 70% and is too noisy.
- Corrections: of 66 user messages, 19 are hook feedback and 47 human; 9 of the human ones match a correction-like pattern (19%). The pattern cannot tell a correction from a question ("why ..."). Not reliable.
- Scope: nothing records which files a task may touch, so "file outside the feature" has no ground truth. This session's 24 commits touched 1 to 33 files; `run_telemetry.py` (8 commits), its tests (7) and `PROGRESS.md`, `feature_list.json`, `RELIABILITY.md` (6 each) recur.
- Cheap and derivable: commits and files per window, hook blocks, tool calls after a block, reviewers spawned (`meta.json`), outside-agent attempts and independence.

## 3. Cost (41 reviewer subagents in `docs/telemetry/runs/*.json`)
- Output tokens: median 1,003 (398 to 2,886). Wall time: median 186 s (40 to 1,034 s). Final context about 45,500 input tokens (size, not billed cost).
- Subagents were 24% and 48% of output in this session's two windows (5 reviewers each). One extra reviewer is about +1,000 output tokens and +3 min. A pair agent every 10 minutes over 4 hours is about 24 runs, 24k output tokens, more than the second window's whole parent output (7,099).

## 4. Options
(a) Deterministic scope check. Needs a declared `scope_files` list per feature and a Stop-time diff check. Near-zero cost. Catches edits outside the list. Misses wrong approach and ignored errors. False alarms: legitimate follow-up files.
(b) (a) plus one fresh reviewer at the end of a feature, given the request text and the diff: "does this do what was asked, what was left out". About +1,000 tokens, +3 min per feature. Catches direction drift once, while it is cheap to fix. Needs a skill or a `session-clean.sh` step that keeps the request text; no new hook.
(c) Periodic pair agent (shared spec file, fresh context). Catches execution drift early. Cost grows with time (above). High false-alarm risk, since the pair sees partial context.

## Recommendation: (b), staged
1. Measure only: add a `process_adherence` block to the run record (below). No new gate.
2. Add (a) when at least 10 features carry `scope_files`.
3. Add the end-of-feature reviewer only if step 1 shows drift events that existing gates did not catch.
Change course if: fewer than about 1 uncaught drift event per 10 features (stop at step 1), or corrections cluster mid-feature (then (c) with a 30+ minute period).

## Tests first, reviewers
Fixture transcripts: block then command, block then text, no block, unreadable file; scope list empty, file inside, file outside. A Stop hook or gate change needs a fresh subagent plus an outside agent (try codex-kiro and agy). Step 1 is a script, so a subagent suffices.

## 5. Metrics (`{value, source, status}`)
`hook_blocks` and `tool_calls_after_block` measured; `reviewers_spawned`, `reviewer_families`, `files_per_commit` measured; `scope_violations` missing until `scope_files` exists; `user_corrections` missing (no reliable signal); `uncaught_drift_events` estimated, hand-labelled from review findings. Success: fewer review findings of type "did not do what was asked" and fewer messages restating a request, at equal or lower output tokens per feature.
