# Lecture 2 Training — Full Progress Detail

Companion to [summary.md](./summary.md). Exact commands, exact diffs, exact review transcript.

## Part 1 — Gap check against Lecture 2's five-subsystem model

Lecture 2's model: Instructions, Tools, Environment, State, Feedback. Cross-referenced against what Lecture 1 already covered via `harness-creator`'s scorer (Instructions/State/Verification/Scope/Lifecycle — see [lecture-01](../lecture-01/summary.md)):

| Lecture 2 subsystem | Lecture 1 scorer covers it? | Status found |
|---|---|---|
| Instructions | Yes | Already 5/5 from Lecture 1 |
| State | Yes | Already 5/5 from Lecture 1 |
| Feedback | Roughly = "verification" | Already 4/5 from Lecture 1 |
| **Tools** | **No** | Not checked before — found: no `permissions` block in `.claude/settings.json` |
| **Environment** | **No** | Not checked before — found: no `.python-version`, no manifest, no container def |

## Part 2 — Environment: `.python-version` pin

```bash
pyenv install 3.14.7                    # newest stable (3.15.0rc1 excluded — release candidate)
~/.pyenv/versions/3.14.7/bin/pip install mypy ruff
cd agent-skills-setup && pyenv local 3.14.7   # writes .python-version, scoped to this dir tree
```

Confirmed scoping (pyenv resolves by walking up from shell cwd):
```bash
cd /tmp/other-repo && python3 --version
# Python 3.13.4   <- global default, NOT 3.14.7. Pin does not leak.
```

First `bash init.sh` under the new pin surfaced mypy failures:
```
Cannot find implementation or library stub for module named "pytest"
Cannot find implementation or library stub for module named "anthropic"
Cannot find implementation or library stub for module named "google.generativeai"
Found 10 errors in 6 files (checked 27 source files)
```
Confirmed this was a real regression, not pre-existing, by running the OLD interpreter side by side:
```bash
~/.pyenv/versions/3.13.4/bin/python3 -m mypy --config-file mypy.ini .
# Success: no issues found in 27 source files
```
And confirmed why: `pip freeze` under 3.13.4 showed `pytest`, `anthropic`, `google-generativeai`, `lxml` already installed there — among ~80 total packages, most unrelated to this repo (numpy, onnxruntime, pymupdf, langfuse, etc. — this is a shared ambient pyenv environment, not isolated per-repo). Nothing in the repo declared these as dependencies anywhere.

Fixed by installing the actual needed set under 3.14.7:
```bash
~/.pyenv/versions/3.14.7/bin/pip install pytest==9.0.3 lxml==6.1.0
~/.pyenv/versions/3.14.7/bin/pip install google-generativeai==0.8.6
```
(Versions matched to what 3.13.4 already had, via `pip freeze`.) Full suite after: `bash scripts/run-tests.sh --fast` → 53 passed, 0 failed (was 45 passed, 8 failed immediately after the pin, before these installs).

### Dependency-manifest / osv-scanner investigation (parked, not resolved)

