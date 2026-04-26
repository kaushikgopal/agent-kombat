# Routing

Use the classifier first:

```bash
python3 skills/plan/scripts/plan_core.py classify --request "$ARGUMENTS"
```

For file-backed requests, use `--request-file path/to/request.txt` instead of
`--request`.

## Route Selection

- `action: refine` -> read the existing plan note, preserve completed work, and
  refine it in place
- `kind: software` -> use the software template and repo-first planning flow
- `kind: universal` -> use the universal template and mode-shaped sections
- `needs_clarification: true` -> ask one short question and stop

## Repo-First Planning

For software planning:

1. inspect the repo before proposing changes
2. look for nearby conventions and similar code
3. note real file paths in `## Files`
4. add implementation units only when they help execution
5. if repo inspection finds no plausible target files or patterns, stop and ask
   for the correct repo, files, or additional grounding context

## Context Fan-Out Rules

Use context fan-out when `should_consider_fanout_research: true`, or when a
software plan is large, ambiguous, cross-cutting, high-risk, or targets a
complex/unfamiliar codebase.

Do not use fan-out for small, obvious, one-file, or typo-level changes unless
the request explicitly says the surrounding system is risky or unclear.

Fan-out should answer independent questions before synthesis:

- what the repo already does
- whether prior plans, notes, or repo-local knowledge solved this before
- what current docs/community examples say, when freshness matters
- which tests, edge cases, and validation surfaces matter

Prefer parallel subagents when available and the questions are independent.
Otherwise gather the same context locally. The plan should include synthesized
findings in `## Context`, `## Existing Patterns`, `## Files`, `## Risks`, and
`## Validation`; it should not include raw subagent reports.

## External Research Rules

Only use external research when freshness materially affects the plan:

- library or vendor choice
- API or framework comparisons
- pricing or current product behavior
- travel or logistics plans where current conditions matter

If current external signal is needed and the user did not already provide it,
route through the existing `research` wrapper rather than inventing a parallel
research workflow.
