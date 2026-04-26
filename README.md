# Agent Combat

Agent Combat is a shell CLI for turning one requirement into an auditable
planning debate between Claude Code and Codex.

The script is intentionally small: one shell file, filesystem artifacts, and
explicit session IDs. It does not run a server or hide the transcript in an
opaque database.

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
./agent-combat --dry-run "build a rate limiter for our API"
./agent-combat --contract-check
./agent-combat -r 1 --no-judge "draft a tiny implementation plan"
./agent-combat --resume debate_YYYYMMDD_HHMMSS
./agent-combat --show debate_YYYYMMDD_HHMMSS
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

## Install Locally

```sh
mkdir -p "$HOME/.local/bin"
ln -sf "$(pwd)/agent-combat" "$HOME/.local/bin/agent-combat"
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
