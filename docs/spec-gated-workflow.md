Spec-Gated Agent Development Workflow
1. Purpose

This document defines a scalable product engineering workflow for using Agent Skills, Superpowers, and OpenSpec together across the full development lifecycle.

The goal is not simply to let AI agents write more code. The goal is to make agents work within the right context, with clear specifications, verifiable acceptance criteria, controlled change management, and traceable delivery evidence.

This workflow connects:

Confluence
Jira
OpenSpec
Superpowers
Agent Skills
GitHub
Apidog
Testing
Release readiness
Post-release maintenance

The core principle is:

Rough specs should not go directly into implementation.
Every feature should pass through spec audit, OpenSpec, task planning, API contract planning, test planning, implementation, verification, release, and post-release triage.

2. Core Concept

The three systems should not overlap with each other. They should operate at different layers.

Component	Role	Responsibility
OpenSpec	Specification governance layer	Proposal, design, tasks, acceptance criteria, change request, bugfix spec, archive
Superpowers	Engineering methodology layer	Planning, TDD, debugging, code review, subagent coordination, stop-the-line review
Agent Skills	Company workflow automation layer	Read Confluence, read Jira, scan GitHub, generate Jira subtasks, plan Apidog, generate test plans, verify delivery evidence

In simple terms:

```text
OpenSpec is the specification backbone.
Superpowers is the engineering discipline.
Agent Skills are the company-specific hands and feet.
```

3. Recommended End-to-End Workflow

```text
Confluence rough spec
↓
Jira story / epic
↓
Spec intake
↓
Confluence spec audit
↓
GitHub repo context scan
↓
OpenSpec draft / proposal
↓
Dependency / assumption check
↓
OpenSpec review and approval
↓
Jira subtasks generation
↓
Apidog API contract planning
↓
Test plan generation
↓
Implementation
↓
Verification
↓
Release
↓
Post-release triage
↓
Bugfix / follow-up / archive
```

The critical rule is:

```text
Do not allow agents to move directly from Confluence rough specs to implementation.
```

The required middle steps are:

```text
Spec Audit → OpenSpec → Tasks → API Contract → Test Plan → Implementation
```

4. Tool Responsibilities
4.1 Confluence

Confluence is the business requirement source, not the final engineering specification.

Confluence is good for:

Business background
Customer problem
Product goal
Rough UX flow
High-level requirements
Stakeholder discussions
Final user-facing behavior

Confluence alone is usually not enough for implementation because it may contain:

Unclear scope
Missing edge cases
Incomplete API details
Untestable acceptance criteria
Missing permission behavior
Missing error behavior
Missing data behavior
4.2 Jira

Jira is the delivery tracking and task management tool.

Jira is good for:

Epic
Story
Bug
Status
Owner
Priority
Release target
Subtasks
Links to Confluence, OpenSpec, PRs, Apidog, and test results

Jira should not be the only source of truth for product behavior.

The best role for Jira is:

```text
Who owns it?
What is the current status?
What is blocked?
Where is the evidence?
```

4.3 OpenSpec

OpenSpec is the engineering-executable specification source.

OpenSpec should contain:

Problem
Goals
Non-goals
Proposal
Design
API behavior
Data behavior
Permission behavior
Acceptance criteria
Tasks
Assumptions
Unknowns
External dependencies
Change log
Verification checklist

OpenSpec should become the main source that agents follow before writing code.

4.4 GitHub Repo

GitHub is the actual system source of truth.

Before generating OpenSpec or Jira subtasks, agents should scan the related repos to understand:

Related modules
Existing APIs
Existing DTOs
Existing schemas
Database migration patterns
Permission middleware
Test structure
Coding conventions
Domain models
Known limitations

Without repo context, OpenSpec may become unrealistic.

4.5 Apidog

Apidog is the API contract, mock, and API test execution center.

For API-related features, Apidog should not be updated after backend implementation as documentation only.

The recommended sequence is:

```text
OpenSpec design approved
↓
Apidog API contract draft
↓
Frontend / backend / QA review
↓
Mock and API test cases ready
↓
Implementation
```

Apidog should become an implementation gate for API features.

4.6 Superpowers

Superpowers should not be used as the source of product specs.

Superpowers should enforce good engineering behavior, such as:

