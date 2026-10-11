# Goal Specification Template

> Autonomous loop specification template (Lecture 13).
> Define the end state, machine-verifiable criteria, scope boundaries, and stopping conditions before starting an autonomous ratchet cycle.

## Goal

<!-- One-sentence summary of the target deliverable or optimization -->
Implement feature or optimization with complete automated verification.

## Acceptance Criteria

<!-- Machine-checkable conditions. Each criterion can be asserted with an automated command -->
- [ ] `bash scripts/run-tests.sh --fast --changed` passes with zero failures
- [ ] Linting clean (`.venv/bin/ruff check <target>`)
- [ ] Type validation clean (`.venv/bin/mypy <target>`)
- [ ] Independent reviewer signoff (Checker verdict: PASS)

## Scope

### Fair Game
<!-- Explicitly declare directories and files the agent is allowed to edit -->
- `scripts/<module>.py`
- `scripts/tests/test_<module>.sh`
- `tests/test_<module>.py`

### Hands Off
<!-- Explicitly declare boundary files the agent must NEVER modify -->
- `AGENTS.md`
- `registry.txt`
- `scripts/_lib.sh`
- `.github/workflows/`

## Verification Method

<!-- Commands to execute after each Maker change -->
1. Type check:
   - `npx tsc --noEmit` or `.venv/bin/mypy --config-file mypy.ini <files>`
2. Code style & lint:
   - `.venv/bin/ruff check <files>`
3. Unit & integration tests:
   - `bash scripts/run-tests.sh --fast --changed`

## Stop Conditions

<!-- Deterministic circuit breakers protecting against infinite loops or cost blowouts -->
- Target criteria met (all acceptance criteria confirmed by independent Checker)
- Max rounds reached: 10
- Circuit breaker: 3 consecutive failed or regressed iterations halts the loop (Status: `BLOCKED`)
- Rollback invariant: Any iteration that fails tests or is rejected by the Checker is immediately rolled back (`git reset --hard`)
