# Agent Kombat

Agent Kombat is a shell CLI for turning one requirement into an auditable
planning debate between Claude Code and Codex.

The script is intentionally small: one shell file, filesystem artifacts, and
explicit session IDs. It does not run a server or hide the transcript in an
opaque database.

## Quick Start

Run `agent-kombat` by itself to open the guided intake UI:

```sh
./agent-kombat
```

With `gum` installed, the UI lets you choose one of three input shapes:

```text
AGENT KOMBAT
Start with a prompt, an existing plan file, or both.

> Write a prompt
  Use an existing plan file
  Prompt + plan file
```

Run a cheap one-round planning debate:

```sh
./agent-kombat --no-judge -r 1 "build a tiny CLI that prints hello"
```

Agent Kombat writes a timestamped `debate_*` directory with each agent's plan,
the debate transcript artifacts, and a final synthesized plan:

```sh
./agent-kombat --show debate_YYYYMMDD_HHMMSS
cat debate_YYYYMMDD_HHMMSS/plan-final.md
```

Use `--dry-run` first if you want to inspect the selected models and output
directory without calling either agent.

## Input Depth

Agent Kombat can take anything from a sentence to a full existing plan. Use a
short prompt when the decision space is small:

```sh
./agent-kombat "choose an implementation plan for a tiny hello-world CLI"
```

Use a richer prompt when you already know the constraints:

```sh
./agent-kombat --no-judge -r 1 \
  "plan a POSIX shell CLI; keep it one file; include tests and install docs"
```

Use `--requirement-file` when the source input is already a document:

```sh
./agent-kombat --requirement-file sample-plan.md \
  "Debate this plan. Find missing risks, unclear sequencing, and better tests."
```

That command copies the file content into `requirement.txt` and asks both agents
to plan from it. The file is treated as input data, not instructions to execute.

Do not rely on a prompt like `read sample-plan.md` by itself. Agent Kombat keeps
agent calls planning-only, so the broker should read the file and pass the
content into the debate explicitly.

## Requirements

- `bash`
- `jq`
- `claude`
- `codex`
- Optional: `gum` for a cleaner terminal display

Install `gum` from <https://github.com/charmbracelet/gum#installation> if you
want the nicer presentation. The CLI works without it.

## Usage

```sh
./agent-kombat --dry-run "build a rate limiter for our API"
./agent-kombat --contract-check
./agent-kombat -r 1 --no-judge "draft a tiny implementation plan"
./agent-kombat --requirement-file sample-plan.md "debate this plan"
./agent-kombat --resume debate_YYYYMMDD_HHMMSS
./agent-kombat --show debate_YYYYMMDD_HHMMSS
```

The default run creates a timestamped directory:

```text
debate_YYYYMMDD_HHMMSS/
├── requirement.txt
├── config.json
├── events.jsonl
├── plan-agent1.md
├── plan-agent2.md
├── plan-final.md
├── judge-verdict.json
└── rounds/
```

`config.json` is durable state. It records the origin working directory,
selected harnesses, models, session IDs, published round, and replay counters.
Resume logic must use those explicit session IDs, never a CLI's "last session"
shortcut.

## Example Output

A normal run prints progress like this:

```text
==> Agent Kombat
Agent 1: Claude Code (opus)
Agent 2: Codex CLI (gpt-5)
Judge: Claude Code (opus)
Rounds: 1 + up to 1 replay
Requirement: build a tiny CLI that prints hello
Workdir: /path/to/debate_YYYYMMDD_HHMMSS
==> Round 0: independent planning
ok: Round 0 published
==> Round 1: debate
ok: Round 1 published
==> Judge attempt 1
ok: Judge verdict written
ok: Final plan: debate_YYYYMMDD_HHMMSS/plan-final.md
```

`--show` summarizes the durable state and artifact paths:

```text
{
  "status": "done",
  "phase": "done",
  "published_round": 1,
  "current_round": 2,
  "rounds_planned": 1,
  "last_successful_artifact": "plan-final.md"
}

Agent 1 plan: debate_YYYYMMDD_HHMMSS/plan-agent1.md
Agent 2 plan: debate_YYYYMMDD_HHMMSS/plan-agent2.md
Judge verdict: debate_YYYYMMDD_HHMMSS/judge-verdict.json
Final plan: debate_YYYYMMDD_HHMMSS/plan-final.md
```

The final plan is Markdown:

```markdown
# Final Plan

## Goal

Build a one-file CLI that prints `hello` and exits successfully.

## Implementation Steps

1. Create the executable script.
2. Add a smoke test for stdout and exit code.
3. Document local install and usage.
```

## Install Locally

```sh
mkdir -p "$HOME/.local/bin"
ln -sf "$(pwd)/agent-kombat" "$HOME/.local/bin/agent-kombat"
```

Fish users can add the bin directory for the current shell with:

```fish
fish_add_path "$HOME/.local/bin"
```

## Stable Wrapper Surface

Future wrappers should call the script, not reimplement the broker.

- `--dry-run REQUIREMENT` prints the selected configuration and avoids agent calls.
- `--contract-check` validates the installed Claude and Codex automation surface.
- `--no-interactive` prevents prompts.
- `--requirement-file FILE` reads the requirement from a document.
- `--workdir DIR` chooses the artifact directory.
- `--show WORKDIR` prints the latest state.
- `--resume WORKDIR` resumes from durable state.

`--resume` reconstructs progress from published round manifests, restores the
top-level live plan files from the last complete round, and continues from the
next round. It never uses a CLI "last session" shortcut; Claude and Codex resume
only from session IDs stored in `config.json`.

Exit codes:

- `0`: success
- `1`: usage or validation failure
- `2`: missing dependency or failed CLI contract

## Planning Restrictions

Agent calls are planning-only by default. Claude is invoked with tools disabled
and plan permission mode. Codex is invoked with a read-only sandbox and explicit
prompts that forbid command execution for debate turns. Opponent plans are
treated as untrusted data to critique, not instructions to follow.