Brainstorming
Planning
TDD
Systematic debugging
Code review
Subagent workflow
Stop-the-line review when implementation does not match the spec
4.7 Agent Skills

Agent Skills are company-specific workflow capabilities.

They should automate repeatable work across the company’s toolchain.

Examples:

Read Jira story
Read Confluence spec
Audit rough specs
Scan GitHub repos
Generate OpenSpec proposals
Generate Jira subtasks
Plan Apidog contracts
Generate test plans
Check release readiness
Generate bugfix specs
Verify delivery evidence
5. OpenSpec Lifecycle States

A simple draft / approved / done status model is not enough.

Recommended OpenSpec states:

```text
draft
provisional
approved
blocked
implementing
changed
released
bugfix
superseded
archived
```

State	Meaning
draft	Initial version, still being prepared
provisional	Information is incomplete, but safe work can start
approved	Specification is approved for implementation
blocked	Blocked by third-party, design, infrastructure, legal, business, or other dependency
implementing	Implementation is in progress
changed	Major change happened during implementation
released	Released to users or production
bugfix	Post-release fix for committed behavior
superseded	Replaced by a newer spec
archived	Completed and stored for traceability
6. Gate-Based Workflow

Each gate should have a clear output before moving to the next step.

```text
Gate 1: Intake Complete
Gate 2: Spec Audit Complete
Gate 3: Repo Context Reviewed
Gate 4: OpenSpec Draft Ready
Gate 5: OpenSpec Approved
Gate 6: Jira Subtasks Generated
Gate 7: API Contract Approved
Gate 8: Test Plan Approved
Gate 9: Implementation Complete
Gate 10: Verification Passed
Gate 11: Released
Gate 12: Archived / Follow-up Created
```

7. Full Workflow Diagram

```text

Jira story created
↓
Read Confluence rough spec
↓
Spec intake report
↓
Confluence spec audit
↓
GitHub repo context scan
↓
Domain risk check
↓
OpenSpec proposal generated
↓
External dependency check
├── Complete → Continue
└── Incomplete → Provisional spec + mock + adapter + blocked tasks
↓
OpenSpec design + tasks + acceptance criteria
↓
Review by PM / tech lead / QA / relevant engineers
↓
OpenSpec approved
↓
Generate Jira subtasks
↓
Generate Apidog API contract
↓
Generate test plan
↓
Implementation starts
↓
Mid-implementation issue?
├── Minor → Amendment
└── Major → Change request + impact analysis
↓
PR review against OpenSpec
↓
Verification
├── OpenSpec acceptance criteria
├── Apidog contract
├── Automated tests
├── QA checklist
└── Jira evidence
↓
Release readiness check
↓
Release
↓
Post-release triage
├── Incident → Hotfix / incident process
├── Bug → Bugfix spec + regression test
├── Spec gap → Clarification / follow-up
├── Enhancement → New OpenSpec proposal
└── Operational issue → Ops / infra ticket
↓
Archive OpenSpec
```
8. Handling Incomplete Third-Party Information

Some features cannot be fully specified because a third-party vendor, external team, or partner has not completed their part.

In this situation, do not pretend the specification is complete.

Use:

```text
Provisional spec
Assumptions
Unknowns
External dependencies
Mock provider
Adapter boundary
Feature flag
Blocked integration tasks
```

Recommended Flow

```text
Confluence rough spec
↓
OpenSpec draft
↓
Mark external dependency
↓
Create provisional contract
↓
Create blocking / tracking Jira tasks
↓
Build independently developable parts
↓
Third-party information becomes available
↓
Update spec
↓
Integration and verification
```

Example OpenSpec Section

```text
External Dependencies

Dependency:

Third-party access control API

Current status:

Waiting for vendor to confirm final response schema

Assumptions:

API will return userId, role, and permissionScopes
Error codes will include 401, 403, 429, and 5xx
Average response time should be under 500ms

Unknowns:

Whether pagination is required
Whether webhook retry is supported
Whether permission scope format is stable

Fallback plan:

Use adapter layer to isolate third-party schema
Use mock server before real integration
Avoid exposing third-party-specific fields to frontend

Blocking:

Final integration test cannot complete until vendor sandbox is available
```
Recommended Jira Task Split
Task	Status
Define provisional integration contract	Can start
Build internal adapter interface	Can start
Build mock / fake provider	Can start
Implement feature behind feature flag	Can start
Confirm final third-party API schema	Blocked
Integrate with third-party sandbox	Blocked
Run contract verification	Blocked
Production readiness review	Blocked

