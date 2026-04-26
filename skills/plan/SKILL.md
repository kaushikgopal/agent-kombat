---
name: plan
description: >-
  Create or refine a durable plan note for software and non-software work.
  Use when the user has an idea, bug, issue, transcript, screenshot, or rough
  prompt that should become a structured plan under .agents/plans before
  execution begins.
argument-hint: >-
  plan this auth bug | plan this meeting transcript into a proposal | plan
  .agents/plans/2026-04-25-auth-rewrite-plan.md
allowed-tools: Bash, Read, Write, AskUserQuestion, WebSearch
user-invocable: true
metadata:
  author: kaushik-gopal
  version: "0.3"
---

# Plan

`/plan` is the entry point for turning rough inputs into durable plan notes.

Run the classifier helper before doing anything else:

```bash
python3 "$SKILL_DIR/scripts/plan_core.py" classify \
  --repo-root "$PWD" \
  --plans-dir "$PWD/.agents/plans" \
  --request "$ARGUMENTS"
```

The classifier returns:

- `action` - `create` or `refine`
- `kind` - `software`, `universal`, or `null`
- `mode` - informational mode for the plan note
- `existing_plan_path` - existing plan file when refining
- `target_path` - where the plan should be written
- `plans_dir` - directory used for new plan notes
- `contract_path` - durable plan contract reference
- `routing_path` - routing and research rules reference
- `template_path` - template reference to follow
- `should_consider_external_research`
- `should_consider_fanout_research`
- `needs_clarification`
- `clarification_prompt`
- `explanation`

For a file-backed request, use:

```bash
python3 "$SKILL_DIR/scripts/plan_core.py" classify \
  --repo-root "$PWD" \
  --plans-dir "$PWD/.agents/plans" \
  --request-file path/to/request.txt
```

If `needs_clarification` is `true`, ask `clarification_prompt` and stop.
Do not guess.

Then tell the user the route in one short line:

- `Routing to software planning for {request}.`
- `Routing to universal planning for {request}.`
- `Refining existing plan at {existing_plan_path}.`

## Source Of Truth

The portable core and canonical CLI live in:

- [scripts/plan_core.py](scripts/plan_core.py)

Use it for classification, reusable planning instructions, and validation.

Prompt adapters such as Agent Kombat should own their outer prompt wrapper and
splice in shared planning instructions from:

```bash
python3 "$SKILL_DIR/scripts/plan_core.py" render-instructions \
  --classification classification.json
```

The plan note contract lives in:

- [references/plan-contract.md](references/plan-contract.md)

Read it before writing or mutating any plan note.

Use:

- [references/routing.md](references/routing.md) for routing and research rules
- [references/plan-template-software.md](references/plan-template-software.md)
  for software plans
- [references/plan-template-universal.md](references/plan-template-universal.md)
  for universal plans
- [references/subagent-prompts.md](references/subagent-prompts.md) only when you
  need the context fan-out workflow or canned prompts for parallel research

## Context Fan-Out

Do not fan out for every plan. Use it when the classifier returns
`should_consider_fanout_research: true`, or when a software request is large,
ambiguous, cross-cutting, risky, or in an unfamiliar/complex codebase.

When fan-out is warranted, gather independent context before writing the plan:

- what the repo already does
- whether prior plans, notes, or repo-local knowledge solved this before
- what current docs/community examples say, when freshness matters
- which tests, edge cases, and validation surfaces matter

Use [references/subagent-prompts.md](references/subagent-prompts.md) for the
fan-out workflow. If subagents are unavailable or unnecessary, answer the same
questions locally. Synthesize only load-bearing findings into the plan; do not
paste raw research logs.

## External Research

Do not automatically run external research for every plan.

If the classifier returns `should_consider_external_research: true` and the
user did not already provide fresh research, first classify the same request
through the existing research wrapper.

Use a compatible Python interpreter in this repo:

```bash
PYTHON_BIN="$(command -v python3.13 || command -v python3)"
```

Then run:

```bash
$PYTHON_BIN skills/research/scripts/research.py --classify $ARGUMENTS
```

If that research classifier returns a non-empty topic and does not require
clarification, run:

```bash
$PYTHON_BIN skills/research/scripts/research.py --exec-last30days $ARGUMENTS
```

Then summarize only the load-bearing takeaways into the plan note's
`## Context` section. Do not dump raw evidence into the plan.

## Validation

Before calling a plan note complete, validate it:

```bash
python3 "$SKILL_DIR/scripts/plan_core.py" validate --plan-file "$PLAN_PATH"
```

Validation is intentionally lenient: missing optional sections warn, while
broken frontmatter, wrong `kind`, missing required sections, and invalid task
checkbox structure fail.

## Writing Rules

- Always write plan notes under `.agents/plans/` in the repo where the skill
  was invoked, not in the skill package directory.
- Use the classifier's `target_path`.
- Keep file paths inside the plan repo-relative.
- Preserve existing completed work when refining a plan.
- Use implementation units only when the software task is large enough that
  stable unit identities help execution.
- Keep the plan at decision level. Do not turn it into pseudocode or a task log.
- For software plans, inspect the repo first. If you cannot find plausible
  files, patterns, or code to ground the plan, ask for the target repo or files
  instead of drafting a confident but ungrounded plan.
