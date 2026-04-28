# Agent Kombat

Agent Kombat turns one prompt, plan, or custom artifact request into a debate
between Claude Code and Codex. It saves the debate, judge verdict, and final
artifact as plain files you can inspect or resume.

To understand the purpose of this tool, how I use it, and why it is valuable,
read the full blog post at https://kau.sh/blog/agent-kombat.

## Cheat Sheet

### Pick the Right Contract

Use this rule before running the tool:

| User wants | Command shape | Final file |
|---|---|---|
| A plan for doing work | `agent-kombat "plan ..."` or `agent-kombat --contract plan "..."` | `plan-final.md` |
| The artifact itself | `agent-kombat --contract artifact "draft/write/produce ..."` | `artifact-final.md` |
| A typed artifact with stronger vocabulary | `agent-kombat --contract path/to/contract.json "..."` | contract-defined |

Default to `plan` only when the desired output is a durable plan note,
implementation plan, strategy plan, investigation plan, or refinement of an
existing plan. Use `artifact` when the user asks for final copy, a brief, PRD,
memo, critique, postmortem, release note, proposal, or any other deliverable
that should not be plan-shaped.

Concrete examples:

```sh
# Debate a plan
agent-kombat "plan a tiny CLI that prints hello"

# Debate final copy, not a writing plan
agent-kombat --contract artifact \
  "draft the actual executive brief from @brief-source.md"

# Use a typed contract when the deliverable needs a named noun/schema
agent-kombat --contract .agents/kombat-contracts/executive-brief.json \
  "draft the Project Trinity executive brief from @.agents/plans/project-trinity-synthetic-data-prompt.md"
```

When a prompt says "not a plan," "actual brief," "final copy," or "deliverable
itself," do not rely on prompt wording alone. Pass `--contract artifact` or a
custom contract explicitly.

### Guided UI

Start the guided UI:

```sh
./agent-kombat
```

Abbreviated output:

```text
AGENT KOMBAT
Start with a prompt, an existing plan file, or both.

> Write a prompt
  Use an existing plan file
  Prompt + plan file
```

### Write a Prompt

Run the usual debate from a prompt:

```sh
./agent-kombat "plan a tiny CLI that prints hello"
```

Abbreviated output:

```text
==> Agent Kombat
Agent 1: Claude Code (opus)
Agent 2: Codex CLI (gpt-5)
Judge: Claude Code (opus)
Contract: plan (plan)
Rounds: 3 + up to 1 replay
Requirement: plan a tiny CLI that prints hello
Workdir: debate_YYYYMMDD_HHMMSS
==> Round 0: independent plan generation
ok: Round 0 published
==> Round 1: debate
ok: Round 1 published
==> Round 2: debate
ok: Round 2 published
==> Round 3: debate
ok: Round 3 published
==> Judge attempt 1
ok: Judge verdict written
ok: Final plan: debate_YYYYMMDD_HHMMSS/plan-final.md
```

### Debate a Non-Plan Artifact

Use the built-in `artifact` contract when you want the agents to produce the
requested artifact itself instead of a plan for producing it:

```sh
./agent-kombat --contract artifact "draft an executive brief from @brief-source.md"
```

This keeps the same classification, grounding context, debate rounds, judge,
replay, and synthesis machinery, but changes the schema and prompts so Round 0
produces artifacts, debate rounds revise artifacts, and synthesis writes:

```text
debate_YYYYMMDD_HHMMSS/artifact-final.md
```

The default `plan` contract is unchanged:

```sh
./agent-kombat --contract plan "plan a tiny CLI that prints hello"
```

### Custom Contracts

Use a JSON contract when the deliverable needs more specific language than the
generic `artifact` contract:

```json
{
  "id": "executive-brief",
  "noun": "brief",
  "output_field": "brief_markdown",
  "revised_field": "revised_brief_markdown",
  "final_filename": "brief-final.md",
  "final_label": "Final brief",
  "context_mode": "context",
  "initial_task": "Draft the requested executive brief.",
  "debate_task": "Revise your own brief after reviewing a competing brief.",
  "synthesis_task": "Produce the final requested executive brief from the debate.",
  "round0_note": "Do not output a plan; output the brief itself.",
  "synthesis_note": "Return the final brief copy only."
}
```

Run it with:

```sh
./agent-kombat --contract .agents/kombat-contracts/executive-brief.json \
  "draft the Project Trinity executive brief from @.agents/plans/project-trinity-synthetic-data.md"
```

