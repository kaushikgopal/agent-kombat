# Plan Contract

This document is the source of truth for plan notes written by `plan` and read
by `work`.

## Storage

- Prefer repo-local `.agents/plans/` when it exists
- If repo guidance recommends another local plans directory, use that
- If no repo-local plans directory is available, use the classifier's XDG state
  fallback
- Filenames use `YYYY-MM-DD-<kebab-slug>-plan.md`
- Add `-NN` only when multiple plans land on the same day
- Paths inside plan notes are repo-relative, never absolute, even when the note
  itself is stored outside the repo

## Frontmatter

Every plan note starts with:

```yaml
---
title: <short descriptive title>
kind: software | universal
status: planned | in_progress | blocked | done
mode: feature | fix | refactor | investigation | writing | strategy | trip | study | runbook | proposal
created: YYYY-MM-DD
updated: YYYY-MM-DD
repo: <repo-name or "none">
source_inputs:
  - <file path, URL, transcript ref, etc.>
---
```

Rules:

- `kind` is the routing field in v1
- `mode` is informational-only in v1
- `created` never changes after the file is created
- `updated` changes whenever the plan is intentionally edited

## Shared Core Sections

Every plan note includes:

- `## Goal`
- `## Context`
- `## Constraints`
- `## Approach`
- `## Open Questions`

Do not leave obviously empty headings behind. If a section genuinely has
nothing to say, either omit it when the template allows omission or write a
short explicit note.

## Software Plans

Software plans additionally include:

- `## Existing Patterns`
- `## Files`
- `## Tasks`
- `## Acceptance Criteria`
- `## Validation`
- `## Risks`
- `## Implementation Units` when complexity warrants stable unit identities

Software investigation plans may also include:

- `## Decision`
- `## Options`
- `## Evaluation Criteria`
- `## Evidence`
- `## Recommendation`
- `## Next Experiment`

Use these when the user is evaluating tools, APIs, or implementation paths
rather than moving directly into feature execution.

Implementation Unit shape:

```markdown
- U1. **<Name>**
  - Goal: ...
  - Files: ...
  - Approach: ...
  - Test scenarios: ...
  - Verification: ...
```

U-ID rules:

- once assigned, U-IDs are never renumbered
- reordering preserves IDs
- splitting keeps the original ID on the original concept and assigns a new one
- deletion leaves gaps; gaps are fine

## Universal Plans

Universal plans use the shared core sections plus mode-shaped sections:

| mode | additional sections |
|---|---|
| `trip` | `## Itinerary`, `## Reminders`, `## Budget` |
| `proposal` | `## Proposal`, `## Recommendation`, `## Open Risks` |
| `study` | `## Syllabus`, `## Milestones`, `## Resources` |
| `strategy` | `## Options`, `## Recommendation`, `## Success Metrics` |
| `writing` | `## Outline`, `## Drafts`, `## References` |
| `runbook` | `## Timeline`, `## Responsibilities`, `## Checklist` |
| `investigation` | `## Questions`, `## Sources`, `## Findings` |

Universal plans do not use software-only sections like:

- `## Acceptance Criteria`
- `## Validation`
- `## Implementation Units`

Universal plans are durable artifacts in v1, not executable inputs to `work`.

## Mutation Rules

These are hard rules enforced by `work`.

`work` may mutate only:

- `status`
- `updated`
- task checkboxes in `## Tasks`
- acceptance checkboxes in `## Acceptance Criteria`
- appended notes in `## Validation`
- appended blockers in `## Open Questions`

`work` must not mutate:

- `title`, `kind`, `mode`, `created`, `repo`
- `## Goal`
- `## Context`
- `## Constraints`
- `## Approach`
- `## Existing Patterns`
- `## Files`
- `## Risks`
- implementation-unit bodies
- U-IDs
- section order or heading names

## Software Example

```markdown
---
title: Auth middleware rewrite
kind: software
status: planned
mode: refactor
created: 2026-04-25
updated: 2026-04-25
repo: aikado
source_inputs:
  - issue #123
---

# Auth middleware rewrite

## Goal

Reduce auth branching and make request validation testable.

## Context

Current auth checks are duplicated across two entry points.

## Constraints

Keep the public request shape unchanged.

## Existing Patterns

- `src/auth/base.ts`

## Approach

Move shared validation into one service and keep adapters thin.

## Files

- `src/auth/base.ts`
- `src/http/middleware.ts`

## Tasks

- [ ] Extract shared validation
- [ ] Update middleware callers

## Acceptance Criteria

- [ ] Existing auth tests still pass
- [ ] New shared service is used by both entry points

## Validation

- `pnpm test auth`

## Risks

- Hidden coupling in request context mutation

## Open Questions

- Do we need a temporary adapter for legacy callers?

## Implementation Units

- U1. **Extract shared validator**
  - Goal: centralize auth checks
  - Files: `src/auth/base.ts`
  - Approach: move common validation into one exported helper
  - Test scenarios: valid token, invalid token
  - Verification: `pnpm test auth`
```

## Universal Example

```markdown
---
title: Tokyo June trip
kind: universal
status: planned
mode: trip
created: 2026-04-25
updated: 2026-04-25
repo: none
source_inputs:
  - family request
---

# Tokyo June trip

## Goal

Build a four-day family trip with minimal hotel changes.

## Context

Two adults, one child, first time in Tokyo.

## Constraints

Stay under the lodging budget ceiling and keep travel days light.

## Approach

Use one hotel base, cluster activities by neighborhood, and pre-book any
limited-entry activities.

## Open Questions

- Should DisneySea replace one city day?

## Itinerary

- Day 1: Asakusa + Ueno

## Reminders

- Book museum tickets two weeks ahead

## Budget

- Lodging: ...
```

## Proposal Example

```markdown
---
title: Candidate lunch product proposal
kind: universal
status: planned
mode: proposal
created: 2026-04-25
updated: 2026-04-25
repo: none
source_inputs:
  - lunch transcript
---

# Candidate lunch product proposal

## Goal

Turn a candidate conversation into an internal product proposal.

## Context

The source is a meeting transcript with mixed discussion and tangents.

## Constraints

Keep it concise and focused on product scope, team fit, and first milestone.

## Approach

Extract the product idea, ignore unrelated conversation, and frame it as a
proposal with a recommendation and explicit risks.

## Open Questions

- What should count as the first proof point?

## Proposal

- Problem
- User
- Proposed product

## Recommendation

- Start with ...

## Open Risks

- Market timing
- Scope control
```