The key rule is:

```text
Do not let the entire story be blocked by the third party.
Only block the actual integration tasks.
```

9. Adapter Boundary for Third-Party Integration

Third-party APIs should not directly leak into core product logic.

Recommended architecture:

```text
Product logic
↓
Internal interface
↓
Third-party adapter
↓
Third-party API
```

Benefits:

Third-party schema changes are isolated
Mocking becomes easier
Contract tests become easier
Product logic remains stable
Vendor-specific behavior does not spread across the codebase
10. Handling Mid-Implementation Spec Changes

Sometimes implementation reveals that the original spec is wrong, incomplete, or no longer suitable.

Do not silently change code.

First decide whether the change is:

```text
Amendment
or
Change Request
```

10.1 Amendment

Use an amendment for small changes.

Examples:

Wording clarification
Small field clarification
Additional edge case
Minor acceptance criteria update
Small error message clarification

Recommended flow:

```text
Issue discovered
↓
Create spec amendment
↓
Mark affected tasks / tests / API
↓
Update OpenSpec
↓
Sync Jira subtask
↓
Update Apidog / tests if needed
↓
Continue implementation
```

10.2 Change Request

Use a change request for major changes.

Examples:

API contract changed
Database schema changed
Permission model changed
Product behavior changed
Scope changed
Release commitment changed
Acceptance criteria changed significantly

Recommended flow:

```text
Mismatch discovered
↓
Stop implementation for affected area
↓
Create spec change request
↓
Run impact analysis
↓
PM / tech lead / QA review
↓
Update OpenSpec
↓
Regenerate Jira subtasks if needed
↓
Update Apidog
↓
Update test plan
↓
Resume implementation
```

10.3 Amendment vs Change Request Rule
Question	Amendment	Change Request
Only wording or small clarification?	Yes	No
API contract affected?	Usually no	Yes
Database schema affected?	No	Yes
Permission or security affected?	No	Yes
Release scope affected?	No	Yes
Other teams affected?	Usually no	Usually yes
Test baseline changed?	Maybe	Usually yes

Simple rule:

```text
If it only changes wording, small fields, or minor edge cases, use amendment.
If it changes API, DB, permissions, behavior, scope, or test standards, use change request.
```

11. Change Decision Log

Every meaningful change should leave a decision trail.

Recommended format:

```text
Change Decision Log

Date:

2026-06-03

Change:

Original design used cameraId filter only.
Updated to support cameraGroupId and siteId filters.

Reason:

Enterprise customers manage cameras by site or group, not individual camera only.

Impact:

API query schema changed
Backend permission check needs group-level validation
Frontend filter UI needs update
Apidog test cases need update

Decision:

Approved by PM and backend lead
```

This avoids future confusion about why a decision was made.

12. Post-Release Issue Handling

After release, issues should not automatically be pushed back into the original story.

First triage the issue.

12.1 Post-Release Triage Categories
Issue Type	Definition	Process
Incident	System stability, security, data correctness, or severe customer impact	Incident + hotfix
Bug	Released behavior does not match approved spec	Bugfix spec
Regression	Previously working behavior is broken	Bugfix spec + regression test
Spec gap	Original spec was unclear or incomplete	Clarification / follow-up
Enhancement	New requirement or improvement	New OpenSpec proposal
Operational issue	Deployment, monitoring, configuration, or data issue	Ops / infra ticket
12.2 Bugfix Flow

A bug means:

```text
The released implementation does not satisfy the approved spec or acceptance criteria.
```

Recommended bugfix flow:

```text
Bug reported
↓
Triage
↓
Compare against released OpenSpec
↓
Create bugfix OpenSpec change
↓
Create Jira bug
↓
Add regression test
↓
Implement fix
↓
Verify
↓
Release patch
↓
Archive bugfix spec
```

12.3 Bugfix Spec Example

```text
Bugfix Spec

Issue:

Users without camera group permission can still query events.

Expected behavior:

API should return 403 when user lacks permission.

Actual behavior:

API returns 200 with an empty event list.

Root cause:

Permission check only validates tenantId, not cameraGroupId.

Fix:

Add cameraGroup-level permission validation before query execution.

Regression test:

User without access to cameraGroupId should receive 403.
User with access should receive 200.

Affected areas:

Event query API
Permission middleware
Apidog negative test case
Integration test
```

