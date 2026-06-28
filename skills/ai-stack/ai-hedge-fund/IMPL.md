---
name: ai-stack-ai-hedge-fund
description: Use when running AI-powered stock analysis with multiple famous investor agents (Buffett, Munger, Damodaran, Ackman, etc.). Each agent analyzes fundamentals, sentiment, and technicals independently, then a portfolio manager makes final trading decisions. Educational/research use — not for real trading.
---

# ai-hedge-fund

Multi-agent AI hedge fund using LangGraph. 13 investor persona agents + risk manager + portfolio manager analyze stocks and generate trading signals.

Repo: `/home/top/projects/ai-hedge-fund` (fork of `virattt/ai-hedge-fund`, synced to upstream)

## When to use

- Research how famous investors would analyze a stock
- Generate multi-perspective trading signals for TWSE stocks
- Backtest AI-driven strategies against historical data
- Extend the robots project with AI investment analysis

## Install

```bash
cd /home/top/projects/ai-hedge-fund
pip install poetry
poetry install
cp .env.example .env
# Add API keys to .env
```

## Required API keys

```bash
# Minimum (financial data)
FINANCIAL_DATASETS_API_KEY=...   # from financialdatasets.ai

# LLM — pick one:
ANTHROPIC_API_KEY=...            # Claude (recommended)
OPENAI_API_KEY=...               # GPT-4
OPENROUTER_API_KEY=...           # already in robots .env.prod (free models available)
```

## Run

```bash
cd /home/top/projects/ai-hedge-fund

# Interactive CLI — pick tickers + date range
poetry run python src/main.py

# Backtest
poetry run python src/backtester.py

# v2 pipeline (more modular)
poetry run python -m v2.backtesting --help
poetry run python -m v2.event_study --help
```

## Investor agents available

| Agent | Style |
|---|---|
| Warren Buffett | Value — wonderful companies at fair price |
| Charlie Munger | Quality businesses, mental models |
| Aswath Damodaran | Disciplined DCF valuation |
| Ben Graham | Deep value, margin of safety |
| Bill Ackman | Activist, concentrated positions |
| Cathie Wood | Disruptive innovation, growth |
| Michael Burry | Contrarian, deep value |
| Peter Lynch | Ten-baggers in everyday businesses |
| Stanley Druckenmiller | Macro, asymmetric opportunities |
| Nassim Taleb | Tail risk, antifragility |
| + Fundamentals, Sentiment, Technicals, Risk Manager, Portfolio Manager |

## Key paths

| Path | Purpose |
|---|---|
| `src/agents/` | Individual investor agent implementations |
| `src/graph/` | LangGraph workflow wiring all agents |
| `src/data/` | Financial data client (financialdatasets.ai) |
| `v2/` | Modular v2 pipeline with backtesting + event study |
| `v2/signals/` | Signal generation (PEAD and more) |
| `v2/backtesting/` | Full backtesting engine |
| `v2/event_study/` | Event study analysis |

## Integration with robots project

- TWSE stocks (2330, 2317, 2454, 8996) already tracked in robots SQLite DB
- CAPE + Buffett indicator data available — can feed as context to agents
- News articles (833+ classified) can feed into Sentiment agent
- Run analysis on demand, surface results via robots `/api/v1/insights` endpoint

## Sync upstream

```bash
cd /home/top/projects/ai-hedge-fund
git fetch upstream
git merge upstream/main --no-edit
git push origin main
```
