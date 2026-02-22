---
name: comprehensive-implementation-review
description: Run a full-scale implementation review using parallel subagents: plan-alignment code review, UI manual verification with Playwright/agent-browser, technical risk analysis, and strategic architecture analysis.
metadata:
  short-description: Parallel end-to-end implementation review
---

# Comprehensive Implementation Review

## Goal

Audit an implementation end-to-end, with or without a formal plan, and produce a defensible review with evidence from code, diffs, tests, and manual UI verification.

## When to use

Use this skill when the user asks for a broad post-implementation review such as:

- comparing implementation to an attached plan or handoff
- reviewing uncommitted or committed changes for regressions and bugs
- manually verifying front-end behavior with Playwright and/or agent-browser
- assessing strategic implementation quality, not only local correctness

## Entry criteria

Check these preconditions before deep review:

- repo scope is clear (`cwd`, target project, and base branch/range known)
- change scope is available (`git status`/`git diff` or explicit commit range)
- runnable environment exists for intended checks (tests/build/dev server as needed)
- UI verification prerequisites are known (auth path, test user/role, seed state)
- DB review prerequisites are known when relevant (local DB state, migration order, reset/test commands)

If any criterion fails, continue with available lanes and clearly report blocked coverage.

## Inputs

Gather the following before review:

1. Intention source (preferred in this order):
- `.plan.md` file path, or
- pasted implementation/handoff text in the prompt, or
- no-plan mode (derive expected behavior from changed files, tests, docs, and commit/diff context)

2. Change scope:
- uncommitted (`git status`, `git diff`), or
- committed range (`git diff <base>...HEAD`)

3. UI scope:
- routes/pages to verify, pulled from plan, tests, docs, and changed files

If any item is missing and blocks execution, ask one short question. Otherwise, state assumptions and proceed.

## Review modes

Select one mode explicitly at the start of the review:

1. `plan` mode
- Use when a `.plan.md` is available.
- Evaluate strict plan-to-implementation alignment.

2. `handoff` mode
- Use when only prompt/handoff intent is available.
- Evaluate claim-to-implementation alignment.

3. `no-plan` mode
- Use when no plan/handoff is provided.
- Skip strict alignment claims and focus on correctness, regressions, UX behavior, and strategy quality.

4. `self-review` mode
- Use when the same agent that implemented changes performs the review.
- Treat prior assumptions as untrusted and require diff/test/UI evidence for every claim.

## Parallel subagents

Run parallel subagents with explicit, non-overlapping responsibilities:

1. `plan-alignment-reviewer`
- Build an intention-to-evidence matrix from plan/handoff claims.
- Verify each claim against actual file diffs.
- Flag missing, partial, or extra implementation.

2. `ui-verification-reviewer`
- Perform manual UI checks using Playwright or agent-browser.
- Validate key user paths and permissions/role gating.
- Record pass/fail with exact route and observed behavior.

3. `technical-risk-reviewer`
- Perform code review on changed files.
- Prioritize bugs, regressions, data/permission risks, and test coverage gaps.
- Include file references and concrete failure modes.

4. `strategic-reviewer`
- Evaluate architecture and implementation strategy.
- Identify coupling, migration safety gaps, maintainability risks, and scalability concerns.
- Suggest alternatives only when they materially reduce risk.

## Subagent output contract

Require each subagent to return this exact structure:

- `findings`: severity-ranked items with file references when applicable
- `evidence`: concrete observations (diff snippet summary, command result, UI observation)
- `confidence`: `high | medium | low` per finding
- `unverified_assumptions`: assumptions that could change conclusions
- `blocked_items`: what could not be validated and why

Reject subagent output that is opinion-only or lacks evidence.

## UI coverage matrix

Build and execute a minimal matrix:

- persona/role x route/page x key action x expected result
- include at least one happy path and one negative/permission-boundary path per protected area
- include a navigation/gating check (route guard, menu visibility, or access denial behavior)
- record each matrix row as `pass`, `fail`, or `blocked`

When blocked, capture exact blocker and the attempted step.

## Workflow

1. Establish scope and evidence
- Determine review mode (`plan`, `handoff`, or `no-plan`) and whether review is `self-review`.
- Read plan/handoff text when provided.
- Enumerate changed files and classify by area (DB/schema, server, client, tests/docs).
- Derive expected outcomes from the best available intention source for the selected mode.

2. Validate entry criteria and set timebox
- Confirm entry criteria; note any missing prerequisites.
- Set a review timebox and prioritize critical paths first (permissions, data integrity, primary UI flows).