Hard rule:

```text
No regression test, no bugfix closure.
```

12.4 Follow-Up Enhancement Flow

If the post-release issue is not a bug but a new requirement, create a new proposal.

Examples:

Customer wants an additional filter
QA suggests a better UX
Customer support finds a new operational scenario
PM wants an additional report
Existing behavior works as specified, but users now need more

Recommended flow:

```text
Post-release feedback
↓
Triage: bug or enhancement?
↓
If enhancement:
Create new OpenSpec proposal
Link original released spec
Create new Jira story
Plan API / tests / implementation
```

Do not hide new scope inside the old story.

13. Jira Evidence Requirements

Each completed Jira item should include evidence.

Item	Required Evidence
API design	Apidog link
Backend implementation	PR link
Frontend implementation	PR link or design review link
Tests	CI link or test report
Spec	OpenSpec change ID
Documentation	Confluence link
Verification	QA result
Release	Release note or deployment record

The verification rule is:

```text
No evidence, no closure.
```

14. Recommended Agent Skills

The following skills can be built gradually.

Do not build everything at once.

14.1 Intake Skills
1. jira-intake

Purpose:

Read Jira story, epic, or bug

Input:

```text
Jira issue key
```

Output:

```text

Title
Description
Acceptance criteria
Priority
Owner
Linked Confluence
Linked GitHub
Linked Apidog
Current status
Missing fields
```
2. confluence-spec-reader

Purpose:

Read Confluence rough spec

Output:

```text

Business goal
User problem
Proposed behavior
User flow
Requirements
Edge cases mentioned
Open questions
```
3. spec-intake-summarizer

Purpose:

Combine Jira and Confluence into an intake report

Output:

```text

Confirmed requirements
Unclear requirements
Assumptions
Stakeholders
Affected product area
Suggested next action
```
14.2 Spec Audit Skills
4. confluence-spec-audit

Purpose:

Check whether Confluence has conflicts, gaps, or untestable requirements

Checks:

```text

Requirement conflict
Missing actor
Missing state
Missing permission
Missing API behavior
Missing data behavior
Missing error behavior
Missing edge cases
Missing acceptance criteria
```
5. spec-gap-detector

Purpose:

Detect specification gaps

Output:

```text

Must-resolve gaps
Can-assume gaps
Future-scope gaps
Questions for PM / tech lead / QA
```
6. vortex-domain-risk-checker （this is example, we must be common checker）

Purpose:

Detect domain-specific risks for VSaaS, AI surveillance, AI cameras, and cloud VMS

Checks:

```text

Tenant isolation
Camera permission
Site / group hierarchy
Cloud recording impact
Edge camera offline behavior
AI event accuracy / false positive
Event retention
Video privacy
Audit log
Notification behavior
Bandwidth / latency
Failover behavior
```

This skill is especially important because it makes agents understand product-specific risks instead of acting like generic coding assistants.

14.3 GitHub Context Skills
7. github-repo-context-scan

Purpose:

Scan related repos before writing OpenSpec or subtasks

Output:

```text

Affected modules
Related APIs
Related services
Related database tables
Related tests
Coding conventions
Risky dependencies
```
8. implementation-surface-mapper

Purpose:

Identify which parts of the system will be affected

Output:

```text

Backend impact
Frontend impact
API impact
DB impact
Permission impact
Infrastructure impact
QA impact
```
9. existing-test-discovery

Purpose:

Discover existing test coverage

Output:

```text

Existing unit tests
Existing integration tests
Missing test areas
Suggested new tests
```
14.4 OpenSpec Skills
10. openspec-proposal-generator

Purpose:

Generate an OpenSpec proposal from Jira, Confluence, and repo context

Output:

```text

Problem
Goals
Non-goals
Proposed solution
Affected specs
Assumptions
Risks
```
11. openspec-design-writer

Purpose:

Generate the OpenSpec design section

Includes:

```text

API design
Data model
Permission model
Error handling
Migration
Observability
Compatibility
```
12. openspec-task-generator

Purpose:

Generate OpenSpec tasks and later convert them into Jira subtasks

Output:

