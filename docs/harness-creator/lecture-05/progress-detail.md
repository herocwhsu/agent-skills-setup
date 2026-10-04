# Lecture 5 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Date: 2026-10-04.

## Step 1 — baseline from the lecture's own material

- `session-simulator.ts` (bun): scripted toy. No handoff: Session B redoes 3 steps, 590 ms
  total. With handoff: 0 repeats, 400 ms. Hard-coded steps, so it measures nothing about our repos.
- `continuity-checklist.md` applied to agent-skills-setup: startup path documented (yes),
  unfinished work identified (yes, after the garbled header), next task visible (partly),
  recent work identifiable in 5 minutes (probably not: 370-line `PROGRESS.md`).
- Gap check: no `DECISIONS.md`; decisions sat in a "Decisions Made" section; `PROGRESS.md`
  "Current State" had five stacked `Active Feature` lines.

## Step 2 — cold-start rebuild, three subagents

Read-only, no memory, no `init.sh`, no memory directory. Same seven questions per repo.

| Repo | Calls | Files read | Wrong or missing |
|---|---|---|---|
| agent-skills-setup | 9 | PROGRESS (partial), feature_list, git | HEAD `83748b3` unrecorded; auto-merge decision thin (feat-020 line) |
| hangar | 4 | AGENTS, PROGRESS, init.sh | "Next" empty; no auto-merge decision found |
| atelier | 4 | AGENTS, PROGRESS, feature_list, init.sh | harness reported unmerged (stale); decision only inferable from `renovate.json` |

Claims verified against the files by grep before acting. One subagent also hit a Stop-hook test
failure (`confluence-tree/tests/test_push.sh` test 5, `ConnectionResetError` in `push.py`);
six serial reruns passed, so it was a load-related flake, not investigated further.

## Step 3 — fixes

Commits: atelier `5cf3595`, hangar `218a7ff`, agent-skills-setup `25eed39`, all local until the
user pushes. `./init.sh` passed in all three before committing. Second pass (uncommitted at the
time of writing): `PROGRESS.md` split into current state + `docs/progress-archive.md`
(370 → 248 lines), hangar `docs/architecture.md` Grafana sign-in line corrected.

## agy runs

Four modes, in order:
1. Read-only prompt in the real repos, no permission flag: no output ("command permission
   auto-denied" in headless mode), same with `--sandbox`.
2. State files pasted into the prompt, no tools, at the pre-fix and post-fix commits of atelier
   and agent-skills-setup. Pre-fix: flagged the stale harness, the unrecorded HEAD and the
   stacked lines. Post-fix: all consistent.
3. `--dangerously-skip-permissions` with a read-only prompt, run from each real repo with
   `env -u SSH_CONNECTION`. HEAD and dirty-file count were identical before and after in all
   three repos. agy reported `AGENTS.md` already in context before any file read, used 7 calls
   each, and found the new Standing decisions. It surfaced the stale hangar SSO line
   (`docs/architecture.md:410`) and the frozen `PROGRESS.md` sections.

agy errors: a wrong inference that `83748b3` reversed `feat-019` (it reads Claude Code's keychain
entry, `feat-019` removed Gemini keychain reading); file links pointing at the wrong repo
when run from another directory; 5/5 confidence on everything.

## Not done

Rebuild time in seconds; exercise 2 template; exercise 3; a staleness guard; the rest of the
`PROGRESS.md` "What's Done" trim.
