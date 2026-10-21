---
title: agy review commands confined to the repo
date: 2026-10-20
status: implemented
feature: feat-095
---

# agy review commands confined to the repo

## Problem

feat-094 removed `--dangerously-skip-permissions` from agy reviews: `AGY_REVIEW_ALLOW`
(`scripts/outside_agent.py`) admits a few read-only commands, so a review cannot write.
It can still read outside the repo. Live in a scratch repo on 2026-10-20 (agy 1.4.3,
headless `-p`), these ran:

| Command | Result |
|---|---|
| `cat /etc/hosts`, `head -1 /etc/hosts`, `grep -c localhost /etc/hosts`, `ls /etc` | ran |
| `cat ../agytest/a.txt` | ran |
| `git diff -O /etc/hosts HEAD~1 --stat` | ran (`-O<file>` reads an order file) |
| `git diff --no-index /etc/hosts a.txt` | refused (flag not listed) |
| agy's built-in `read_file /etc/hosts` | refused: agy limits its own tools to the workspace |

The cause: `cat`, `head`, `tail`, `grep`, `ls` and `wc` are prefix rules
(`command(cat)`), which take any arguments, and the git rule's argument class lets
an argument start with `/` or `~`.

## Goal

A review's shell commands reach only paths inside the repo, the same limit agy
already puts on its built-in file tools. Ordinary review commands keep working.

## Rule

Every argument of an allowed command, quoted or not, and every short-flag value:

- does not start with `/` (absolute path) or `~` (home);
- has no `..` path part: `..` alone, or `..` at the start or end of the argument, or
  between `/` characters (`../x`, `a/../../x`, `x/..`).

A `..` inside a word stays allowed, so git ranges keep working: `HEAD~1..HEAD`,
`main...feature`, `a..b -- scripts/`.

Changes:

1. Replace `command(cat)`, `command(head)`, `command(tail)`, `command(grep)`,
   `command(ls)` and `command(wc)` with one `command(regex:...)` rule: the command,
   then arguments that are short flags with no value (`-n`, `-c`, `-rn`), `--` , or
   path-safe words and quoted strings, optionally piped into grep/head/tail/wc with
   the same arguments.
2. Tighten the git rule's plain and quoted arguments and its pipe arguments to the same
   path-safe class. Valued options (`--format=`, `--since=` ...) name no file and keep their
   values.
3. Short-flag values: the short-flag class `-[A-Za-z0-9]+` already refuses `-O/etc/x`,
   but `-O /etc/hosts` passed because `/etc/hosts` matched as a plain argument; change 2
   refuses it.
4. `AGY_REVIEW_NOTE` says no argument may be an absolute path, start with `~`, or use `..`.
5. `allow-agy` only added rules, so the prefix rules would have stayed in the live
   settings. It now removes the rules it retired (the nine prefix rules and older versions of
   its regex rules) and prints how many; a user's own `command(cat)` goes too, since it would
   reopen the same reads.
6. `git status`, `git rev-parse` and `git merge-base` move into the git regex rule too: a
   prefix rule takes any pipe, and `git status | cat /etc/hosts` ran live (2026-10-21).

## Tests (written first, must fail on the current rules)

`tests/test_outside_agent.py`, matched with Python `re` against the rule text (RE2 and
`re` agree on this subset: no lookaround, no backreferences):

- refused: `cat /etc/hosts`, `cat '/etc/hosts'`, `cat "/etc/hosts"`, `head -1 /etc/hosts`,
  `grep -c x /etc/hosts`, `grep -rn x ~`, `grep x ~/.ssh/id_ed25519`, `ls /etc`, `ls ..`,
  `cat ../x`, `cat a/../../x`, `wc -l x/..`, `git diff -O /etc/hosts HEAD~1`,
  `git log -- /etc`, `git diff | grep x /etc/hosts`. (`git show HEAD:path` names a
  path inside the commit, so it stays allowed.)
- allowed: `cat scripts/outside_agent.py`, `grep -n "AGY_REVIEW" scripts/outside_agent.py`,
  `grep -rn foo scripts/ tests/`, `head -50 README.md`, `ls scripts`, `wc -l a b`,
  `git diff HEAD~1..HEAD -- scripts/`, `git log main...HEAD --oneline`,
  `git show HEAD:scripts/install.sh | head -20`, `git diff --stat | tail -1`.
- Every refused case is also checked live once against agy (scratch repo, refusal
  appears in `denied_actions`), and two allowed cases run.

## Not covered

- A symlink inside the repo that points outside it: a rule over command text cannot see
  where a link leads. Checked 2026-10-21: no tracked symlink in this repo, hangar or atelier
  points outside its repo; the untracked pack-skill links sync writes (6 each in hangar and
  atelier, none here) point to skill folders under `~/.agent-skills-setup/pack-skills/` and
  `skills/`, which hold skill files, not secrets.
- Repo config that runs programs (diff drivers, `core.pager`, textconv): a reviewed repo is
  the owner's own; unchanged from feat-094.
- A grep pattern that starts with `/` is refused (`grep -E '^/usr'` is fine; `grep '/usr' x`
  is not). That ends the agy run with no answer; agy is optional, so nothing waits on it.

## Review

Permissions change: two fresh-context subagents (correctness; security and permissions).
