---
name: ai-stack-memu
description: Use when adding persistent workspace memory to an AI agent. memU compiles any workspace (docs, code, chat logs, images, audio) into three durable layers — INDEX.md, MEMORY.md, SKILL.md — so agents have context, continuity, and control across sessions. Supports Claude, OpenAI, OpenRouter, and local models.
---

# memU

memU is a workspace runtime for AI agents. It turns any file system into structured agent memory with three layers:

- **INDEX.md** — navigable map across everything the agent knows
- **MEMORY.md** — living memory: user profile, preferences, goals, events
- **SKILL.md** — learned skills and tool patterns

Repo: `/home/top/projects/memU` (fork of `NevaMind-AI/memU`, synced to upstream)

## When to use

- Agent needs persistent memory across sessions
- Want to reduce token cost by 95% via workspace-indexed retrieval
- Building a 24/7 proactive agent (like this Claude Code setup)
- Need multi-modal memory (text, images, audio, video, documents)

## Install

```bash
cd /home/top/projects/memU
pip install uv
uv sync
# or install as package:
pip install memu-py
```

## Quick start

```python
from memu import MemU

mem = MemU(
    llm_backend="claude",          # or "openai", "openrouter"
    embedding_backend="openai",    # or "voyage", "jina", "openrouter"
    workspace_path="./workspace",
)

# Memorize a conversation
await mem.memorize(messages=[...])

# Retrieve relevant memory
results = await mem.retrieve(query="what did we discuss about deployment?")
```

## Key modules

| Module | Purpose |
|---|---|
| `src/memu/app/memorize.py` | Core memorize pipeline |
| `src/memu/app/retrieve.py` | Semantic retrieval |
| `src/memu/memory_fs/` | INDEX/MEMORY/SKILL file synthesis |
| `src/memu/embedding/` | Embedding backends (OpenAI, Voyage, Jina, OpenRouter) |
| `src/memu/llm/` | LLM backends (Claude, OpenAI, DeepSeek, Kimi) |
| `src/memu/vlm/` | Vision-language backends for image/video memory |
| `src/memu/preprocess/` | Audio, video, document, image ingestion |

## Supported LLM backends

- `claude` — Anthropic Claude (uses `ANTHROPIC_API_KEY`)
- `openai` — OpenAI (uses `OPENAI_API_KEY`)
- `openrouter` — OpenRouter (uses `OPENROUTER_API_KEY` — already in robots `.env.prod`)
- `deepseek`, `kimi`, `minimax`

## Integration with this host

- OpenRouter key already available in `/home/top/projects/robots/config/env/.env.prod`
- Can be wired into the robots backend as a memory layer for news/insight agents
- Pairs naturally with the Claude Code memory system in this repo

## Sync upstream

```bash
cd /home/top/projects/memU
git fetch upstream
git merge upstream/main --no-edit
git push origin main
```