3. Dispatch the four subagents in parallel
- Provide each subagent only the context needed for its lane.
- Require each subagent to return contract-compliant output.

4. Run UI verification explicitly
- Start from user-visible flows (routes, nav, forms, role-conditional UI).
- Verify both happy path and at least one negative/permission boundary path.
- When blocked (auth, env, seed data), report blocker and partial coverage.

5. Run DB/migration checklist when schema or SQL changed
- check RLS/policy behavior against intended access model
- check migration safety (ordering, idempotency where relevant, rollback feasibility)
- check grants/privileges drift and RPC exposure changes
- check seed/test/type-generation consistency with schema changes

6. Consolidate findings
- De-duplicate overlaps across subagents.
- Convert raw notes into severity-ranked findings.
- Separate confirmed defects from open questions.

7. Deliver review result
- Findings first (highest severity first).
- Then plan alignment verdict, UI verification status, technical analysis summary, strategic analysis summary, and clear next actions.
- If timebox expires or blockers remain, provide partial verdict with explicit coverage gaps.

## Severity model

Use this priority scale:

- `P0`: release-blocking correctness or security issue
- `P1`: high-risk bug/regression likely to affect production behavior
- `P2`: meaningful correctness/maintainability/test gap
- `P3`: minor issue or improvement opportunity

## Sign-off gates

Apply these gates before issuing the final verdict:

- do not return `aligned` if any open `P0` or `P1` exists
- do not return `aligned` when critical UI flows are `blocked` without mitigation evidence
- do not return `aligned` when DB/migration changes were made but DB checklist was skipped
- in `no-plan` mode, return `no-plan reviewed` (never strict `aligned`)

## Output template

```markdown
Review target: `<plan path or prompt summary>`
Review mode: `<plan | handoff | no-plan>` (+ `self-review` when applicable)
Change scope: `<uncommitted | commit range>`

Findings:
1. [P1] <title> — `<file:line>`
   Evidence: <what was observed>
   Impact: <user/system impact>
   Recommendation: <concrete fix>
1. [P2] <title> — `<file:line>`
   Evidence: <what was observed>
   Impact: <user/system impact>
   Recommendation: <concrete fix>

Plan alignment matrix (for `plan`/`handoff` modes):
1. `<planned item>` -> `<implemented evidence>` -> `<aligned | partial | missing | extra>`
1. `<planned item>` -> `<implemented evidence>` -> `<aligned | partial | missing | extra>`

Intent reconstruction matrix (for `no-plan` mode):
1. `<inferred expected behavior>` -> `<implemented evidence>` -> `<confirmed | partial | contradicted>`
1. `<inferred expected behavior>` -> `<implemented evidence>` -> `<confirmed | partial | contradicted>`

UI verification:
1. `<route + area + action>` -> `<pass/fail>` -> `<observed result>`
1. `<route + area + action>` -> `<pass/fail>` -> `<observed result>`
Blockers: <none or list>

Technical analysis:
- `<top technical risk or confirmation>`
- `<top technical risk or confirmation>`

Strategic analysis:
- `<strategy strength/weakness>`
- `<strategy strength/weakness>`

Review artifacts:
- `<commands run and key outcomes>`
- `<ui evidence: screenshots/log notes or blocker proof>`
- `<coverage summary: tested vs blocked>`

Verdict: `<aligned | partially aligned | not aligned | no-plan reviewed>`
Recommended next steps:
1. <step>
1. <step>
```

## Guardrails

- Do not mark "aligned" unless plan claims are evidenced in diffs/tests/UI checks.
- In `no-plan` mode, do not claim strict alignment; use verdict `no-plan reviewed`.
- Do not bury critical defects under summary text; findings must appear first.
- If UI cannot be fully executed, provide exact blocker and what was still validated.
- Prefer concrete, falsifiable statements over broad judgments.
- In `self-review` mode, call out reviewer/implementer overlap and keep evidence thresholds strict.
- Enforce subagent output contract; request retries for incomplete outputs.
- If review is partial due to blockers/timebox, say so explicitly in verdict context.

## Subagent prompt pack

Use these prompts as-is, replacing placeholders.

### Parent orchestration prompt

