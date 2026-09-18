# Harness Creator Training — Lecture 2: What a Harness Actually Is

Source lecture: https://walkinglabs.github.io/learn-harness-engineering/en/lectures/lecture-02-what-a-harness-actually-is/
Target repo: `agent-skills-setup` (this repo)
Date: 2026-09-16

## Why this exercise

Lecture 2 defines a harness as five subsystems: Instructions, Tools, Environment, State, Feedback. Two of these — **Tools** (shell/tool access, least-privilege) and **Environment** (reproducibility) — are not measured at all by `harness-creator`'s `validate-harness.mjs` scorer used in [Lecture 1](../lecture-01/summary.md) (that scorer's five subsystems are Instructions/State/Verification/Scope/Lifecycle). So this repo's 88/100 Lecture 1 score said nothing about whether it actually had these two. Checking directly found it didn't:

- **Environment**: no `.python-version`, `pyproject.toml`, lockfile, or container definition, despite depending on `python3`/`mypy`/`ruff` throughout.
- **Tools**: `.claude/settings.json` had no `permissions` block at all. The only least-privilege content was advisory prose in `AGENTS.md`'s "Boundaries (scope)" section.

## What we did — Environment

Pinned `.python-version` to `3.14.7` (newest stable, installed via pyenv, scoped to this repo's directory only — confirmed it does not leak into other repos' shell sessions).

This surfaced a real finding, not just a missing file: `mypy` had been reporting clean for a long time, but only because whichever ambient interpreter happened to be active (3.13.4) happened to have `pytest`, `anthropic`, `google-generativeai`, and `lxml` already pip-installed — with zero declaration anywhere in the repo that these were required. The pin didn't break anything; it exposed that the green checkmark was never actually reproducible. Installing the real package set under 3.14.7 fixed it for real. Full test suite: 53/53 passing after.

**Update (same training, later session): resolved.** Built a real isolated venv (`python3 -m venv .venv`, created from the already-pinned 3.14.7 interpreter — inherits the pin rather than competing with it) and installed only this repo's actual dependencies (`mypy`, `ruff`, `pytest`, `lxml`, `anthropic`, `google-generativeai`) into it — not the shared ambient pyenv environment other projects on this machine also use. Generated `requirements-dev.txt` via `.venv/bin/pip freeze` and ran `osv-scanner` against it for real: **clean, no vulnerabilities** — the CVEs found earlier (idna, soupsieve, urllib3) came specifically from the polluted ambient environment's older pins, not from a fresh install of this repo's real dependency set. `.claude/hooks/types-guard.sh` and `scripts/run-tests.sh` now prefer `.venv/bin/mypy` / `.venv/bin/python3 -m pytest` when the venv exists, falling back to bare `mypy`/`python3` otherwise — every other `python3` call site in the repo (installer scripts, credential helpers, hook templates shipped to other repos) deliberately still resolves from ambient PATH, since that code runs on other people's machines. `secret-scan.sh`'s osv-scanner step now genuinely scans and can genuinely block (exit 2) on a future CVE — an accepted, deliberate cost, not a surprise. Full detail: [progress-detail.md](./progress-detail.md#part-2b).

## What we did — Tools

Converted two of `AGENTS.md`'s four advisory "Boundaries" into an actual `permissions` block in `.claude/settings.json`:
- Deny writing/editing `AGENTS.override.md` anywhere under a user's home dir.
- (Originally also) ask before running `install.sh`/`install-agents-md.sh`.

The other two boundaries (never point `init-repo.sh` at this repo; tests must redirect `HOME`) were left as prose only — neither is expressible as a Claude Code permission rule: one is about how an *external* invocation targets this repo, the other is a testing discipline, not a tool-access boundary.

## The review that mattered: `codex-kiro` caught real gaps in the first draft

