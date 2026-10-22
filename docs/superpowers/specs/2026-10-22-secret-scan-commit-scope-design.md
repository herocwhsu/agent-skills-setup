---
title: secret-scan scans only what git would commit
date: 2026-10-22
status: implemented
feature: feat-096
---

# secret-scan scans only what git would commit

## Problem

The shared Stop hook `templates/hooks/common/secret-scan.sh` runs
`gitleaks detect --source . --no-git` from the repo root. `--no-git` walks the whole
directory, gitignored files included. In Handy (2026-10-22) that is the 11 GB
`src-tauri/target/` build folder:

| Scan | Time | Result |
|---|---|---|
| current (`--no-git` over the tree) | 151 s | exit 1: false positives in `target/` `.rmeta` files |
| tracked + untracked-not-ignored files only | 0.9 s | exit 0 |

So every Stop in Handy took minutes and warned on build output that is never
committed. The warning says "review before committing"; an ignored file cannot be
committed by `git add -A`, so it is out of the hook's intent.

## Rule

The scan covers exactly the files `git ls-files --cached --others --exclude-standard`
lists (tracked, plus untracked files that are not ignored), that exist as regular
files. Not scanned: ignored files, symlinks (the current scan does not follow them
either), deleted tracked files, and submodule contents (a gitlink is not a file).

gitleaks has no gitignore option and `dir`/`detect` take one path, so the hook copies
those files, keeping their relative paths, into a `mktemp -d` folder (mode 700,
removed on exit) and runs the same `gitleaks detect --source . --no-git` there.
Findings keep their repo-relative paths, so a committed `.gitleaksignore`
`file:rule:line` entry still matches. The repo's `.gitleaksignore` and
`.gitleaks.toml` are passed by path (`-i`, `-c`) when they exist, so an ignored or
untracked copy of either still applies as it does today.

A file the copy cannot read (mode 000, or gone between listing and copying) does not
stop the scan: the other files are copied and scanned, and the hook prints which files
were not scanned and blocks (exit 2). Found by both reviews: under `set -e` a tar error
ended the hook with exit 1, a non-blocking Stop error, before gitleaks ran.
If no temp folder can be made (full or unwritable temp volume), the hook scans the
tree in place as before, slower but never skipped (found by the re-review).

Unchanged: the turn-scope gate, osv-scanner, output and exit codes, the repo config
block.

## Where

`templates/hooks/common/secret-scan.sh` and its copies with the same logic:
hangar `.claude/hooks/secret-scan.sh`, atelier `.claude/hooks/secret-scan.sh`, and the
installed `~/.agent-skills-setup/hooks/secret-scan.sh` (via `install.sh`).

Out of scope: `harness/guards/secret-scan.sh`, this repo's own whole-tree gate, has the
same `--no-git` walk. It is a separate script; flagged for a follow-up.

## Tests (written first, must fail on the current hook)

`scripts/tests/test_shared_hook_templates.sh`, with the real gitleaks (a SKIP line
when it is not installed), fake tokens generated at run time:

- a token in a gitignored file only: hook exits 0;
- a token in a tracked file: exits 2;
- a token in an untracked, not ignored file: exits 2;
- a token in a tracked file listed in `.gitleaksignore` as `file:rule:line`: exits 0;
- a token in a tracked file that was deleted from the working tree: no error;
- a file name with a space: scanned (exits 2);
- a token in one file and an unreadable (mode 000) second file: exits 2, the token is
  reported, and the warning names the files not scanned (skipped when run as root).
- `mktemp` failing (stubbed on PATH) with a token in a file: exits 2.

The existing test that gitleaks runs as `--source .` from the repo root changes to:
`--source .` from a folder holding only the commit-scope files.

## Acceptance

- Handy Stop scan finishes in about a second with no findings.
- All test cases above pass; the existing shared-hook tests still pass.
- hangar and atelier copies differ from the template only in the config block.
- All harness gates pass.
