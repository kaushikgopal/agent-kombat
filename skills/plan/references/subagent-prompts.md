# Subagent Prompts

Use context fan-out only when extra parallel context gathering materially
improves the plan: large ambiguous features, complex/unfamiliar codebases,
cross-cutting changes, risky migrations, or software investigations.

If subagents are unavailable or unnecessary, answer the same questions locally.
Keep reports concise and synthesize only load-bearing findings into the plan.

## Fan-Out Set

For complex software plans, gather the relevant subset of these independent
questions before writing the plan:

- what does this repo already do?
- have we solved this before in prior plans, notes, or repo-local knowledge?
- what do current docs or community examples say, when freshness matters?
- what tests, edge cases, and validation surfaces matter?

## Repo Research

`Inspect this repo for the behavior, files, conventions, and existing patterns most relevant to: <request>. Return concise findings with repo-relative paths and name any areas that should not be changed.`

## Prior Learning Search

`Search prior plan files, docs, notes, and repo-local knowledge for decisions or attempts that should inform: <request>. Return only items that materially change the plan, with repo-relative paths.`

## Best Practices Research

`Find primary-source guidance and established best practices relevant to: <request>. Prefer official docs and authoritative sources. Return only the load-bearing takeaways.`

## Validation Surface Research

`Inspect the repo for tests, fixtures, commands, edge cases, and failure modes relevant to: <request>. Return the smallest meaningful validation plan and any gaps.`
