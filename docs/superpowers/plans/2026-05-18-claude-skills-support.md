# Claude Code Skills Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the four local skills (fetch-page-to-markdown, fetch-jira-story, plan-story, create-story-tasks) work for Claude Code without breaking Kiro, by replacing hardcoded `~/.kiro/skills/` paths with runtime-detected paths and adding dual sub-skill invocation instructions.

**Architecture:** Approach A — runtime detection in skill files. Each skill file gains a shell snippet that searches known skills dirs for `html2md.py`, and sub-skill invocation sections get dual instructions (Claude Code: Skill tool; Kiro: read file path). No changes to install infrastructure; symlinks keep working.

**Tech Stack:** Bash, Python 3, Markdown

---

## Files to Modify

- `skills/fetch-page-to-markdown/SKILL.md` — fix 3 hardcoded `~/.kiro/skills/` references
- `skills/fetch-jira-story/SKILL.md` — fix 2 hardcoded `~/.kiro/skills/` references
- `skills/plan-story/SKILL.md` — fix 2 sub-skill invocation lines
- `skills/create-story-tasks/SKILL.md` — fix 1 sub-skill invocation line
- `README.md` — document Claude Code support in Supported Agents table and Quick Start
- `skills/fetch-page-to-markdown/README.md` — update html2md.py path note if present

---

### Task 1: Fix fetch-page-to-markdown/SKILL.md

**Files:**
- Modify: `skills/fetch-page-to-markdown/SKILL.md`

Three hardcoded paths to fix:
1. Line ~72: credential verify example uses `~/.kiro/skills/../../../Project/agent-skills-setup/scripts/setup-credentials.sh`
2. Line ~124: Python subprocess call uses `~/.kiro/skills/fetch-page-to-markdown/html2md.py`
3. Line ~147: plain curl pipe uses `python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py`

- [ ] **Step 1: Replace the credential verify example**

In `skills/fetch-page-to-markdown/SKILL.md`, find:

```
**Verify credential is stored (without revealing it):**
```bash
bash ~/.kiro/skills/../../../Project/agent-skills-setup/scripts/setup-credentials.sh confluence verify
# or directly:
[ -n "$(security find-generic-password -s 'agent-skills:confluence-example-org-com' -a '<user>' -w 2>/dev/null)" ] \
  && echo "✓ credential found" || echo "✗ not found"
```
```

Replace with:

```
**Verify credential is stored (without revealing it):**
```bash
# Run from your agent-skills-setup repo:
bash /path/to/agent-skills-setup/scripts/setup-credentials.sh confluence verify
# or directly:
[ -n "$(security find-generic-password -s 'agent-skills:confluence-example-org-com' -a '<user>' -w 2>/dev/null)" ] \
  && echo "✓ credential found" || echo "✗ not found"
```
```

- [ ] **Step 2: Replace the Python subprocess html2md.py call**

Find:

```python
result = subprocess.run(
    ['python3', os.path.expanduser('~/.kiro/skills/fetch-page-to-markdown/html2md.py')],
    stdin=open('/tmp/_cf_body.html'), capture_output=True, text=True
)
```

Replace with:

```python
import glob as _glob
_candidates = _glob.glob(os.path.expanduser('~/.**/fetch-page-to-markdown/html2md.py'), recursive=True)
_html2md = next((p for p in _candidates if os.path.isfile(p)), None)
if not _html2md:
    raise FileNotFoundError("html2md.py not found in any agent skills directory")
result = subprocess.run(
    ['python3', _html2md],
    stdin=open('/tmp/_cf_body.html'), capture_output=True, text=True
)
```

- [ ] **Step 3: Replace the plain curl pipe html2md.py reference**

Find:

```bash
curl -s "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"

# With auth (Basic Auth) — read and unset immediately:
_PASS=$(security find-generic-password -s "agent-skills:<service-slug>" -a "<username>" -w 2>/dev/null)
curl -s -u "<username>:$_PASS" "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
unset _PASS
```

Replace with:

```bash
# Detect html2md.py location across agent skills dirs
_HTML2MD=""
for _d in "$HOME/.kiro/skills" "$HOME/.claude/skills"; do
  [[ -f "$_d/fetch-page-to-markdown/html2md.py" ]] && { _HTML2MD="$_d/fetch-page-to-markdown/html2md.py"; break; }
done
[[ -z "$_HTML2MD" ]] && { echo "ERROR: html2md.py not found" >&2; exit 1; }

curl -s "$URL" | python3 "$_HTML2MD" \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"

# With auth (Basic Auth) — read and unset immediately:
_PASS=$(security find-generic-password -s "agent-skills:<service-slug>" -a "<username>" -w 2>/dev/null)
curl -s -u "<username>:$_PASS" "$URL" | python3 "$_HTML2MD" \
  > "./docs/pre-specs/${DATE}-${SLUG}-reference.md"
unset _PASS
```