```text

Implementation tasks
API tasks
Frontend tasks
QA tasks
Documentation tasks
Verification tasks
```
13. openspec-acceptance-criteria-generator

Purpose:

Convert specs into testable acceptance criteria

Recommended format:

```text
Given / When / Then
```

14.5 External Dependency Skills
14. external-dependency-handler

Purpose:

Handle incomplete third-party or external dependency information

Output:

```text

External dependency list
Confirmed information
Assumptions
Unknowns
Blocking items
Fallback plan
Mock strategy
Adapter strategy
Questions to vendor
```
15. provisional-contract-generator

Purpose:

Generate provisional API or data contracts

Useful when:

```text

Vendor API is not finalized
Sandbox is not available
Webhook format is not confirmed
Schema is still changing
```
16. mock-provider-planner

Purpose:

Plan mock or fake providers to avoid being blocked by third parties

Output:

```text

Mock endpoint
Fake response
Error simulation
Latency simulation
Retry simulation
Contract test cases
```
14.6 Jira Skills
17. jira-subtask-generator

Purpose:

Generate Jira subtasks from OpenSpec tasks

Each subtask should include:

```text

Title
Description
Owner role
Dependency
Done criteria
Evidence link requirement
```
18. jira-dependency-mapper

Purpose:

Create blocking relationships between Jira tasks

Output:

```text

Blocked by
Blocks
Can start now
Cannot start until dependency is resolved
```
19. jira-evidence-checker

Purpose:

Check whether Jira has enough evidence before closure

Checks:

```text

PR link
Apidog link
Test result
CI result
OpenSpec link
Confluence update link
```
14.7 Apidog Skills
20. apidog-contract-planner

Purpose:

Generate API contract plans based on OpenSpec

Output:

```text

Endpoint
Method
Path
Request schema
Response schema
Error codes
Auth requirement
Permission behavior
Examples
```
21. apidog-mock-generator

Purpose:

Generate mock API data

Includes:

```text

Success response
Empty response
Permission denied
Invalid request
Rate limited
Third-party timeout
```
22. apidog-testcase-generator

Purpose:

Generate API test cases

Includes:

```text

Positive cases
Negative cases
Boundary cases
Permission cases
Pagination cases
Compatibility cases
```
14.8 Testing Skills
23. test-plan-generator

Purpose:

Generate test plans from OpenSpec, Apidog, and repo context

Output:

```text

Unit test plan
Integration test plan
API test plan
Regression test plan
Manual QA checklist
```
24. regression-test-generator

Purpose:

Generate regression tests for bugs or changed behavior
25. acceptance-test-mapper

Purpose:

Map OpenSpec acceptance criteria to tests

Output:

```text
Requirement → Test case → Evidence
```

26. qa-verification-checker

Purpose:

Check test coverage before verification

Checks:

```text

Every acceptance criterion has a test
Every API error has a test
Every permission rule has a test
Every known edge case has a test
```
14.9 Change Management Skills
27. spec-change-impact-analyzer

Purpose:

Determine the impact of a spec change during implementation

Output:

```text

Amendment or change request
Affected OpenSpec sections
Affected Jira subtasks
Affected API contract
Affected tests
Affected repo modules
Release risk
```
28. openspec-amendment-writer

Purpose:

Write small spec amendments

Good for:

```text

Wording clarification
Small field clarification
Extra edge case
Minor acceptance criteria update
```
29. openspec-change-request-writer

Purpose:

Write major change requests

Good for:

```text

API contract change
DB schema change
Permission model change
Scope change
Release commitment change
```
30. change-decision-log-updater

Purpose:

Record why a change was made

Format:

```text
Change:
Reason:
Impact:
Decision:
Approved by:
Date:
```

14.10 Implementation and Review Skills
31. implementation-guardrail-checker

Purpose:

Prevent agents from implementing outside the approved spec

Checks:

```text

Did the implementation change a non-goal?
Did it modify unrelated modules?
Did it change the API contract?
Did it skip permission checks?
Did it miss migration?
Did it miss tests?
```
32. pr-spec-compliance-checker

Purpose:

Compare PR content against OpenSpec

Output:

```text

Implemented requirements
Missing requirements
Extra behavior
Risky changes
Test coverage gaps
```
33. code-review-assistant

Purpose:

Support normal code review

