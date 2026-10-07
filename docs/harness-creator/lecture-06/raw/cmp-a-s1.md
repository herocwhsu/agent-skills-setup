# wordstat session 1

- Tool calls used: 9 of 20 (this file is call 9).
- First passing test: tool call 6 (all 10 tests passed together).
- Features completed and verified by pytest: F1, F2, F3, F4, F5. Commit `01ce96d`.
- Half-done: nothing. Not built: packaging/entry point. The CLI runs as `python3 wordstat.py`, and no `wordstat` command gets installed.

Notes:
- Call 3 was the RED run. It failed at collection because `wordstat.py` didn't exist yet, so the tests never ran one by one against a stub.
- Call 4 fixed my own miscounted expected values in the tests: the sample has 10 words, not 9.
- Decisions are recorded in the README: tokenization, `--top` text output omits the total, and stopwords also reduce the total.
