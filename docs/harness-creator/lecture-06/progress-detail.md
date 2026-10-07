# Lecture 6 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-06. Raw reports are in [raw/](./raw/).

All runs used throwaway clones in `/tmp/l6`, with `HOME` redirected to `/tmp/l6/home-*`.
The repo itself was not modified during the runs.

## Step 0 — baseline

- `./init.sh` on the real repo: all 10 gates OK, 5m56s.
- `bash scripts/run-tests.sh --fast`: 62 passed, 300 s.
- `feature_list.json`: 36 features at the time (37 after feat-037), all `done`. Fields are `id, name, description, status, evidence`,
  with no acceptance criteria.

## Step 1 — readiness cold start (Exercise 1)

Two clones of `main` at `b95c5dd`: `ready-claude` and `ready-agy`.

- Claude subagent (general-purpose). Prompt: reach dev setup, passing tests, and current
  state and next task from repo files only. It may not run `install.sh`, `install-agents-md.sh`,
  `init-repo.sh` or `setup-*.sh`, and it reports every place it got stuck, with severity and
  the doc that should have said it. Result: [raw/readiness-claude.md](./raw/readiness-claude.md).
- agy, headless: `agy --dangerously-skip-permissions -p ...` with the same prompt, wrapped in a
  `perl -e 'alarm 1200'` timeout. macOS has no `timeout`; the first attempt failed with rc 127.
  `.agents/hooks.json` was deleted in that clone beforehand, because the repo's agy Stop hook
  (900 s) hangs headless runs (seen in the feat-035 work). Result: [raw/readiness-agy.md](./raw/readiness-agy.md).

Timeline (Claude): `./init.sh` on the bare clone took 5m00s and failed types. Building the venv
took 1m18s. `run-tests.sh --fast` took 4m18s with 62 passed. `./init.sh` then took 4m30s:
9 OK, 1 SKIP (runtime drift).

## Step 2 — acceptance checklist (Exercise 3)

The lecture's 5 items were checked by hand against the repo and the two cold-start reports
(table in summary.md). The venv step is mentioned in `AGENTS.md:74` only in passing
(`.venv/bin/mypy`). Repo-wide grep: the creation command exists only in the error strings in
`run-tests.sh` and `types-guard.sh`.

## Step 3 — template check

```
mkdir /tmp/l6/scaffold && git init
HOME=/tmp/l6/home-c bash scripts/init-repo.sh python-api /tmp/l6/scaffold
```

It wrote 10 files in `.claude/hooks/` and a `.claude/settings.json` containing only
`permissions.deny`. The script's own output says to wire hooks by hand. No state files, no
router, no test.

## Step 4 — comparison (Exercise 2, reduced)

Spec given to every session: `wordstat`, a stdlib Python CLI. F1 is the total count, F2 is
`--top N` with alphabetical tie-break, F3 is `--stop FILE`, F4 is `--json`, and F5 reads stdin
on `-`. The hard budget was 20 tool calls per session. Every session was a fresh subagent with
no shared context.

- A1: "set up and implement as many features as you can". Commit `01ce96d`.
  [raw/cmp-a-s1.md](./raw/cmp-a-s1.md)
- B1: "initialization only, no features". Output: skeleton, `AGENTS.md`, `feature_list.json`
  with criteria, `PROGRESS.md`, 2 tests. Commit `11d9dab`. [raw/cmp-b-s1.md](./raw/cmp-b-s1.md)
- A2: add F6 `--min-len N` and F7 packaging, and keep the existing features working.
  [raw/cmp-a-s2.md](./raw/cmp-a-s2.md)
- B2: implement the pending features plus F6. [raw/cmp-b-s2.md](./raw/cmp-b-s2.md)

The S2 tasks differ: A2 got packaging because A1 skipped it, and B2 got F1–F5 because B1 built
none of them. Each S2 session was asked to bring its repo to the same F1–F6 end state.

Grading: [raw/hidden_accept.sh](./raw/hidden_accept.sh), written after S1 and unseen by every
session. It runs 8 checks on one fixed input (13 words; 7 after the stopwords `the`/`a`; 11
with `--min-len 3`; 7 with both). The first draft had wrong F6 expected values (9 and 5).
They were corrected by counting the fixture before any repo was graded.

| Check | A | B |
|---|---|---|
| F1 count, F2 top, F2 tie, F3 stop, F4 json, F5 stdin, F6 min-len, F6 combo | 8/8 | 8/8 |
| Own test suite | 14 passed | 21 passed |

## Side finding — confluence-tree flake

While the Claude cold-start subagent ran, a Stop hook in the parent session reported a
`test_tree_upload.sh` failure: `BadStatusLine: SSH-2.0-OpenSSH_9.6p1`. The subagent's reading:
test 5 (line 355) picks `PORT5=$((49000 + RANDOM % 1000))` without checking it is free. That
range sits inside macOS's dynamic range, where rapportd (`*:49215`), wsagent and limactl
listen. Tests 1, 3 and 4 use unchecked ports in 45000–47999. Proposed fix: bind the mock server
to port 0 and read the bound port from its log. Not reproduced or applied at the time.
Checked on 2026-10-07: `limactl` and `wsagent` listen on 49906 and 49706, and a Python
`HTTPServer` bind on either fails with `Address already in use`. Fixed with a kernel-assigned
port (see summary "Follow-up fixes").

## Not done

- During the training run no fixes were applied; they came on 2026-10-07 (summary "Follow-up fixes").
- Still open: unordered "What's Next" and no acceptance-criteria field in `feature_list.json`.
