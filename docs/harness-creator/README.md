# harness-creator lectures

Frozen training history for lectures 1 to 15. Do not extend these folders; new work goes in the places below.

- `lecture-N/summary.md` holds the takeaways and `lecture-N/progress-detail.md` the work log.
- `lecture-N/code/*.py` is teaching code with its own tests. Nothing in `scripts/` imports it, and `run-tests.sh` still runs those tests so the examples keep working.
- Lectures 13, 14 and 15 were promoted to production: use `scripts/ratchet_loop_runner.py`, `scripts/graph_runner.py` and `scripts/team_runner.py`. Their engine copies were removed, and the lecture docs link to the runners.
- Changing teaching code here changes no production behavior. To change behavior, edit `scripts/` and `tests/`.
