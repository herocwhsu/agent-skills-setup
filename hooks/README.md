# hooks/

Reusable Claude Code hook templates. Copy into a repo's `.claude/hooks/` to enable local quality gates.

## What are Claude Code hooks?

Hooks run on your local machine when you use Claude Code — not in CI. They give instant feedback before you commit. CI is the team-wide gate; hooks are the developer-experience layer.

```
You type in Claude Code
        ↓
PostToolUse hooks fire after every file edit   (format, lint, guard)
        ↓
Stop hooks fire when Claude thinks it's done   (tests, SAST, CVE scan)
        ↓
You commit — CI enforces the same gates for everyone
```

Exit codes: `0` = ok, `1` = block (error), `2` = warn (agent self-corrects).

## Required tools

```bash
# Security scanners
brew install gitleaks semgrep grype checkov osv-scanner

# Python
pip install ruff bandit pip-audit pytest

# Go
go install github.com/securego/gosec/v2/cmd/gosec@latest
go install golang.org/x/vuln/cmd/govulncheck@latest

# Shell
brew install shellcheck

# K8s
brew install kubectl kustomize

# Node/JS — via nvm or brew
brew install node
```

Missing tools are skipped gracefully — hooks never crash on a host that lacks a tool.

Run `bash .claude/hooks/check-tools.sh` to see what's installed on the current machine.

## Hook library

```
common/
  secret-scan.sh      Stop — gitleaks + osv-scanner
  semgrep-guard.sh    Stop — SAST (customize --config flags for your stack)
  grype-guard.sh      Stop — CVE scan on filesystem / images (HIGH+ with fixes)
  sh-check.sh         PostToolUse *.sh — bash -n + shellcheck

python/
  ruff-fix.sh         PostToolUse *.py — auto-format with ruff (silent)
  py-guard.sh         Stop — ruff check + bandit + pip-audit + pytest
  migration-guard.sh  PostToolUse *.sql — warn if modifying committed migration

js/
  ts-fix.sh           PostToolUse *.ts/tsx/js/jsx/css — auto-format with prettier
  ts-guard.sh         Stop — tsc + vitest + eslint

go/
  gosec-guard.sh      Stop — gosec security scan
  govulncheck-guard.sh Stop — govulncheck dependency vulnerability scan

k8s/
  yaml-validate.sh    PostToolUse *.yaml — kustomize build on nearest overlay
  placeholder-guard.sh PostToolUse *.yaml — warn on hardcoded IPs/credentials
  checkov-guard.sh    Stop — IaC misconfiguration scan

check-tools.sh        Inventory which tools are installed (run once per machine)
```

## Scaffold a new repo

```bash
# from agent-skills-setup root
bash scripts/init-repo.sh <profile> [/path/to/repo]

# profiles
python-api   — ruff-fix, migration-guard, py-guard + common
react        — ts-fix, ts-guard + common
go-api       — gosec-guard, govulncheck-guard + common
k8s          — yaml-validate, placeholder-guard, checkov-guard + common
full         — everything
```

Then wire hooks into `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write|MultiEdit", "hooks": [
        { "type": "command", "command": "bash .claude/hooks/ruff-fix.sh" },
        { "type": "command", "command": "bash .claude/hooks/migration-guard.sh" },
        { "type": "command", "command": "bash .claude/hooks/sh-check.sh" }
      ]}
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "bash .claude/hooks/py-guard.sh" },
        { "type": "command", "command": "bash .claude/hooks/semgrep-guard.sh" },
        { "type": "command", "command": "bash .claude/hooks/grype-guard.sh" },
        { "type": "command", "command": "bash .claude/hooks/secret-scan.sh" }
      ]}
    ]
  }
}
```

## Design principles

- **Repo-local, not global** — each repo owns its `.claude/` copy. Hooks evolve with the repo.
- **agent-skills-setup is the template source** — copy on scaffold, then the repo owns it.
- **Always skip, never crash** — every tool call is guarded with `command -v`. Missing tools print a SKIP line and exit 0.
- **Warn (exit 2), don't block (exit 1)** — most hooks warn so the agent self-corrects. Only hard errors (bash syntax) block.
- **stdin JSON** — PostToolUse hooks read the edited file path from Claude Code's JSON stdin, not `$1`.
