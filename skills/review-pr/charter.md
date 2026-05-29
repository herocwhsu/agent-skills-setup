# Code Review Playbook

A lightweight checklist for reviewing PRs. Focus on issues that can affect correctness, security, data consistency, maintainability, or future changes. Avoid blocking PRs on subjective style preferences.

## Review Priority

Use prefixes when helpful:

```text
blocking:
important:
question:
suggestion:
nit:
```

`nit:` means the comment is optional and should not block the PR.

Prioritize review comments in this order:

1. Correctness bugs
2. Permission or security issues
3. Data consistency and transaction risks
4. Broken API behavior or error handling
5. Missing tests for high-risk logic
6. Architecture or layering problems
7. Naming that may cause misunderstanding
8. Style or formatting nits

## Correctness

Check for:

- Nil pointer dereference risks
- Missing error checks
- Ignored return values
- Incorrect early returns
- Off-by-one errors
- Timezone or time-window boundary issues
- SQL placeholder / argument count mismatch
- Non-deterministic output where stable output matters

Ask:

```text
Can this panic?
Can this return the wrong result?
Can this behave differently on retry or rerun?
```

## Permission and Security

Check for:

- Operator company vs target company confusion
- User-provided IDs being treated as trusted
- Missing permission checks in alternate branches
- Optional fields causing permission checks to return too early
- Identity fields being accepted from request body
- Webhook or callback handlers without idempotency
- Missing HTML escaping in email or HTML content

Important rule:

```text
Missing optional input should not automatically mean invalid input.
It may only mean the current permission branch does not apply.
```

Be careful with names like:

```go
validatedCompanyID
authorizedUser
trustedInput
```

Only use those names after the value has actually been validated or authorized.

## Transaction and Side Effects

Check for:

- `Commit()` error being ignored
- Rollback not handled
- Shadowed transaction/context variables
- External API calls inside DB transactions
- Emails or notifications sent before DB commit
- Side effects that cannot be rolled back
- Retry behavior that may duplicate external actions

Recommended rule:

```text
DB changes should commit before sending emails, notifications, webhooks, or external API calls.
```

Ask:

```text
What happens if this request, callback, or job runs twice?
```

## Error Handling

Check for:

- Logging an error and then returning `nil`
- Validation errors becoming 500 instead of 400
- Not-found cases becoming 500 instead of 404
- Permission errors becoming 500 instead of 403
- Repository not-found behavior being inconsistent
- Sentinel errors not wrapped correctly

Avoid this unless the operation is explicitly best-effort:

```go
if err != nil {
    log.Error().Err(err).Msg("failed")
    return nil
}
```

Prefer:

```go
if err != nil {
    return err
}
```

## Architecture and Layering

General guideline:

- **Controller**: request binding, auth/context extraction, response mapping
- **Service**: business rules, permission checks, transaction orchestration
- **Repository**: SQL/database access, data persistence

Watch for:

- Controller doing complex business logic
- Repository making permission decisions
- Service leaking HTTP-specific behavior
- Helpers with hidden DB writes or external calls
- Function names that hide side effects

If a function sends email, calls SAP, writes DB, or triggers a webhook, the name should make that clear.

## Naming

Do not block PRs on subjective naming preferences.

However, naming is **not** a nit when it affects correctness, domain meaning, or future maintainability.

A naming comment is important when:

- The name implies a value is validated, but it is still user input
- The name implies a permission check is broader or narrower than it really is
- Multiple IDs are collapsed into generic names like `companyID`
- The name hides an external side effect
- The same term means different things in different places

Example:

```go
validatedCompanyID := input.CompanyID
```

If the value has not passed validation yet, prefer:

```go
requestedCompanyID := input.CompanyID
targetCompanyID := input.CompanyID
```

Good review comment:

```text
important: validatedCompanyID is misleading here because this value has
not passed permission validation yet. Please rename it to targetCompanyID
or requestedCompanyID so future code does not treat user input as trusted.
```

## Testing

High-risk logic should have tests.

Prioritize tests for:

- Permission branches
- Transaction rollback behavior
- External API failure handling
- Retry and idempotency behavior
- Timezone and date boundary logic
- Aggregation or allocation logic
- Empty result behavior
- Error mapping behavior

Generated mocks are not test coverage.

## Deterministic Output

If output is used for logs, external requests, tests, diffs, or audit trails, make the order deterministic.

Do not rely on map iteration order.

```go
sort.Slice(output, func(i, j int) bool {
    if output[i].DnNumber != output[j].DnNumber {
        return output[i].DnNumber < output[j].DnNumber
    }
    return output[i].DnItem < output[j].DnItem
})
```

## Comment Style

Good comments explain the risk, not just personal preference.

Prefer:

```text
important: This helper name is too broad. It only checks HQ company
access, but the name suggests HQ-PM access. This could lead future
callers to reuse it for the wrong permission check.
```

Avoid:

```text
Rename this. I do not like the name.
```

For optional comments:

```text
nit: operatorInfo may be clearer than userInfo here, but this is optional.
```

## Do Not Over-Focus On

Do not block PRs only for:

- Minor wording preferences
- Subjective naming alternatives
- Formatting already handled by tools
- Comment punctuation
- Small style differences
- Documentation typos unrelated to behavior

These can be left as `nit:` or `suggestion:` comments.

## Final Rule

A PR should not be blocked by personal preference.

It should be blocked when the code can break behavior, weaken security, corrupt data, hide errors, or mislead future maintainers.