Superpowers can provide the engineering methodology.

This skill should apply company repo conventions, product rules, and review checklists.

14.11 Release and Post-Release Skills
34. release-readiness-checker

Purpose:

Check whether the feature is ready for release

Checks:

```text

OpenSpec approved
Jira subtasks complete
Apidog updated
Tests passed
Monitoring ready
Rollback plan ready
Docs updated
```
35. post-release-triage

Purpose:

Classify post-release issues

Categories:

```text

Incident
Bug
Regression
Spec gap
Enhancement
Operational issue
```
36. bugfix-spec-generator

Purpose:

Convert production bugs into bugfix specs

Includes:

```text

Expected behavior
Actual behavior
Root cause
Fix proposal
Regression tests
Affected areas
```
37. follow-up-proposal-generator

Purpose:

Convert post-release new requirements into new OpenSpec proposals
38. openspec-archive-checker

Purpose:

Ensure final spec archive is complete

Checks:

```text

Final spec updated
Change log completed
Tests linked
PR linked
Jira linked
Confluence final behavior synced
```
15. Recommended Rollout Plan

Do not build all 38 skills at once.

Start with the highest-value skills first.

Phase 1: Required Core Skills

Start with these 8 skills:

```text

jira-intake
confluence-spec-audit
github-repo-context-scan
openspec-proposal-generator
jira-subtask-generator
apidog-contract-planner
test-plan-generator
spec-change-impact-analyzer
```

These support the main workflow.

Phase 2: Dependency, Verification, and Release Skills

Add these after the core workflow works:

```text
9. external-dependency-handler
10. provisional-contract-generator
11. qa-verification-checker
12. pr-spec-compliance-checker
13. release-readiness-checker
14. bugfix-spec-generator
15. post-release-triage
```

Phase 3: Domain-Specific and Advanced Skills

Add these after Phase 1 and Phase 2 are stable:

```text
16. vortex-domain-risk-checker
17. apidog-testcase-generator
18. regression-test-generator
19. implementation-guardrail-checker
20. openspec-archive-checker
```

The vortex-domain-risk-checker should eventually become a priority because it makes agents aware of VSaaS, AI surveillance, cloud VMS, AI camera, permission, event, and video-specific risks.

16. Important Rules
Rule 1: Incomplete information should not be treated as complete

Use:

```text
Provisional spec
Assumptions
Unknowns
External dependencies
Mock
Adapter
Feature flag
```

Rule 2: Third-party integration should use an adapter boundary

Use:

```text
Product logic
↓
Internal interface
↓
Third-party adapter
↓
Third-party API
```

Rule 3: Apidog should be an implementation gate

For API features:

```text
OpenSpec approved
↓
Apidog contract approved
↓
Mock / test ready
↓
Implementation
```

Rule 4: Testing should be planned before implementation

Before coding, prepare:

```text
Acceptance criteria
API test cases
Permission test cases
Regression test plan
Manual QA checklist
```

Rule 5: Mid-implementation mismatch should not be fixed silently

First decide:

```text
Amendment
or
Change request
```

Simple rule:

```text
Small wording, field, or edge-case clarification → Amendment
API, DB, permission, behavior, scope, or test baseline change → Change request
```

Rule 6: Post-release issues should not be hidden in old stories

Triage first:

```text
Does not match original spec → Bugfix
Original spec was unclear → Clarification / follow-up
New requirement → New proposal
Severe production impact → Incident / hotfix
```

Rule 7: Production bugs require regression tests

```text
No regression test, no bugfix closure.
```

Rule 8: Jira closure requires evidence

```text
No evidence, no closure.
```

17. Final Operating Model

The final workflow can be called:

```text
Spec-Gated Agent Development Workflow
```

Its operating principles are:

```text
Rough specs cannot directly enter implementation.
All requirements must become verifiable specifications.
API contract should come before implementation.
Tests should be planned before implementation.
Mid-implementation changes must leave a trace.
Post-release issues must be triaged.
Bugfixes must include regression tests.
Completed specs must be archived.
```

The final goal is:

Agents should work inside the correct specification, correct context, correct test plan, and correct change history.

This makes the workflow scalable for products involving:

Cloud VMS
AI cameras
AI event detection
Tenant permissions
Camera groups
Video data
Third-party integrations
API contracts
Large engineering teams
Complex release cycles