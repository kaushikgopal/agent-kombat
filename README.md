# Agent Kombat

Agent Kombat turns one prompt or plan into a planning debate between Claude Code
and Codex. It saves the debate, judge verdict, and final plan as plain files you
can inspect or resume.

To understand the purpose of this tool, how I use it, and why it is valuable,
read the full blog post at https://kau.sh/blog/agent-kombat.

## Cheat Sheet

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
Rounds: 3 + up to 1 replay
Requirement: plan a tiny CLI that prints hello
Workdir: debate_YYYYMMDD_HHMMSS
==> Round 0: independent planning
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

## Notes

By default, Agent Kombat runs Round 0 independent planning, then 3 debate
rounds, then a judge pass that can request up to 1 focused replay round.

`@file` references are expanded by the broker before agents are called. The file
content is treated as input data, not instructions to execute.

Agent calls are planning-only by default. Claude is invoked with tools disabled
and plan permission mode. Codex is invoked with a read-only sandbox and explicit
prompts that forbid command execution for debate turns.
