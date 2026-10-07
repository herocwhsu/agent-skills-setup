# Readiness report: fresh clone of agent-skills-setup (/tmp/l6/ready-claude)

HOME was set to /tmp/l6/home-a before every command. Nothing was committed or pushed. No install/setup scripts were run.

## Steps

1. `ls -la; git log; wc -l` on the root docs. Found AGENTS.md, README.md, PROGRESS.md, feature_list.json, init.sh, .python-version, requirements-dev.txt. There is no CLAUDE.md, so AGENTS.md is the entrypoint.
2. Read AGENTS.md lines 1-40, init.sh, scripts/harness-verify.sh, .python-version (3.14.7), requirements-dev.txt and pyproject.toml. The Startup Workflow says: read AGENTS.md, then feature_list.json, then PROGRESS.md, then run `./init.sh`.
3. Grepped README, AGENTS.md and docs/*.md for venv, pip and pytest setup, and read the head of scripts/run-tests.sh. The only place that gives the venv build command is the error string in run-tests.sh, lines 23 and 30.
4. Read the README Requirements and Quick Start sections, and checked the local interpreters. `python3` resolves to 3.14.7, which matches the pin.
5. `./init.sh` on the bare clone took 5m00s. Result: FAIL types (mypy cannot find `anthropic`) and SKIP runtime drift (runtime not installed under HOME). The other 8 gates were OK, including tests, which fell back to ambient python3. **This was the first passing test run (tool call 5).**
6. `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt` took 1m18s and succeeded. The venv runs Python 3.14.7.
7. `bash scripts/run-tests.sh --fast` took 4m18s. Result: **62 passed, 0 failed, 0 skipped**, and 0 code-bearing subcommands without tests.
8. Ran `bash .claude/hooks/types-guard.sh`, which now exits 0. Also read the PROGRESS.md headings and Current State, and summarized feature_list.json: 36 features, all `done`.
9. Read the PROGRESS.md sections In Progress, Next, Blockers and Notes for Next Session, plus runtime-drift-guard.sh.
10. `./init.sh` with the venv took 4m30s. Result: 9 gates OK and 1 SKIP (runtime drift). The script prints "Passed, but SKIPPED: runtime drift". `git status` is clean, because .venv is gitignored.
11. Wrote this report.

## Problems

1. **Slowdown (would be a blocker for anyone without ambient packages): no dev-setup instructions.** Neither AGENTS.md "Startup Workflow" (lines 15-23) nor README "Requirements" and "Quick Start" (lines 20-48) says to create `.venv` from `requirements-dev.txt`. As a result, the first `./init.sh` fails the types gate.
   - AGENTS.md line 74 mentions `.venv/bin/mypy` only in passing.
   - The command itself appears only inside a run-tests.sh error message (lines 23 and 30), and that message prints only when a broken .venv already exists.
   - I had to guess the venv recipe from that error string. The fix is a step 0 at AGENTS.md:22: `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`.
2. **Slowdown: PROGRESS.md contradicts a fresh clone.** PROGRESS.md:6 says "`./init.sh` passes all 9 gates", but on a fresh clone it fails types. The statement is only true with a .venv or ambient packages, and PROGRESS.md:6 should say so.
3. **Slowdown: the runtime drift gate cannot pass in development without running install.sh.** That gate skips when `~/.agent-skills-setup` is missing, and you only get that directory from running `scripts/install.sh`. AGENTS.md:52-54 calls install.sh "routine here", but I was not allowed to run it in this sandbox.
   - PROGRESS.md:158 also warns that the drift gate flags `lib.sh` until install.sh runs from main.
   - Nothing in AGENTS.md "Definition of Done" (lines 35-41) says whether a SKIP counts as done. The harness-verify.sh output says those gates "checked nothing".
4. **Slowdown: the gates are slow and nothing warns you.** init.sh takes about 4.5-5 min and run-tests.sh --fast about 4.3 min. AGENTS.md "Verify" (lines 25-30) gives no time estimate.
   - PROGRESS.md "What's Next" mentions "~3 minutes" only for the Stop gate.
   - A newcomer could easily think the command has hung. I also had to raise tool timeouts to stay safe.
5. **Cosmetic: README Quick Start (lines 32-48) is for end users.** It tells you to run `install.sh`, `setup-credentials.sh` and `setup-host.sh`, which write global agent config. There is no separate "Contributing / Development" section, so a contributor has to work out that these are install steps, not dev steps. I did not run them, as the sandbox rules require.
6. **Cosmetic: the next task is ambiguous.** PROGRESS.md:7-8 names Lecture 6 as next. The "What's Next" list (lines 164-172) has five items with Lecture 6 last and no priority order, so the docs do not settle which comes first.
7. **Cosmetic: the types gate is masked by fallback.** On a bare clone the tests gate passed through the ambient python3 fallback (run-tests.sh:18) while the types gate failed. The result depends on what the host's ambient interpreter happens to have installed, which docs/architecture.md:118 says should not happen ("silent fallback ... prohibited"). The code allows the fallback when no `.venv` exists.

## Answers from repo files alone

- **How to run / install for dev:** there is no app to run. The repo is a skills/hooks installer, and end-user install is `bash scripts/install.sh` (README.md:32-38, not run here). The dev environment is `.venv` built from `requirements-dev.txt` on Python 3.14.7. Sources: `.python-version`; the run-tests.sh:23 error text; docs/architecture.md:118.
- **How to test:** `bash scripts/run-tests.sh --fast` (AGENTS.md:29) runs the tests only. The full gate set is `./init.sh` or `bash scripts/harness-verify.sh` (AGENTS.md:22, 28). Result here: 62 passed, 0 failed.
- **Current state:** no active feature. All 36 features in feature_list.json are `done`, and the last one is feat-036, the repo-wide cleanup (PROGRESS.md:5-6, 158-162). One known blocker: the `_lib.sh` pip step fails under Homebrew PEP 668 (PROGRESS.md:175-180).
- **Next task:** Lecture 6, "Why Initialization Needs Its Own Phase" (PROGRESS.md:7, 172). Other open items:
  - Re-run the codex-kiro/agy smoke test against the feat-033 fixes.
  - Scope the Stop-gate tests to changed files (optional).
  - Re-run the fresh-session test on hangar/atelier.
  - Exercise 3 at ~10k tokens (optional).

  Source: PROGRESS.md:164-172.

## Tool-call accounting

- Total tool calls: 11, counting this report write.
- First passing test: tool call 5. That was `./init.sh` on the bare clone, where the tests gate was OK through the ambient-python fallback.
- First fully green test suite under the documented venv: tool call 7 (62 passed).
