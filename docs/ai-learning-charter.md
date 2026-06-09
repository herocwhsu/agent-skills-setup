# AI Learning Charter

## Principle

Speed of learning is more important than speed of development.

The goal is not only to implement solutions quickly. The goal is to shorten the loop between:

```text
Hypothesis → Experiment → Result → Learning → Decision
```

For exploratory work, progress is measured by how quickly the team can test assumptions, learn from results, and make better next decisions.

---

## When This Charter Applies

Use this charter for exploratory or uncertainty-heavy work, including:

* AI/ML model quality improvement
* Prompt engineering
* Retrieval, ranking, or recommendation changes
* Evaluation design
* Data quality investigation
* Product discovery
* A/B testing
* Automation experiments
* Workflow optimization
* Any task where the correct answer is not known upfront

This charter does not replace production engineering rules, security review, permission checks, test requirements, or production spec gates.

When exploratory work becomes production-bound, follow the production workflow.

---

## Core Mindset

Do not optimize only for implementation speed.

Optimize for:

* Fast hypothesis testing
* Clear success and abandon criteria
* Reproducible results
* Documented learnings
* Better next decisions

A failed experiment is useful if it narrows the hypothesis space.

A successful implementation is weak if it does not clarify what was learned.

---

## Leading vs. Lagging Indicators

### Lagging Indicators

Lagging indicators describe final outcomes. They are important, but usually not directly controllable in a single iteration.

Examples:

* Model accuracy
* Hallucination rate
* Task success rate
* False positive / false negative rate
* User engagement
* Revenue impact
* Support ticket reduction
* Customer adoption
* Production incident reduction

### Leading Indicators

Leading indicators describe actions or conditions that can be directly improved.

Examples:

* Number of hypotheses tested
* Experiment velocity
* Time from hypothesis to result
* Number of failure cases analyzed
* Number of evaluation cases added
* Number of data quality issues found
* Reproducibility of experiments
* Percentage of experiments with documented learnings
* Percentage of experiments with clear success and abandon criteria
* Time spent waiting for compute, data, review, or deployment

Prefer leading indicators when deciding what to do next.

---

## Required Experiment Fields

Each experiment should define:

* Problem
* Hypothesis
* Expected outcome
* Success criteria
* Abandon criteria
* Metrics to observe
* Smallest test or implementation
* Result
* Learning
* Decision
* Next experiment

Do not run an experiment without a clear hypothesis and expected outcome.

Do not close an experiment without recording the actual result and learning.

---

## Hypothesis Format

Prefer this format:

```text
We believe that [change] will improve [metric] because [reason].
```

Examples:

```text
We believe that adding camera-model-specific examples will reduce false alarms because the current prompt treats all scenes as visually equivalent.
```

```text
We believe that reranking retrieved documents by recency will improve answer correctness because stale documents are currently being selected over newer policy updates.
```

```text
We believe that splitting onboarding into smaller steps will improve activation because users are dropping off before reaching the first successful setup.
```

---

## Success and Abandon Criteria

Each experiment should define both success and abandon criteria before implementation.

### Success Criteria

Success criteria describe what result would justify continuing, shipping, or scaling the approach.

Examples:

* Hallucination rate decreases by at least 20% on the evaluation set
* False positive rate improves without increasing false negatives
* Task completion rate improves by 5%
* Latency stays below the acceptable threshold
* The new approach passes all regression cases
* Users complete the workflow with fewer support requests

### Abandon Criteria

Abandon criteria describe when to stop investing in the approach.

Examples:

* No measurable improvement after three focused experiments
* Improvement only appears on handpicked examples
* Accuracy improves but latency or cost becomes unacceptable
* Result cannot be reproduced
* Required data is unavailable or too expensive to maintain
* The change increases risk to permissions, privacy, or data correctness

---

## Smallest Test Rule

Use the smallest test that can validate or invalidate the hypothesis.

Prefer:

* Offline evaluation before production rollout
* Local prototype before production integration
* Manual review before automation
* Small dataset before full dataset
* One workflow before all workflows
* One customer segment before all customers
* One reversible change before a permanent migration

Avoid large implementations that do not produce learning until the end.

---

## Decision Rules

At the end of each iteration, choose one decision:

### Continue

Use when the hypothesis is promising and needs more testing.

### Pivot

Use when the result partially supports the direction, but the assumption or implementation should change.

### Abandon

Use when the result disproves the hypothesis, cannot be reproduced, or the cost/risk is too high.

### Ship

Use when the result meets success criteria and the risk is acceptable.

Do not choose `Ship` only because the implementation is complete.

Choose `Ship` only when evidence supports it.

---

## Iteration Review Questions

After each iteration, ask:

* Did the result match the expected outcome?
* What did we learn?
* Which assumption became stronger or weaker?
* What should we test next?
* What slowed down the learning loop?
* Are the results reproducible?
* Did we add useful regression or evaluation coverage?
* Did the experiment introduce new security, permission, data, cost, or latency risk?

---

## Documentation Standard

Experiment notes should be brief but decision-useful.

Good documentation includes:

* What was tested
* Why it was tested
* What result was expected
* What actually happened
* What was learned
* What decision was made
* What should happen next

Avoid vague summaries such as:

```text
Tested prompt changes. Results mixed.
```

Prefer:

```text
Tested adding three camera-model-specific examples to the false alarm prompt. Expected false positives to drop on night scenes. False positives improved from 18% to 12%, but false negatives increased from 4% to 9%. Decision: pivot. Next test should preserve the examples but add stricter detection thresholds for low-confidence cases.
```

---

## Relationship to Engineering Rules

This charter complements engineering rules.

It must not bypass:

* Permission checks
* Security review
* Data safety
* Code review
* Automated tests
* Production spec gates
* API contract review
* Migration review
* Observability requirements

Exploratory work may move quickly only when it is clearly marked, reversible, non-production-facing, and documented.

Productionization requires normal production workflow.