- [ ] **Step 4: Verify no remaining `~/.kiro` references**

```bash
grep -n "kiro" /Users/<user>/Project/agent-skills-setup/skills/fetch-page-to-markdown/SKILL.md
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add skills/fetch-page-to-markdown/SKILL.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "fix: make fetch-page-to-markdown skill agent-agnostic"
```

---

### Task 2: Fix fetch-jira-story/SKILL.md

**Files:**
- Modify: `skills/fetch-jira-story/SKILL.md`

Two hardcoded paths to fix:
1. Line ~27: credential setup uses `~/.kiro/skills/../../../agent-skills-setup/scripts/credentials/jira.sh`
2. Line ~119: Apidog/other URL pipe uses `python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py`

- [ ] **Step 1: Replace the credential setup path**

Find:

```bash
# Store (one-time):
bash ~/.kiro/skills/../../../agent-skills-setup/scripts/credentials/jira.sh add
# e.g. https://example-org.atlassian.net → slug: jira-example-atlassian-net

# Verify (safe — no value printed):
bash ~/.kiro/skills/../../../agent-skills-setup/scripts/credentials/jira.sh verify
```

Replace with:

```bash
# Store (one-time) — run from your agent-skills-setup repo:
bash /path/to/agent-skills-setup/scripts/credentials/jira.sh add
# e.g. https://example-org.atlassian.net → slug: jira-example-atlassian-net

# Verify (safe — no value printed):
bash /path/to/agent-skills-setup/scripts/credentials/jira.sh verify
```

- [ ] **Step 2: Replace the html2md.py pipe reference**

Find:

```bash
URL="https://..."
SLUG=$(echo "$URL" | sed 's|.*://||;s/[^a-z0-9]/-/g' | cut -c1-40)
curl -s "$URL" | python3 ~/.kiro/skills/fetch-page-to-markdown/html2md.py \
  > "./docs/stories/$STORY_ID/apidog-${SLUG}.md"
```

Replace with:

```bash
URL="https://..."
SLUG=$(echo "$URL" | sed 's|.*://||;s/[^a-z0-9]/-/g' | cut -c1-40)

# Detect html2md.py location across agent skills dirs
_HTML2MD=""
for _d in "$HOME/.kiro/skills" "$HOME/.claude/skills"; do
  [[ -f "$_d/fetch-page-to-markdown/html2md.py" ]] && { _HTML2MD="$_d/fetch-page-to-markdown/html2md.py"; break; }
done
[[ -z "$_HTML2MD" ]] && { echo "ERROR: html2md.py not found" >&2; exit 1; }

curl -s "$URL" | python3 "$_HTML2MD" \
  > "./docs/stories/$STORY_ID/apidog-${SLUG}.md"
```

- [ ] **Step 3: Verify no remaining `~/.kiro` references**

```bash
grep -n "kiro" /Users/<user>/Project/agent-skills-setup/skills/fetch-jira-story/SKILL.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add skills/fetch-jira-story/SKILL.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "fix: make fetch-jira-story skill agent-agnostic"
```

---

### Task 3: Fix plan-story/SKILL.md

**Files:**
- Modify: `skills/plan-story/SKILL.md`

Two sub-skill invocation lines reference Kiro file paths. Replace each with dual instructions.

- [ ] **Step 1: Replace the brainstorming sub-skill invocation**

Find:

```
Read `~/.kiro/skills/brainstorming/SKILL.md` and follow it.
```

Replace with:

```
**Invoke brainstorming sub-skill:**
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:brainstorming`
- **Kiro:** Read `~/.kiro/skills/brainstorming/SKILL.md` and follow it
```

- [ ] **Step 2: Replace the writing-plans sub-skill invocation**

Find:

```
Read `~/.kiro/skills/writing-plans/SKILL.md` and follow it.
```

Replace with:

```
**Invoke writing-plans sub-skill:**
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:writing-plans`
- **Kiro:** Read `~/.kiro/skills/writing-plans/SKILL.md` and follow it
```

- [ ] **Step 3: Verify no remaining bare `~/.kiro` references**

```bash
grep -n "kiro" /Users/<user>/Project/agent-skills-setup/skills/plan-story/SKILL.md
```

Expected: no output (the replacement text contains `~/.kiro` only inside the Kiro-specific bullet, which is correct).