Tested which manifest filenames `osv-scanner` treats as a scannable package source (this matters because `AGENTS.md` deliberately keeps `pyproject.toml` out of the repo specifically so `secret-scan.sh`'s osv-scanner step stays at "no package sources found — OK", per its own documented reasoning):

```
requirements.txt        -> DETECTED
requirements-dev.txt    -> DETECTED
dev-requirements.txt    -> DETECTED
requirements-mypy.txt   -> DETECTED
Pipfile                 -> IGNORED
setup.py                -> IGNORED
environment.yml         -> IGNORED
poetry.lock             -> DETECTED
requirements.lock       -> IGNORED
deps.txt                -> IGNORED
constraints.txt         -> IGNORED
```

Then tested what happens once a real manifest exists, using this repo's actual imported third-party packages (`pytest`, `anthropic`, `google.generativeai`, `lxml`) pinned to installed versions:
```
Total 3 packages affected by 5 known vulnerabilities (0 Critical, 1 High, 2 Medium, 2 Low, 0 Unknown)
idna 3.9.0 -> 3.15 (fixed)
pygments 2.9.0 -> 2.15.1 / 2.20.0 (fixed)
tqdm 4.9.0 -> 4.11.2 / 4.66.3 (fixed)
```
Same test against a full ambient `pip freeze` (not scoped to this repo) also found real CVEs (idna, soupsieve, urllib3) — but that manifest is not trustworthy as a statement of this repo's actual dependencies, since the ambient pyenv environment is shared across unrelated projects on this machine.

**Decision at the time: parked.** Building a scoped, trustworthy manifest needs a real isolated venv for this repo (not the shared ambient environment), and a decision on whether finding real CVEs should change repo policy (accept the osv-scanner exposure that comes with declaring dependencies at all vs. keep hiding it). Recorded here so it is not silently lost; not resolved this session by explicit scope decision.

## Part 2b — Resolved (later session)

Built the isolated venv, from the already-pinned interpreter:
```bash
cd agent-skills-setup
python3 -m venv .venv
.venv/bin/python3 --version
# Python 3.14.7   <- inherits .python-version, not a second/competing pin
.venv/bin/pip install --quiet mypy ruff pytest lxml anthropic google-generativeai
```

Generated the manifest and scanned for real:
```bash
.venv/bin/pip freeze > requirements-dev.txt
osv-scanner scan source --recursive . --verbosity error
# No issues found
osv-scanner scan source --recursive .   # verbose, to confirm it's not silently no-oping
# Scanned /Users/herohsu/Project/agent-skills-setup/requirements-dev.txt file and found 51 packages
# No issues found
```
Clean — no CVE-driven version bumps needed. The earlier CVE list (idna, soupsieve, urllib3) came specifically from the *ambient* pyenv environment's older pinned versions (shared across ~80 unrelated packages on this machine); a fresh install of only this repo's real dependencies landed on current, unaffected versions (e.g. `idna==3.20`, well past the `3.15`-fixed CVE).

Rewired the two real gates that need third-party packages (per a full audit of all bare `python3`/`mypy`/`pytest` call sites in the repo — everything else either ships to other people's machines and must stay on ambient PATH, or only imports stdlib and needs no change):

```diff
# .claude/hooks/types-guard.sh
+MYPY="$REPO_DIR/.venv/bin/mypy"
+[[ -x "$MYPY" ]] || MYPY="mypy"
-if ! command -v mypy >/dev/null 2>&1; then
+if ! command -v "$MYPY" >/dev/null 2>&1; then
...
-if ! out=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 mypy 2>&1); then
+if ! out=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 "$MYPY" 2>&1); then
```
```diff
# scripts/run-tests.sh
+PYTHON="$REPO_DIR/.venv/bin/python3"
+[[ -x "$PYTHON" ]] || PYTHON="python3"
...
-  if out=$(python3 -m pytest "$f" -q --tb=short 2>&1); then
+  if out=$("$PYTHON" -m pytest "$f" -q --tb=short 2>&1); then
```

Fixed the one test that literal-string-matched the old invocation form:
```diff
# .claude/hooks/tests/test_types_guard.sh
-grep -q 'xargs -0 mypy' "$HOOK" \
+grep -qE 'xargs -0 "\$MYPY"' "$HOOK" \
```

Added `.venv/` to `.gitignore`.

Verification, in order:
```bash
bash .claude/hooks/tests/test_types_guard.sh
# test_types_guard: 9 passed, 0 failed

bash scripts/run-tests.sh --fast
# Results: 53 passed, 0 failed, 0 skipped, 0 code-bearing subcommands without tests

# Confirm the fallback doesn't silently change behavior:
.venv/bin/mypy --config-file mypy.ini .
# Success: no issues found in 27 source files
mypy --config-file mypy.ini .   # bare, ambient PATH (still resolves 3.14.7 via .python-version)
# Success: no issues found in 27 source files    <- identical

# The one path with zero prior test coverage, per the earlier investigation:
bash .claude/hooks/secret-scan.sh
#   OK  gitleaks
#   OK  osv-scanner
# exit: 0
```

Updated `mypy.ini`'s stale comment and `AGENTS.md`'s osv-scanner section to describe the new, real state rather than "always no-ops here" (both quoted in full in the diff below for the record):

```diff
# mypy.ini
-# Not pyproject.toml: osv-scanner treats that as a dependency manifest, and
-# .claude/hooks/secret-scan.sh special-cases this repo's "No package sources
-# found" result as OK. A pyproject.toml would change that Stop hook's behavior
-# as a side effect of a typing decision. Same reasoning as ruff.toml.
-#
-# python_version is deliberately unset so mypy assumes the running interpreter
-# rather than pinning semantics a contributor on another version would not have.
+# Not pyproject.toml: osv-scanner treats that as a dependency manifest, and
+# a pyproject.toml would change secret-scan.sh's Stop-hook behavior as a side
+# effect of a typing decision. requirements-dev.txt is the manifest instead —
+# see AGENTS.md's Python section for what osv-scanner actually does with it.
+# Same pyproject.toml-avoidance reasoning as ruff.toml.
+#
+# python_version is deliberately unset so mypy assumes the running interpreter
+# rather than pinning semantics a contributor on another version would not have.
+# .python-version + .venv now standardize contributors on one interpreter
+# (3.14.7) anyway, so the portability gap this guarded against is smaller than
+# when this comment was written — left unset regardless, since mypy still
+# infers correctly from whichever interpreter actually runs it, pinned or not.
```

This also directly answers `codex-kiro`'s point 4 from Part 4 above: pinning the interpreter and leaving `python_version` unset were never actually in conflict — mypy still infers from whichever interpreter runs it, pinned or not. The comment's original rationale (portability across contributor versions) is simply less load-bearing now that `.venv` standardizes on one interpreter anyway. Recorded here rather than silently dropped, since `codex-kiro`'s point was a legitimate documentation-staleness catch even though the underlying mechanics were never broken.

## Part 3 — Tools: permissions block, first draft

```json
"permissions": {
  "deny": [
    "Write(//Users/*/AGENTS.override.md)",
    "Edit(//Users/*/AGENTS.override.md)"
  ],
  "ask": [
    "Bash(bash scripts/install-agents-md.sh*)",
    "Bash(bash scripts/install.sh*)"
  ]
}
```
Mapped from 2 of `AGENTS.md`'s 4 "Boundaries" (the other 2 — `init-repo.sh` targeting, and test `HOME` redirection — are not permission-rule-shaped: one is about external invocation of this repo, the other is a testing discipline). `bash -n` clean, `jq` valid, full suite 53/53 at this point (before review).

## Part 4 — `codex-kiro` review of the first draft

```bash
codex-kiro exec -s read-only -C "$(pwd)" "Two changes were just made... Give a blunt, critical verdict on each of the 4 points, not a rubber stamp. Under 250 words total."
```

Full verdict (verbatim, model `gpt-5.6-sol` via `kiro-gateway`):

> 3. **Permissions verdict: inadequate.** `Write(//Users/*/AGENTS.override.md)` matches only files directly beneath `/Users/<entry>/`; it misses `/Users/alice/project/AGENTS.override.md`, which violates "anywhere under." ... The Bash rules are trivially bypassed with `./scripts/install.sh`, `/bin/bash scripts/install.sh`, `sh`, `source`, an absolute path, or a wrapper. ... These rules provide ceremony, not a reliable boundary.
>
> 4. **Python verdict: unnecessarily aggressive.** `mypy.ini` deliberately leaves `python_version` unset so contributors are checked against their running interpreter; pinning the runtime to 3.14.7 effectively undermines that portability choice.

## Part 5 — Independent confirmation of the glob-depth claim

Did not accept point 3 on say-so. Reproduced the exact pattern behavior with a local fixture, same technique as Lecture 1's mutation testing:

```bash
mkdir -p /tmp/glob-test/Users/alice/project
touch /tmp/glob-test/Users/alice/AGENTS.override.md
touch /tmp/glob-test/Users/alice/project/AGENTS.override.md
cd /tmp/glob-test
ls -d Users/*/AGENTS.override.md   # single star
# Users/alice/AGENTS.override.md            <- only the shallow one
shopt -s globstar
ls -d Users/**/AGENTS.override.md  # double star
# Users/alice/AGENTS.override.md
# Users/alice/project/AGENTS.override.md    <- both, confirmed the fix works
```
This is a bash-glob sanity check, not the Claude Code permission engine itself, but it isolates the exact `*` vs `**` path-crossing behavior the finding depends on — confirmed independently, not just repeated.

The bypass claim (point 3, second half) was corroborated by a fact already known from earlier in this session: `~/.claude/settings.json` (this host's user settings) has `"permissions": {"defaultMode": "auto"}` — so an unmatched Bash invocation is not just unblocked by the missing `ask` rule, it is likely auto-approved by the host default rather than falling back to a manual prompt.

## Part 6 — Fixes applied

**Deny rule widened** (`*` → `**`):
```diff
-      "Write(//Users/*/AGENTS.override.md)",
-      "Edit(//Users/*/AGENTS.override.md)"
+      "Write(//Users/**/AGENTS.override.md)",
+      "Edit(//Users/**/AGENTS.override.md)"
```
Re-ran the same fixture test above against the new pattern — confirmed it now matches all three nesting depths tested (direct, one level, two levels deep).

**Ask rules removed entirely**, not patched to cover more invocation forms — enumerating every bypass (`./x.sh`, `sh x.sh`, `source x.sh`, absolute path, a wrapper script) is not a stable boundary, so `AGENTS.md` was edited instead to say plainly that this boundary is advisory-only:

```diff
 - Ask before running `scripts/install-agents-md.sh` or `install.sh`: both write
-  outside the repo and change agent behavior for every project.
+  outside the repo and change agent behavior for every project. Advisory only —
+  a settings.json `ask` rule matching one invocation form (`bash scripts/x.sh`)
+  is trivially bypassed by any other (`./scripts/x.sh`, `sh scripts/x.sh`, an
+  absolute path), so this is not enforced and was deliberately not attempted as
+  a permission rule.
```

Also documented the deny rule as enforced, for symmetry:
```diff
 - Never write `AGENTS.override.md` — Codex prefers it over `AGENTS.md`, so it would
-  shadow whatever the user put there.
+  shadow whatever the user put there. Enforced: `.claude/settings.json` denies
+  `Write`/`Edit` on `AGENTS.override.md` under any user's home dir.
```

Point 4 (Python version tension with `mypy.ini`'s stated design) — **not acted on**. Out of scope for what was agreed this session; recorded in summary.md as an open finding for a future session to pick up deliberately, rather than silently changed or silently dropped.

## Part 7 — Final verification

```bash
jq -e '.permissions' .claude/settings.json
# { "deny": [ "Write(//Users/**/AGENTS.override.md)", "Edit(//Users/**/AGENTS.override.md)" ] }

bash scripts/run-tests.sh --fast
# Results: 53 passed, 0 failed, 0 skipped, 0 code-bearing subcommands without tests
```

Both findings originally left open at this point — the dependency-manifest/osv-scanner question, and the Python-version-vs-mypy.ini tension — were resolved in a later session within the same training arc: see Part 2b above.

## Part 8 — Multi-model review of Part 2b's fallback logic (a third model surfaces, and hallucinates)

Reviewed the `.venv` fallback logic and `requirements-dev.txt` with two independent models before considering it closed, per this training's established discipline.

**`codex-kiro` (`gpt-5.6-sol`)** — first attempt failed outright (`ERROR: Reconnecting... 1/5` through `5/5`, then `stream disconnected before completion: response.failed event received`, exit 1). Retried once; second attempt succeeded and produced real findings:

> 1. **Fallback: weak for a gate.** `-x` proves only executability. A stale entry-point can reference the wrong but still-existing Python, wrong mypy version, or outdated packages. If its shebang is broken, `types-guard.sh` detects that and exits successfully with SKIP, bypassing the type gate.
> 2. **Python-version drift: real bug.** If `.venv` was built with a different Python than `.python-version`, both scripts use it without complaint... Validate `sys.version` against `.python-version`, and fail with rebuild instructions rather than falling back when `.venv` exists.
> 3. Bigger concern: `google-generativeai` is the legacy/deprecated SDK. Review migration to `google-genai`.
> 4. Keep a small `requirements-dev.in` of direct requirements, generate the fully pinned lock reproducibly.

**`agy`** (a third, genuinely different model family — Gemini-based, not GPT-via-kiro-gateway or Claude) was brought in specifically because `codex-kiro` had just failed once — a good instinct: don't lean on a single tool's reliability wobble. First call failed differently: `--dangerously-skip-permissions` was required (headless `--print` mode cannot prompt for tool permission, so a read-only shell command was auto-denied and the call returned nothing). Retried with that flag granted for this one read-only review. Result:

> * **`google-generativeai`:** Deprecated/legacy. Google superseded it with the unified `google-genai` SDK.
> * **Suspicious Packages:** `httpx2` and `httpcore2` appear instead of canonical `httpx` and `httpcore`—potential typosquats or unauthorized forks.
> * **Bogus Runtime:** `.python-version` pins `3.14.7` (Python 3.14.7 does not exist).

**Two of `agy`'s three claims were checked and are false** — not accepted on say-so, per this training's own rule:
- "Python 3.14.7 does not exist" — false. Installed via `pyenv install 3.14.7` earlier this session; `.venv/bin/python3 --version` had already printed `Python 3.14.7` multiple times before this claim was made.
- "`httpx2`/`httpcore2` are potential typosquats" — false. `pip show httpx2` confirms a real PyPI package (`homepage: github.com/pydantic/httpx2`, author Tom Christie — httpx's actual creator), and `pipdeptree --reverse -p httpx2` confirms it's a legitimate transitive dependency: `anthropic==1.6.0 [requires: httpx2>=2.0.0,<3]`.

**One claim from both models converged and was independently verified against a primary source**: `google-generativeai` deprecation. Checked PyPI directly (`WebFetch` on `https://pypi.org/project/google-generativeai/`) rather than trust either model:

> "Please be advised that this repository is now considered legacy." Development limited to "critical bug fixes only." Support "ended permanently on November 30, 2025." Successor: the `google-genai` SDK.

**Actioned — the version-drift/silent-fallback gap** (both models flagged it independently; the failure mode is real and mechanically confirmed, not just claimed):

```bash
cd agent-skills-setup
echo "9.9.9" > .python-version   # simulate drift: .venv is 3.14.7, pin now says otherwise
bash .claude/hooks/types-guard.sh
# Blocked: .venv is Python 3.14.7 but .python-version pins 9.9.9 — rebuild: ...
echo "exit: $?"   # 2 — blocks, does not silently fall back
```
Both `types-guard.sh` and `run-tests.sh` now check, when `.venv` exists: (1) its `python3`/`mypy` binaries are actually executable — a missing or broken venv fails loud with rebuild instructions, not a silent skip; (2) its Python version matches `.python-version` — a mismatch fails loud (exit 2 for the Stop-hook gate, exit 1 for the test-runner CLI convention) rather than silently degrading to whichever tool happens to be on ambient PATH. Restored the correct pin and reran — passes clean; full suite `bash scripts/run-tests.sh --fast` → 53 passed, 0 failed throughout.

**Not actioned — the `google-generativeai` → `google-genai` migration.** This is real, confirmed by a primary source, and two independent models flagged it — but it touches actual shipped code (`skills/utils/polish-input/lib/polish_engine.py`'s Gemini-backend import and client API), not just dev tooling. That's a larger, different-shaped change than today's scope (dependency manifest + mypy comment + version-drift guard). Flagged clearly to the user rather than silently expanded into or silently dropped.

**Not actioned — `requirements-dev.in` (direct-deps-only file, both models suggested it).** `requirements-dev.txt` (the full `pip freeze`) stays the single manifest for now — it's what osv-scanner scans and what's verified clean. Splitting direct from transitive deps is a real hygiene improvement but adds a second file to keep in sync for a 6-direct-dependency manifest; not worth the overhead at this size. Noted here as a legitimate suggestion, not required.

## Part 9 — The controlled variable exclusion test, attempt 2 (attempt 1 was null)

**Attempt 1** (mirror a 20-line sibling file, strip Instructions/State/Feedback across 4 fresh subagents): all 4 conditions succeeded identically. Null result — the task was fully answerable from the sibling file alone, so it never exercised any of the three subsystems being stripped.

**Attempt 2** used a harder task, designed against attempt 1's specific failure: no single sibling file fully specifies the answer.

**Task given to all 4 conditions, verbatim:** "Add a new verification gate that runs `shellcheck` against this repo's shell scripts, following the same conventions as the repo's existing gates. Create a guard script under `.claude/hooks/`, wire it into `scripts/harness-verify.sh`, add it to the Stop/SubagentStop hook arrays in `.claude/settings.json`, and add a test file under `.claude/hooks/tests/`." Real ambiguity (which files, what severity, exit-code convention), a non-obvious stopping point (four integration points, not one file), a mechanically verifiable outcome.

**Method:** one baseline copy of the repo (`git archive HEAD` — tracked files only, excludes the 380MB `.venv`), 3 ablated variants derived from that same baseline (never built independently):

- `no-instructions`: `AGENTS.md` removed.
- `no-state`: `feature_list.json`, `progress.md`, `init.sh` removed.
- `no-feedback`: `scripts/run-tests.sh` and both test directories removed — but not `scripts/harness-verify.sh`, since that's the task's actual edit target, not a feedback mechanism.

One fresh (non-fork) `general-purpose` subagent per variant, 4 total, concurrent, each given only its directory and the task text — no mention of the experiment.

**Result: non-null.** All 4 completed the core task, but not identically:

| Condition | Wiring | Own tests | Found pre-existing SC1087 bug (`test_install_agents_md.sh:210`) | Fixed it |
|---|---|---|---|---|
| baseline (has `AGENTS.md`) | complete | 12/12 | yes | **yes** |
| no-instructions | complete | 6/6 | yes | no — flagged out of scope |
| no-state | complete | 6/7 (asserted, correctly failed) | yes | no — flagged out of scope |
| no-feedback | complete | 8/8 | n/a — see confound | — |

**Confound (caught after all 4 results were in):** `no-feedback`'s ablation deleted `scripts/tests/` wholesale, which happened to also delete `test_install_agents_md.sh` — the file containing the bug. Its silence on the bug is an artifact of the ablation, not a finding; excluded from the comparison. The other 3 ablations never touched that file.

**What the valid 3-way comparison shows:** all 3 independently found the identical bug (strong cross-validation it's real). Only the condition with `AGENTS.md` went from *flag* to *fix* — a genuine correlated difference, the first non-null exclusion-test result in this training.

**What it does NOT establish:** `AGENTS.md` has no instruction resembling "fix incidental bugs" (grepped directly — no match). The mechanism linking "has `AGENTS.md`" to "fixed rather than flagged" is unconfirmed — this is a correlation, not a proven cause. Would need a follow-up (rerun, or ask the agent directly) to move it from lead to verdict.

**Verification performed on the results, not just self-report:** read `.claude/settings.json` in each variant directly (confirmed wiring in both hook arrays, all 4); read the actual test files in `no-feedback`/`no-state` to resolve two apparent discrepancies, both false alarms (an assertion-count mismatch, a harness scanner false-positive on ordinary settings.json content); checked all 4 guard scripts for bash-4+-only syntax against the documented bash-3.2 floor — none found, including in the 3 conditions that never saw that constraint stated; confirmed the confound directly via file-existence check rather than accepting the "n/a" cell.

## Part 10 — Affordance analysis (Gulf of Execution / Gulf of Evaluation)

Lecture 2's last exercise: take concrete stuck-or-wrong-turn cases from real work and classify each into Norman's two gulfs — **Gulf of Execution** (the actor knows what they want, but the interface offers no clear path to it) versus **Gulf of Evaluation** (an action happened, but its result isn't legible enough to tell whether it worked). Used two real cases from this same training session rather than inventing synthetic ones.

**Case 1 — `polish-input` hook fabricating fake refusals/identities. Gulf of Evaluation.**

Across this session, the `UserPromptSubmit` hook (meant to silently inject a paraphrase) repeatedly returned fabricated text shaped like a full agent turn instead — a refusal ("appears to be an attempt to override my system guidelines") or a contradicting identity claim ("I'm Kiro... I don't rewrite user messages"). Each time, the real user message was underneath, and I had to recognize the fabrication and act on the real message instead.

This is a Gulf of Evaluation failure, and it's the hook's own gulf first, surfaced to me second. The hook has no feedback loop on its own output: no schema check, no shape/length sanity check, no confidence signal distinguishing "the polish model produced a genuine paraphrase" from "the polish model hallucinated a tangent." It just runs the call and forwards whatever comes back as `additionalContext`. The hook's action always "succeeds" from Claude Code's point of view (exit 0, valid JSON) — the ambiguity is entirely in whether the content means what it claims to mean, and nothing in the tool tells you that.

Downstream, this becomes my own Gulf of Evaluation problem: I have no structural signal (a flag, a marker, a confidence field) to check — only content-level judgment, redone from scratch each occurrence, on whether hook output is trustworthy.

**Case 2 — spurious `exit 128` across all 4 exclusion-test sandboxes. Gulf of Execution.**

All 4 subagents dispatched in Part 9, working in `git archive`-built copies with no `.git` directory, hit `types-guard.sh` failing (exit 128, `git ls-files` on a non-repo) when running `harness-verify.sh` end-to-end. All 4 independently diagnosed this correctly as environmental, not caused by their change — but each had to rediscover the same root cause from scratch, with no shortcut available.

This is Gulf of Execution, not Evaluation: the feedback itself was clear (a plain exit code and an unambiguous git error). The gap is that `harness-verify.sh` offers exactly one action — run all 8 gates — with no way to express a narrower, equally valid intent ("run only the gate relevant to my change" or "skip gates that assume a real git repo"). Each agent's goal was clear; the tool simply didn't expose a path to it, so every agent paid the same diagnostic cost independently.

**Why one case of each, not four of one kind:** the two gulfs are conceptually distinct failure shapes, and this session happened to produce one clean example of each without needing to manufacture one. Forcing a second example of either into this write-up would pad the exercise without adding a new distinction to reason about.

**Not done:** neither gap was fixed as part of this exercise — Lecture 2's affordance-analysis step is a classification exercise, not a remediation task, and turning either into an actual fix (a schema/sanity check on hook output; a `--gate <name>` selector on `harness-verify.sh`) is future work, not implied as required by this exercise itself.
