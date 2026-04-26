#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$ROOT_DIR/agent-combat"

"$ROOT_DIR/agent-combat" --dry-run --no-interactive --workdir "$TMP_DIR/dry" "build a rate limiter" >/tmp/agent-combat-dry.out
test ! -e "$TMP_DIR/dry"
grep -q "Dry run: no agent calls will be made" /tmp/agent-combat-dry.out

if "$ROOT_DIR/agent-combat" --no-interactive >/tmp/agent-combat-missing.out 2>&1; then
  echo "expected missing requirement to fail" >&2
  exit 1
fi
grep -q "missing requirement" /tmp/agent-combat-missing.out

"$ROOT_DIR/agent-combat" --dry-run --no-interactive --rounds 1 --no-judge "draft a tiny implementation plan" >/tmp/agent-combat-cheap.out
grep -q '"rounds_planned": 1' /tmp/agent-combat-cheap.out
grep -q '"judge_enabled": false' /tmp/agent-combat-cheap.out

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "2.1.120 (Claude Code)"
  exit 0
fi
session_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id|--resume)
      session_id="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$session_id" ]] || session_id="fake-claude-session"
jq -n --arg session_id "$session_id" '{
  type: "result",
  subtype: "success",
  is_error: false,
  session_id: $session_id,
  structured_output: {plan_markdown: "# Claude Plan\n\n- Build the smallest useful version.\n"},
  result: "Done."
}'
SH

cat >"$FAKE_BIN/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  echo "codex-cli 0.125.0"
  exit 0
fi
if [[ "${1:-}" != "exec" ]]; then
  echo "unexpected codex command" >&2
  exit 1
fi
shift
output_last=""
thread_id="fake-codex-thread"
while [[ $# -gt 0 ]]; do
  case "$1" in
    resume)
      shift
      thread_id="${1:-$thread_id}"
      shift || true
      ;;
    --output-last-message)
      output_last="$2"
      shift 2
      ;;
    --model|--sandbox|--output-schema)
      shift 2
      ;;
    --json|--skip-git-repo-check)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$output_last" ]] || {
  echo "missing --output-last-message" >&2
  exit 1
}
jq -n '{plan_markdown: "# Codex Plan\n\n- Keep state auditable on disk.\n"}' >"$output_last"
jq -cn --arg thread_id "$thread_id" '{type: "thread.started", thread_id: $thread_id}'
jq -cn '{type: "turn.completed", usage: {}}'
SH

chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/codex"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-combat" \
  --no-interactive \
  --rounds 0 \
  --no-judge \
  --workdir "$TMP_DIR/run" \
  "draft a tiny implementation plan" >/tmp/agent-combat-round0.out

test -f "$TMP_DIR/run/rounds/r0.json"
test -f "$TMP_DIR/run/plan-agent1.md"
test -f "$TMP_DIR/run/plan-agent2.md"
jq -e '.published_round == 0 and .agent1.session_id != null and .agent2.session_id == "fake-codex-thread"' "$TMP_DIR/run/config.json" >/dev/null
jq -e '.published == true and .agents.agent1.parse_status == "ok" and .agents.agent2.parse_status == "ok"' "$TMP_DIR/run/rounds/r0.json" >/dev/null