- [ ] **Step 4: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add skills/plan-story/SKILL.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "fix: make plan-story skill agent-agnostic"
```

---

### Task 4: Fix create-story-tasks/SKILL.md

**Files:**
- Modify: `skills/create-story-tasks/SKILL.md`

One sub-skill reference to fix.

- [ ] **Step 1: Replace the using-git-worktrees reference**

Find:

```
**Read `using-git-worktrees` skill** for full worktree workflow:
`~/.kiro/skills/using-git-worktrees/SKILL.md`
```

Replace with:

```
**Invoke using-git-worktrees sub-skill** for full worktree workflow:
- **Claude Code:** Use the `Skill` tool with skill name `superpowers:using-git-worktrees`
- **Kiro:** Read `~/.kiro/skills/using-git-worktrees/SKILL.md` and follow it
```

- [ ] **Step 2: Verify no remaining bare `~/.kiro` references**

```bash
grep -n "kiro" /Users/<user>/Project/agent-skills-setup/skills/create-story-tasks/SKILL.md
```

Expected: no output (the replacement text contains `~/.kiro` only inside the Kiro-specific bullet).

- [ ] **Step 3: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add skills/create-story-tasks/SKILL.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "fix: make create-story-tasks skill agent-agnostic"
```

---

### Task 5: Verify Claude Code installation

- [ ] **Step 1: Run install script targeting Claude Code**

```bash
cd /Users/<user>/Project/agent-skills-setup && bash scripts/install.sh
# When prompted: choose option 2 (Claude Code)
```

Expected output includes:
```
  ✓ fetch-page-to-markdown
  ✓ fetch-jira-story
  ✓ plan-story
  ✓ create-story-tasks
```

- [ ] **Step 2: Verify symlinks exist**

```bash
ls -la ~/.claude/skills/fetch-page-to-markdown
ls -la ~/.claude/skills/fetch-jira-story
ls -la ~/.claude/skills/plan-story
ls -la ~/.claude/skills/create-story-tasks
```

Expected: each is a symlink pointing into `/Users/<user>/Project/agent-skills-setup/skills/`.

- [ ] **Step 3: Verify no `~/.kiro` paths remain in installed skill files (except inside Kiro-specific bullets)**

```bash
grep -rn "~/.kiro/skills" ~/.claude/skills/fetch-page-to-markdown/SKILL.md \
  ~/.claude/skills/fetch-jira-story/SKILL.md \
  ~/.claude/skills/plan-story/SKILL.md \
  ~/.claude/skills/create-story-tasks/SKILL.md
```

Expected: only lines that contain `- **Kiro:**` (the intentional Kiro-specific bullets). No bare path references.

- [ ] **Step 4: Verify html2md.py detection works**

```bash
python3 - <<'EOF'
import os, glob
candidates = glob.glob(os.path.expanduser('~/.*/fetch-page-to-markdown/html2md.py'))
print("Found:", candidates)
EOF
```

Expected: at least one path printed (from `~/.kiro/skills/` or `~/.claude/skills/`).

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Supported Agents table**

Find the existing table:

```markdown
| # | Agent | Skills directory |
|---|---|---|
| 1 | Kiro | `~/.kiro/skills/` |
| 2 | Claude Code | `~/.claude/skills/` |
| 3 | Gemini CLI | `~/.gemini/skills/` |
| 4 | All | all of the above |
```

Add a "Custom skills supported" column:

```markdown
| # | Agent | Skills directory | Custom skills |
|---|---|---|---|
| 1 | Kiro | `~/.kiro/skills/` | ✓ |
| 2 | Claude Code | `~/.claude/skills/` | ✓ |
| 3 | Gemini CLI | `~/.gemini/skills/` | ✓ |
| 4 | All | all of the above | — |
```

- [ ] **Step 2: Add a Claude Code note under Custom Skills section**

After the `fetch-page-to-markdown` description in the Custom Skills section, add:

```markdown
> **Claude Code users:** Sub-skill invocations use the `Skill` tool (e.g. `Skill("superpowers:brainstorming")`). The `html2md.py` converter is auto-detected from whichever agent skills directory is present.
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add README.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "docs: document Claude Code support for custom skills"
```

---

### Task 7: Update fetch-page-to-markdown/README.md

**Files:**
- Modify: `skills/fetch-page-to-markdown/README.md`

- [ ] **Step 1: Read current README**

```bash
cat /Users/<user>/Project/agent-skills-setup/skills/fetch-page-to-markdown/README.md
```

- [ ] **Step 2: Add agent compatibility note**

After the existing overview paragraph, add:

```markdown
## Agent Compatibility

Works with Kiro, Claude Code, and Gemini CLI. The `html2md.py` converter is located at install time by scanning `~/.kiro/skills/`, `~/.claude/skills/`, and `~/.gemini/skills/` in order — whichever is found first is used.
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/<user>/Project/agent-skills-setup add skills/fetch-page-to-markdown/README.md
git -C /Users/<user>/Project/agent-skills-setup commit -m "docs: add agent compatibility note to fetch-page-to-markdown README"
```
