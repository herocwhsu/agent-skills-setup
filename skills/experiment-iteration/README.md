# experiment-iteration

Guides structured hypothesis testing and learning loops for exploratory work.

## When to use

Use this skill for any task where the correct answer is not known upfront:

- AI/ML model quality improvement
- Prompt engineering
- Retrieval, ranking, or recommendation changes
- Evaluation design
- Data quality investigation
- Product discovery and A/B testing
- Automation experiments
- Workflow optimization

## Prerequisites

The repo must have:

- `docs/ai-learning-charter.md` — defines the learning mindset and required experiment fields
- `docs/experiment-template.md` — the template used for each experiment file

If these are missing, copy them from `agent-skills-setup/docs/`.

## Usage

```
/experiment-iteration
```

The skill will:

1. Ask for a short experiment slug
2. Load or create `docs/experiments/YYYY-MM-DD-<slug>.md`
3. Guide you through hypothesis, success criteria, abandon criteria, and smallest test before running
4. Guide you through result, learning, and decision after running
5. Run a productionization check if the decision is `Ship`

## Output

Each experiment produces a file at:

```
docs/experiments/YYYY-MM-DD-<slug>.md
```

## Installing in a repo

This skill is `local-optional`. To enable it in a repo:

1. Copy `docs/ai-learning-charter.md` and `docs/experiment-template.md` from
   `agent-skills-setup/docs/` into the target repo's `docs/` directory.
2. The skill is already installed globally via `agent-skills-setup`. No
   additional install step is needed.

## Relationship to production workflow

Exploratory work may move quickly. When an experiment decision is `Ship`,
return to the spec-gated workflow before merging to production.
