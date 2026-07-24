---
title: kiro-gateway fork-source reproducible setup
date: 2026-07-24
status: approved
supersedes: 2026-06-03-kiro-gateway-skill-design.md (Image Source + Non-Goals)
---

# kiro-gateway fork-source reproducible setup

Refactor the existing `infra/kiro-gateway` skill so it reproduces the real working
gateway on any host — macOS or Linux, arm64 or amd64 — building from the user's
**fork** (which carries a required bug fix) instead of pulling the upstream image.

## Problem

Three gaps prevent quick bring-up on a new host:

1. **Wrong image source.** The skill pulls `ghcr.io/jwadow/kiro-gateway` (upstream).
   Upstream defines `AnthropicMessage.role` as `Literal["user","assistant"]`, which
   returns **HTTP 422** on any `/v1/messages` request carrying a `system` item in the
   `messages` array — exactly what Claude Code sends. The running host instead builds
   `kiro-gateway:latest` from the fork `herocwhsu/kiro-gateway`, whose commit
   `5b4b873` relaxes the field to `role: str`. The skill would reintroduce the bug.
2. **Mount-path drift (latent bug).** The skill mounts the kiro-cli data dir at
   `/home/ubuntu/.local/share/kiro-cli`, but the fork image runs as user `kiro` and
   the working `kg-up` mounts `/home/kiro/.local/share/kiro-cli:ro`. The skill's path
   would not line up with the fork image, breaking credential pickup.