```text
Run a comprehensive implementation review.

Context:
- Review target: <plan path OR handoff summary OR "none">
- Review mode: <plan | handoff | no-plan>
- Self-review: <yes | no>
- Change scope: <uncommitted | commit range>
- Repo/project path: <path>
- UI routes in scope: <route list>
- Timebox: <minutes>

Execution requirements:
1) Spawn four parallel subagents:
   - plan-alignment-reviewer
   - ui-verification-reviewer
   - technical-risk-reviewer
   - strategic-reviewer
2) Enforce this output contract for every subagent:
   - findings
   - evidence
   - confidence
   - unverified_assumptions
   - blocked_items
3) Reject and retry any subagent output that lacks evidence.
4) Consolidate results into one findings-first report with severity ordering.
5) Apply sign-off gates from the skill and produce a final verdict.
```

### Prompt: `plan-alignment-reviewer`

```text
You are the plan-alignment-reviewer.

Inputs:
- Review mode: <plan | handoff | no-plan>
- Intention source: <plan path or handoff text; can be empty in no-plan mode>
- Change scope: <uncommitted | commit range>
- Changed file list/diff summary: <insert>

Tasks:
1) Build an intention-to-evidence matrix from intention claims and actual diffs.
2) For each claim, classify as aligned, partial, missing, or extra.
3) In no-plan mode, produce an intent reconstruction matrix:
   - inferred expected behavior -> implemented evidence -> confirmed/partial/contradicted
4) Flag any claimed work not evidenced in code/tests/docs.

Return exactly:
- findings: severity-ranked issues with file refs
- evidence: specific diff/test/doc observations
- confidence: high/medium/low per finding
- unverified_assumptions: assumptions and why
- blocked_items: what prevented validation
```

### Prompt: `ui-verification-reviewer`

```text
You are the ui-verification-reviewer.

Inputs:
- UI scope routes/pages: <insert>
- Personas/roles: <insert>
- Environment/access constraints: <insert>
- Change scope summary: <insert>

Tasks:
1) Use Playwright and/or agent-browser to manually verify UI behavior.
2) Build and execute a coverage matrix:
   - role x route/page x key action x expected result
3) Include at least:
   - one happy path per protected area
   - one negative/permission-boundary path per protected area
   - one gating/navigation check (route guard/menu visibility/access denial)
4) Record each row as pass/fail/blocked with observed result.
5) Capture evidence artifacts (screenshots/log notes) for failures or blockers.

Return exactly:
- findings: severity-ranked UI defects/regressions
- evidence: route-level observations and artifact references
- confidence: high/medium/low per finding
- unverified_assumptions: missing env/auth/data assumptions
- blocked_items: exact blocker + attempted step
```

### Prompt: `technical-risk-reviewer`

```text
You are the technical-risk-reviewer.

Inputs:
- Changed files and diff: <insert>
- Related tests/docs/commands run: <insert>
- Review mode and constraints: <insert>

Tasks:
1) Perform a code review focused on:
   - correctness bugs
   - behavioral regressions
   - data integrity and permission risks
   - missing or weak tests
2) If SQL/schema changed, run DB/migration checklist:
   - RLS/policy behavior vs intended access model
   - migration safety, ordering, rollback feasibility
   - grants/privileges/RPC exposure drift
   - seed/test/type-generation consistency
3) Prioritize findings by P0-P3 and include file references.

Return exactly:
- findings: severity-ranked technical issues with file refs
- evidence: concrete code/diff/test command observations
- confidence: high/medium/low per finding
- unverified_assumptions: what is assumed but unproven
- blocked_items: checks that could not be completed
```

### Prompt: `strategic-reviewer`

```text
You are the strategic-reviewer.

Inputs:
- Implementation summary: <insert>
- Changed areas by layer (db/server/client/tests/docs): <insert>
- Review mode: <insert>

Tasks:
1) Evaluate implementation strategy quality:
   - architecture cohesion and coupling
   - migration/cutover safety and operability
   - maintainability and future change cost
   - scalability and team workflow implications
2) Identify strategic weaknesses and practical alternatives.
3) Recommend only changes that materially reduce risk or complexity.

Return exactly:
- findings: severity-ranked strategic risks/anti-patterns
- evidence: concrete repo or diff observations
- confidence: high/medium/low per finding
- unverified_assumptions: strategic assumptions needing confirmation
- blocked_items: missing context that limits confidence
```

### Consolidation prompt (optional)

```text
Consolidate four subagent outputs into one final review.

Rules:
1) Findings first, highest severity first, deduplicated across lanes.
2) Keep only evidence-backed findings.
3) Include mode-appropriate matrix:
   - plan/handoff -> plan alignment matrix
   - no-plan -> intent reconstruction matrix
4) Include UI verification status, blockers, and coverage summary.
5) Apply sign-off gates before verdict.
6) Verdict allowed values:
   - aligned
   - partially aligned
   - not aligned
   - no-plan reviewed
```
