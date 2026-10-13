# Gate necessity: method and results

Question: are all 11 gates in `scripts/harness-verify.sh` worth their cost? This note is evidence for that decision. It never removes a gate.

## Two kinds of evidence

1. **Field data.** How often each gate actually stopped work in real sessions, from the `stop_hook_summary` records of the 24 Claude Code sessions in this repo (225 Stop-hook runs).
2. **Planted defects.** One defect at a time is planted in a clone, the full gate set runs, and the tool records which gates fail. `harness-verify.sh` runs every gate even after one fails, so one run per defect shows the whole picture.

## Field data (24 sessions, 225 Stop-hook runs, 2026-09 to 2026-10-13)

How often each guard returned feedback to the agent, from `stop_hook_summary` records:

| Guard | Fired |
|---|---|
| commit-evidence | 43 |
| tests | 5 |
| bash-compat | 1 |
| runtime-drift | 1 |
| secret-scan | 1 |
| registry, types, skill-paths, credential-backend, hook-wiring, state-layer, clean-state | 0 |

`commit-evidence` asks the agent to check new commits; its count is how often it asked, not how many problems it found. During this work the `harness-verify` gate set also failed: secret scan 4 times (test strings that looked like keys), types once (two benchmark fixture files with one module name), runtime drift once (a runtime-copied file edited without syncing). Zero firings is not proof of uselessness: the defects behind several gates (a credential branch missing on Linux, a runtime copy out of sync) are rare by nature, and 24 sessions of one author in one repo is a small sample.

## How the experiment runs

`python3 scripts/gate_experiment.py` (all cases) or `--case <id>` (one). Cases are data in `tests/gate_cases/cases.json`: the file changes to plant and the gate each case was written for.

- A baseline run of the unmodified tree comes first. If any gate already fails there, the tool stops: with a gate failing everywhere, every case would look as if that gate caught it.
- Each case gets a fresh clone of the working tree, uncommitted edits included, and a case that sets `stage` has its planted files `git add`ed (the type gate reads only tracked files; the clean-state gate looks for files that are not committed, so staging would hide those). The source tree is never touched.
- `HOME` is a throwaway directory, and the runtime-drift gate compares against a throwaway copy of the four runtime files, so nothing is written to the real home directory and the real installed runtime is not read.
- A case whose expected gate does not fail is a **broken case** and is excluded from conclusions. A gate that does not catch the defect written for it is a finding about the case first.
- The secret-shaped case writes random-looking material generated at run time (a fixed low-entropy string such as `abcdef…` is ignored by the scanner), so no key-shaped literal sits in the source or its bytecode.

## How a verdict is reached

| Verdict | Meaning |
|---|---|
| needed | at least one valid case is caught by this gate and by no other |
| possibly redundant | every valid case it catches is also caught by another gate that would stay; gates that only ever fail together are not both flagged |
| needed if the gates it overlaps with are also removed | covered only by gates that are themselves flagged |
| cannot judge | no valid case exercises it |

"Possibly redundant" is a prompt to look closer, not permission to delete. A gate can be the only guard against a defect nobody planted.

## Limits

- 12 cases, one per gate plus a second for the state layer. They are the defects each gate was written for, so they favour the gates being judged needed; a defect no case imagines is invisible here.
- A gate that never fired in the field is not shown to be useless: the defects it guards (a credential branch missing on Linux, a runtime copy out of sync) are rare by nature.
- The clone shares the repo's `.venv` through a symlink; the types and tests gates therefore run against the same interpreter as the real repo.
- Gates are judged one defect at a time. Two defects in one change are not tried. A gate that fails in the baseline is reported as `cannot judge`.

## Results (2026-10-13)

Baseline of the unmodified tree: all 11 gates pass. Twelve cases; the full run took 20 minutes. The clean-state case was first reported as broken because the tool staged every planted file, which hid it from a gate that looks for uncommitted files; after the fix (stage only the type case) it was re-run alone and the clean-state gate caught it.

| Case | Written for | Caught by |
|---|---|---|
| registry-missing-skill | registry | registry, tests |
| types-error | types | types |
| tests-broken-assertion | tests | tests |
| skill-path-undefined-var | skill paths | skill paths, tests |
| bash-compat-mapfile | bash compat | bash compat, tests |
| credential-backend-missing-branch | cred backends | cred backends, tests, runtime drift |
| hook-wiring-missing-target | hook wiring | hook wiring, tests |
| state-layer-two-active | state layer | state layer, tests |
| state-layer-done-without-evidence | state layer | state layer, tests |
| clean-state-scratch-file | clean state | clean state |
| runtime-drift-lib-edit | runtime drift | runtime drift |
| secret-scan-key-shape | secret scan | secret scan |

What the table says:

- **Four gates are the only catch for their defect: types, clean state, runtime drift, secret scan.** Nothing else fails on those cases.
- **Six gates overlap with the `tests` gate:** registry, skill paths, bash compat, cred backends, hook wiring, state layer. Each case written for them also fails the test suite. That is why the tool labels them "possibly redundant".
- **This overlap is an artifact of how the suite is built, and the label should not be acted on as is.** The test suite contains tests that run these very checks (for example `test_bash_compat_guard.sh` runs the bash-compat check over the whole tree; `test_hook_wiring.sh` and `test_state_layer_guard.sh` do the same for theirs). The `tests` gate catches these defects because the guards' own tests run the guards. Removing the guard and keeping its test would keep the defect caught, but only at the cost of a 70-second suite run instead of a sub-second guard, and only when the whole suite runs. The guards exist partly because they are fast and also run on every Stop and SubagentStop hook (the `tests` gate there runs only the tests for changed files). So these six are cheap and fast; the redundancy is real in coverage but not in speed.
- **Cost of the six overlapping gates in a full run** (from the gate report): registry 0.03 s, skill paths 0.4 s, bash compat 1.3 s, cred backends 0.14 s, hook wiring 0.15 s, state layer 0.3 s: about 2.3 seconds in total, against about 73 s for tests, 9 s for the secret scan and 1.1 s for types. Removing them would save almost nothing.
- **The only meaningful time costs are `tests` (70 s) and `secret scan` (9 s), and both are the sole catch for something.** The experiment gives no reason to drop either.

## Conclusion

No gate should be removed on this evidence. The gates that cost time are also the ones with unique catches, and the ones that overlap with the test suite cost about two seconds combined. The field data does not change that: the seven guards that never fired in 24 sessions are the cheap, fast ones that protect rarely-hit but expensive-to-find defects. This is evidence about 12 planted defects, not proof that no other defect exists; rerun `gate_experiment.py` before changing any gate.
