# Experiment Template

Use this template for exploratory work, AI/ML iteration, product discovery, model-quality improvement, prompt changes, retrieval/ranking changes, automation experiments, or any task where the correct solution is uncertain.

---

## 1. Problem

What problem are we trying to improve?

```text
[Describe the problem clearly.]
```

Why does this matter?

```text
[Explain user impact, business impact, system risk, or learning value.]
```

---

## 2. Current Baseline

What is the current behavior or metric?

```text
[Record the current baseline.]
```

Evidence:

```text
[Link logs, examples, evaluation results, user reports, dashboards, tickets, or observations.]
```

---

## 3. Hypothesis

Use this format:

```text
We believe that [change] will improve [metric] because [reason].
```

Hypothesis:

```text
[Write the hypothesis.]
```

Key assumption:

```text
[What must be true for this hypothesis to work?]
```

---

## 4. Metrics

### Lagging Metric

The final outcome we care about:

```text
Metric:
Baseline:
Target:
```

Examples:

* Accuracy
* Hallucination rate
* False positive rate
* False negative rate
* Task success rate
* User engagement
* Revenue impact

### Leading Metrics

The actionable metrics we can influence during this iteration:

```text
Hypotheses tested:
Time from hypothesis to result:
Failure cases analyzed:
Evaluation cases added:
Data quality issues found:
Reproducibility:
Documented learnings:
Waiting time / blockers:
```

---

## 5. Expected Outcome

What do we expect to happen?

```text
[Describe the expected result.]
```

What result would surprise us?

```text
[Describe an unexpected result that would change our understanding.]
```

---

## 6. Success Criteria

This experiment succeeds if:

```text
-
-
-
```

Success should be measurable or observable.

Avoid vague criteria such as:

```text
Looks better.
Seems improved.
Works well.
```

---

## 7. Abandon Criteria

We stop or pivot away from this direction if:

```text
-
-
-
```

Examples:

* No measurable improvement
* Improvement is not reproducible
* Improvement only works on handpicked examples
* Regression appears in important cases
* Latency, cost, security, or data risk becomes unacceptable
* Required data is unavailable or unreliable

---

## 8. Smallest Test or Implementation

What is the smallest reversible test that can validate or invalidate the hypothesis?

```text
[Describe the smallest test.]
```

Scope:

```text
In scope:
-

Out of scope:
-
```

---

## 9. Test Plan

How will we evaluate the result?

```text
[Describe evaluation method.]
```

Test cases / dataset:

```text
[Describe test set, user segment, examples, or scenarios.]
```

Regression coverage:

```text
[Describe what must not break.]
```

---

## 10. Result

What actually happened?

```text
[Record actual result.]
```

Observed metrics:

```text
Before:
After:
Delta:
```

Evidence:

```text
[Link output, logs, screenshots, dashboards, evaluation files, PR, or test run.]
```

---

## 11. Learning

What did we learn?

```text
[Summarize learning.]
```

Which assumption became stronger?

```text
[Describe strengthened assumption.]
```

Which assumption became weaker?

```text
[Describe weakened assumption.]
```

What remains uncertain?

```text
[Describe remaining uncertainty.]
```

---

## 12. Decision

Choose one:

```text
Continue
Pivot
Abandon
Ship
```

Decision:

```text
[Choose one.]
```

Reason:

```text
[Explain why.]
```

Decision meanings:

* **Continue** — the hypothesis is promising and needs more testing.
* **Pivot** — the result partially supports the direction, but assumptions need adjustment.
* **Abandon** — the result disproves the hypothesis or cost/risk is too high.
* **Ship** — the result meets success criteria and risk is acceptable.

---

## 13. Next Experiment

What should we test next?

```text
[Describe next hypothesis or next test.]
```

Why this next?

```text
[Explain why this is the highest-learning next step.]
```

---

## 14. Blockers and Learning Loop Friction

What slowed down the experiment?

```text
-
-
-
```

Examples:

* Waiting for data
* Waiting for compute
* Waiting for review
* Missing evaluation cases
* Slow deployment
* Unclear ownership
* Poor observability
* Non-reproducible setup
* Manual analysis overhead

How can we reduce this friction next time?

```text
-
-
-
```

---

## 15. Productionization Check

Does this change affect production behavior?

```text
Yes / No
```

If yes, check whether it affects:

```text
External contracts:
API behavior:
Permissions:
Data models:
Data correctness:
Security behavior:
Production behavior:
Migration behavior:
User-visible behavior:
```

If any answer is yes, return to the production spec-gated workflow before shipping.
