---
name: experiment-iteration
description: Use for AI/ML, prompt engineering, product discovery, model-quality improvement, retrieval/ranking, evaluation design, automation experiments, or any exploratory task where the correct solution is uncertain upfront. Guides hypothesis → experiment → result → learning → decision loops using the repo's learning charter and experiment template.
---

# experiment-iteration

Guides the team through structured hypothesis testing and learning loops for
exploratory work. Applies when the correct answer is not known upfront.

## When to Use

- AI/ML model quality improvement
- Prompt engineering and evaluation design
- Retrieval, ranking, or recommendation changes
- Data quality investigation
- Product discovery and A/B testing
- Automation experiments
- Workflow optimization
- Any task where the correct solution requires testing assumptions first

This skill does not apply to production feature implementation. When
exploratory work is ready to ship to production, return to the spec-gated
workflow.

## Slash Command

| Slash command | What it does |
|---|---|
| `/experiment-iteration` | Start or continue an experiment. Loads the charter and template, guides you through all required fields, and produces a filled experiment file. |

## How It Works

1. **Load the charter** — read `docs/ai-learning-charter.md` in the current
   repo. If not found, fall back to `~/.claude/docs/ai-learning-charter.md`.
   If neither exists, tell the user and stop.

2. **Load the template** — read `docs/experiment-template.md` in the current
   repo. If not found, fall back to `~/.claude/docs/experiment-template.md`.

3. **Identify the experiment** — ask the user for a short slug (e.g.
   `false-alarm-camera-examples`). Use it to derive the output path:
   `docs/experiments/YYYY-MM-DD-<slug>.md`

4. **Resume or start** — if the output file already exists, load it and ask
   which section to update. Otherwise start from section 1.

5. **Guide through required fields** — work through the template sections in
   order. Required fields before running an experiment:
   - Problem
   - Hypothesis (must follow `We believe that [change] will improve [metric] because [reason]`)
   - Success criteria (measurable or observable)
   - Abandon criteria
   - Smallest test

   Required fields before closing an experiment:
   - Result (with before/after metrics)
   - Learning
   - Decision (Continue / Pivot / Abandon / Ship)
   - Next experiment

6. **Enforce the smallest test rule** — if the proposed test is large or
   deferred, flag it and suggest a smaller reversible alternative.

7. **Save the file** — write or update `docs/experiments/YYYY-MM-DD-<slug>.md`.

8. **Productionization check** — if the decision is `Ship`, run through the
   productionization checklist from the charter. If any production surface is
   affected, tell the user to return to the spec-gated workflow before merging.

## Leading vs Lagging Indicators

The charter distinguishes:

- **Lagging**: model accuracy, hallucination rate, user engagement — important
  but not directly controllable in a single iteration.
- **Leading**: hypotheses tested, experiment velocity, failure cases analyzed,
  evaluation cases added — these are what to optimize during exploratory work.

When the user asks "why isn't accuracy improving?", reframe to: "what is
preventing us from running more experiments?"

## Relationship to Other Workflows

This skill is a complement to the production spec-gated workflow, not a
replacement. Exploratory work may move quickly only when it is:

- Clearly marked as an experiment
- Reversible and non-production-facing
- Documented with hypothesis and result

Productionization requires returning to the spec-gated workflow.