`context_mode` controls how much of the planning machinery is injected:

- `instructions`: full durable plan-note contract and templates. This is the
  default for `plan`.
- `context`: classification and grounding context without plan-note output
  rules. This is the default for `artifact`.
- `none`: no shared planning context beyond the original requirement.

### Use an Existing Plan File

Use `@file` when the plan already exists and you want Agent Kombat to load it:

```sh
./agent-kombat "@sample-plan.md"
```

Agent Kombat writes the expanded prompt to `requirement.txt`:

```text
@sample-plan.md

<user-input-plan>
source: sample-plan.md
# Sample Plan

...
</user-input-plan>
```

### Prompt + Plan File

Add instructions around the `@file` reference when you want to steer the debate:

```sh
./agent-kombat "debate @sample-plan.md and focus on missing risks"
```

Agent Kombat writes the expanded prompt to `requirement.txt`:

```text
debate @sample-plan.md and focus on missing risks

<user-input-plan>
source: sample-plan.md
# Sample Plan

...
</user-input-plan>
```

### Preview and Inspect

Preview the run without calling either agent:

```sh
./agent-kombat --dry-run "build a rate limiter"
```

Abbreviated output:

```text
==> Dry run: no agent calls will be made
==> Agent Kombat
Rounds: 3 + up to 1 replay
Requirement: build a rate limiter
...
"rounds_planned": 3,
"judge_enabled": true,
"status": "dry-run"
```

Inspect the latest durable state:

```sh
./agent-kombat --show debate_YYYYMMDD_HHMMSS
```

Abbreviated output:

```text
{
  "status": "done",
  "phase": "done",
  "published_round": 3,
  "last_successful_artifact": "plan-final.md"
}

Agent 1 plan: debate_YYYYMMDD_HHMMSS/plan-agent1.md
Agent 2 plan: debate_YYYYMMDD_HHMMSS/plan-agent2.md
Judge verdict: debate_YYYYMMDD_HHMMSS/judge-verdict.json
Final plan: debate_YYYYMMDD_HHMMSS/plan-final.md
```

### Resume and Tune Rounds

Resume an interrupted run:

```sh
./agent-kombat --resume debate_YYYYMMDD_HHMMSS
```

Use fewer rounds when the decision is small:

```sh
./agent-kombat -r 1 --no-judge "draft a tiny implementation plan"
```

Run only one debate round but keep the judge:

```sh
./agent-kombat -r 1 "compare two API designs"
```

Validate local CLI contracts:

```sh
./agent-kombat --contract-check
```

## Requirements

- `bash`
- `jq`
- `python3`
- `claude`
- `codex`
- Optional: `gum` for the guided terminal UI and in-progress status panels

## Install

```sh
git clone https://github.com/kaushikgopal/agent-kombat.git
cd agent-kombat
mkdir -p "$HOME/.local/bin"
ln -sf "$PWD/agent-kombat" "$HOME/.local/bin/agent-kombat"
```

Make sure `~/.local/bin` is on your `PATH`.

Verify the install:

```sh
agent-kombat --help
```

## Bundled Plan Skill

This repo includes a complete Agent Skills-compatible planning skill at
`skills/plan`. The directory is self-contained: `SKILL.md`, `agents/`,
`references/`, and `scripts/` live together so the skill can be copied or
symlinked into another skills root as one directory.

The skill chooses plan storage from the directory where it is invoked. It uses
an existing `.agents/plans/` first, then a repo-local recommended plans
directory from guidance files, then an XDG state fallback. If `skills/plan` is
symlinked into another repo, run the skill from that repo so the local project
controls where new plans land.

Agent Kombat uses `skills/plan/scripts/plan_core.py` during Round 0 to classify
the requirement. The `plan` contract injects the full shared plan contract into
both independent prompts. Non-plan contracts can instead inject context-only
grounding, so the planning machinery still informs the debate without forcing a
plan-shaped output. It does not invoke the skill adapter directly, so Claude and
Codex still create real sessions that later debate rounds can resume.

## Notes

By default, Agent Kombat runs the `plan` contract: Round 0 independent plan
generation, then 3 debate rounds, then a judge pass that can request up to 1
focused replay round.

`@file` references are expanded by the broker before agents are called. The file
content is treated as input data, not instructions to execute.

Agent calls are execution-disabled by default. Claude is invoked with tools
disabled and plan permission mode. Codex is invoked with a read-only sandbox and
explicit prompts that forbid command execution for debate turns.