Per the lesson from Lecture 1 (same-model review isn't independent review), we asked `codex-kiro` — a different model (`gpt-5.6-sol`) — to critique the first version of the permissions block and the Python pin, not rubber-stamp it. It found two real problems, which we independently confirmed before fixing rather than trusting on say-so:

1. **`Write(//Users/*/AGENTS.override.md)` used a single `*`**, which does not cross path separators — it only matched `/Users/alice/AGENTS.override.md`, not `/Users/alice/project/AGENTS.override.md`. Confirmed with a local glob test (`ls` against a fixture tree) before fixing. **Fixed** — widened to `**`, re-verified the same fixture now matches all nesting depths.

2. **The `ask` rule on `install.sh`/`install-agents-md.sh` matched only the literal invocation `bash scripts/install.sh`.** Any other invocation form (`./scripts/install.sh`, `sh scripts/install.sh`, an absolute path) bypasses it entirely — and this repo's own host settings (`~/.claude/settings.json`) run with `defaultMode: "auto"`, so an unmatched command likely gets silently auto-approved rather than falling back to a safe default. **Fixed by removal**, not by trying to enumerate every bypass: the `ask` rules were dropped, and `AGENTS.md` now states plainly that this boundary is advisory-only and explains why a settings.json rule can't reliably enforce it for an arbitrarily-invoked shell command.

`codex-kiro` also raised a third point — that pinning `.python-version` conflicts with `mypy.ini`'s own explicit comment ("`python_version` is deliberately unset so mypy assumes the running interpreter rather than pinning semantics a contributor on another version would not have"). This is a real, legitimate tension in the repo's design, but changing it wasn't part of the scope agreed for this session — it's recorded as an open finding, not resolved, so a future session doesn't have to rediscover it.

**Update (same training, later session): resolved.** Two settings were never actually in conflict — `mypy` still infers correctly from whichever interpreter runs it, pinned or not. `mypy.ini`'s comment was updated to say so, rather than the tension being silently left alone or silently changed.

## A third model joins, and demonstrates why verification matters even more with three sources

Closing out the `.venv`/manifest work (see [progress-detail.md](./progress-detail.md) Part 2b) meant reviewing the fallback logic before calling it done. `codex-kiro` failed outright on the first attempt (5 reconnect retries, then a hard stream error) — a good reason to not lean on one review tool alone, so we brought in `agy` (a third, genuinely different model family — Gemini-based) once it became available with a logged-in subscription.

`codex-kiro`'s retry succeeded and found a real gap: the fallback pattern (`[[ -x "$MYPY" ]] || MYPY="mypy"`) only proves a binary is *executable*, not that it's the *right* one — if `.venv` were ever rebuilt at a different Python version than `.python-version` currently pins, both gates would silently use the stale venv with zero warning. **Fixed**: both `types-guard.sh` and `run-tests.sh` now compare `.venv`'s actual Python version against the pin and fail loud (not silently fall back) on any mismatch or broken binary — confirmed by actually simulating the drift and watching it block correctly, not just reading the code.

`agy` needed `--dangerously-skip-permissions` to run at all in headless mode (a read-only shell command was auto-denied with no way to prompt) — granted for this one review since the underlying command was harmless. Its review then produced two confident, specific, **and false** claims: that Python 3.14.7 "does not exist" (we'd installed and used it repeatedly all session), and that `httpx2`/`httpcore2` were "potential typosquats" (both are real PyPI packages, a legitimate transitive dependency of `anthropic`, confirmed via `pip show` and `pipdeptree`). Neither was accepted on say-so — both were checked and refuted before being dropped.

One claim did converge across both models and was worth taking seriously precisely because it wasn't accepted on their say-so either: `google-generativeai` is genuinely deprecated. Checked against PyPI's own project page directly rather than trust either model — confirmed: legacy status, "support ended permanently on November 30, 2025," successor is `google-genai`. **Not migrated this session** — it touches real shipped code (`polish_engine.py`'s Gemini backend), a different-shaped change than today's dev-tooling work, flagged clearly rather than silently expanded into or silently dropped.

## Outcome

- Environment subsystem: reproducible pin in place, real isolated venv + scanned manifest built, version-drift/silent-fallback gap closed, `mypy.ini`/`python-version` tension resolved as a documentation staleness issue (not a real conflict).
- Tools subsystem: one boundary now mechanically enforced (deny), one downgraded from a broken/misleading enforcement attempt to honest advisory-only documentation.
- Every fix independently reviewed by at least one genuinely different model before being finalized, and every review claim was verified mechanically (glob fixtures, simulated version drift, `pip show`/`pipdeptree`, a direct PyPI check) rather than accepted as-is — including catching a third model's own hallucinations, not just a first model's gaps.
- One real, confirmed finding (the `google-generativeai` deprecation) deliberately not acted on this session, flagged for a future one rather than silently dropped.
- Full test suite green (53/53) throughout.

Full step-by-step log, including the exact `codex-kiro`/`agy` transcript excerpts and the verification commands for each claim: [progress-detail.md](./progress-detail.md).
