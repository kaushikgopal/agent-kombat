# Software Plan Template

```markdown
---
title: <short descriptive title>
kind: software
status: planned
mode: feature | fix | refactor | investigation
created: YYYY-MM-DD
updated: YYYY-MM-DD
repo: <repo-name>
source_inputs:
  - <issue, transcript, URL, note>
---

# <Title>

## Goal

## Context

## Constraints

## Existing Patterns

## Approach

## Files

- `path/to/file`

## Tasks

- [ ] Task 1
- [ ] Task 2

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Validation

- `command or check`

## Risks

- risk

## Decision

## Options

## Evaluation Criteria

## Evidence

## Recommendation

## Next Experiment

## Open Questions

- question

## Implementation Units

- U1. **<Name>**
  - Goal: ...
  - Files: ...
  - Approach: ...
  - Test scenarios: ...
  - Verification: ...
```

Notes:

- omit `## Implementation Units` when the work is small enough that flat tasks
  are clearer
- omit the decision-oriented sections unless the software mode is
  `investigation`
- keep the plan at decision level; avoid pseudocode and line-by-line coding
  instructions