3. **Aliases never update.** `setup-alias`/`setup-codex` use `grep -Fq … && skip`, so
   when an alias *definition* changes the skill reports "already present" and leaves
   the stale line in place. The user requires `~/.zshrc` to auto add/remove/**update**.

There is also no guard against upstream drift reintroducing the 422, and no
post-start verification that the gateway actually works.

## Goals

- Build the gateway image locally from the fork, native to each host's CPU arch.
- Keep `init` / `update` / `rollback` / `status` / `setup-alias` / `setup-codex` /
  `remove-codex`, with rollback backed by git-SHA image tags (no registry).
- Guard the `role: str` fix on every build; re-apply from a tracked patch if an
  upstream sync dropped it; abort loudly if the patch will not apply.
- Verify the running gateway with a live HTTP 200 probe using the original failing
  payload shape (system role inside `messages[]`).
- Correct the mount path and run args to match the working `kg-up`.
- Reconcile the `~/.zshrc` aliases via a managed sentinel block (add/remove/update).
- Keep secrets out of the repo: keychain + prompt, reusing `store_proxy_key()`.
- Canonical build path owned by the skill; reuse an existing checkout via a symlink.

## Non-Goals

- Pushing images to a registry or multi-arch buildx. Each host builds its own arch;
  `python:3.10-slim` (the fork's base) is already multi-arch, so a local build
  produces the correct arch automatically.
- Cross-host rollback. Rollback re-runs a previously built image **present on that
  host**; it does not fetch old images from anywhere.
- Changing the container's internal port (8000 is fixed by the app).
- Full dotfiles or machine bootstrap. This covers AI-agent glue only.

## Supersession

This reverses two decisions in `2026-06-03-kiro-gateway-skill-design.md`:

| Old decision | New decision | Why |
|---|---|---|
| Image = upstream `ghcr.io/jwadow/kiro-gateway`, pinned by digest | Image = local build from fork `herocwhsu/kiro-gateway`, tagged by git short SHA | Upstream lacks the `role: str` fix and reintroduces the 422 |
| "Building a custom Docker image" listed as a Non-Goal | Building locally is now the core mechanism | Required to carry the fix and to match host arch |

All other parts of the old spec (platform-aware data dir, state file location,
local-skill install pattern) still hold.

## Build-Path Resolution

One canonical path the whole skill references: `~/.agent-skills-setup/kiro-gateway`.

`init` prompts once (env `KIRO_GATEWAY_DIR` supplies the answer non-interactively):

```
Path to an existing kiro-gateway checkout
(blank = clone fresh into ~/.agent-skills-setup/kiro-gateway):
```

- **Blank** → `git clone git@github.com:herocwhsu/kiro-gateway.git` into the canonical
  path (a real directory). Self-contained; assumes nothing about host layout.
- **A path** (e.g. `~/Project/kiro-gateway`) → expand to absolute, then
  `ln -s <target> ~/.agent-skills-setup/kiro-gateway`. This host reuses the existing
  checkout; no second copy.

All downstream steps (fix-guard, build, `update` pull) operate on the canonical path
and follow the symlink transparently.

Edge cases:

| Case | Behavior |
|---|---|
| Input is `~`/relative | Expand to absolute before symlinking |
| Target missing or not a git repo | Fail loud, re-prompt; never create a dangling link |
| Target remote ≠ `herocwhsu/kiro-gateway` | Warn, allow (differently-named clone permitted) |
| Canonical path is an existing symlink | Re-point to the new target |
| Canonical path is a real dir with content | Refuse to clobber; instruct to remove it or pass a path |
| Non-interactive (`KIRO_GATEWAY_DIR` set) | Use it as the answer; no prompt |

`status` reports which form is in use: `linked → /abs/target` vs `cloned`.

## Image Build & Rollback

| Field | Value |
|---|---|
| Source repo | `git@github.com:herocwhsu/kiro-gateway.git` |
| Base image | `python:3.10-slim` (multi-arch → native build per host) |
| Local tag | `kiro-gateway:<git-short-sha>` |
| State file | `~/.agent-skills-setup/kiro-gateway.state` (`current=<sha>`, `previous=<sha>`) |

- `init`: resolve build path → fix-guard → `docker build -t kiro-gateway:<sha>` →
  start container → health probe. Records `current=<sha>`.
- `update`: `git pull` in the build path → fix-guard → rebuild at new SHA → if SHA
  changed, stop/rm old container, restart at new tag, set `previous=<old>` /
  `current=<new>`.
- `rollback`: require `previous`; if `kiro-gateway:<previous>` image exists on host,
  stop/rm and restart it, swap current/previous. If the image was pruned, fail loud
  with the tag name — no silent no-op.

## Fix-Guard

Run before every build:

1. Assert `role: str` in `kiro/models_anthropic.py` of the build path.
2. If absent (upstream sync dropped it), apply tracked
   `skills/infra/kiro-gateway/patches/kiro-gateway-system-role.patch`.
3. If the patch does not apply cleanly, **abort before building** — never start a
   container from known-broken code.

## Container Configuration

Match the working `kg-up`:

```
docker run -d \
  --name kiro-gateway \
  --restart unless-stopped \
  -p 127.0.0.1:7788:8000 \
  --env-file ~/.env.kiro-gateway \
  -v "<kiro-data-dir>:/home/kiro/.local/share/kiro-cli:ro" \
  -v ~/kiro-gateway-logs:/app/debug_logs \
  kiro-gateway:<sha> \
  python main.py
```

`<kiro-data-dir>` from the existing platform switch: macOS
`~/Library/Application Support/kiro-cli`, Linux `~/.local/share/kiro-cli`.
`~/.env.kiro-gateway` is rendered from the keychain value (see Secrets); the
debug-logs dir is created `chmod 755` before the run to avoid the container-side
chown-on-mount failure seen on Docker Desktop.

## Health Probe

After start, POST the original failing shape and require HTTP 200:

```
POST http://127.0.0.1:7788/v1/messages
{ "model": "claude-sonnet-4-20250514", "max_tokens": 32,
  "messages": [ {"role":"user","content":"ping"},
                {"role":"system","content":"be terse"} ] }
```

Non-200 → print `docker logs` tail and exit non-zero. This is the end-to-end proof
the fix is live in the running container, not merely present on disk.

## Managed zshrc Block

Replace `grep && skip` in `setup-alias`/`setup-codex` with a reconciled block:

```
# >>> agent-skills-setup kiro-gateway >>>
alias claude-kiro='ANTHROPIC_BASE_URL=http://localhost:7788 ANTHROPIC_API_KEY=<read_cmd> claude'
alias hermes-kiro='...'
alias codex-kiro='CODEX_HOME="$HOME/.codex-kiro" KIRO_PROXY_KEY=<read_cmd> codex --profile kiro'
# <<< agent-skills-setup kiro-gateway <<<
```

All three aliases live in **one** managed block. `setup-alias` reconciles the
`claude-kiro`/`hermes-kiro` lines; `setup-codex` reconciles the `codex-kiro` line;
each inserts-or-updates only its own lines and leaves the others intact. On every run
the block is rewritten from source between the sentinels, so changed definitions
actually update. Content outside the markers is never touched. `<read_cmd>` is the
inline keychain lookup — no secret value is written to the file. `remove-codex`
removes only the `codex-kiro` line; if that leaves the block empty, the whole block
(both sentinels) is removed.

## Secrets

Unchanged mechanism: `store_proxy_key()` writes the proxy key to the macOS keychain
(`security`) or `secret-tool` (Linux), and emits the inline read command used in the
aliases. Additionally, `~/.env.kiro-gateway` is rendered from the keychain value at
`chmod 600` for the container's `--env-file`. The repo ships only a
`.env.kiro-gateway.example` with placeholders; no secret value is committed.

## Testing

- `shellcheck` on the modified `lib/kiro-gateway.sh`.
- **Idempotency:** run `setup-alias` twice → managed block count stays 1, second run
  produces no diff.
- **Managed block:** seed `~/.zshrc` with the sentinels plus surrounding lines;
  assert surrounding lines survive an update *and* a full removal; assert a changed
  alias definition is actually rewritten.
- **Build-path resolution:** blank input clones to canonical; a path input creates a
  symlink; an existing symlink re-points; a real dir refuses to clobber; a
  non-git/missing target fails without leaving a dangling link.
- **Fix-guard (unit):** temp repo with strict `Literal` → patch re-applies and the
  build proceeds; a patch that will not apply aborts before build.
- **`--dry-run`:** prints planned file writes, symlink, build tag, and run command
  without executing.

## Defaults Chosen

- Canonical build path `~/.agent-skills-setup/kiro-gateway`; override/reuse via the
  `init` prompt or `KIRO_GATEWAY_DIR`.
- Fix-guard runs on every `init`/`update` (cheap insurance against silent drift).
