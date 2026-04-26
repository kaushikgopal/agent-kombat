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

cat >"$TMP_DIR/sample-plan.md" <<'MD'
# Sample Plan

Build a tiny CLI that prints hello.
MD

"$ROOT_DIR/agent-combat" --dry-run --no-interactive --requirement-file "$TMP_DIR/sample-plan.md" \
  "debate this plan" >/tmp/agent-combat-file.out
grep -q "debate this plan" /tmp/agent-combat-file.out
grep -q "Build a tiny CLI that prints hello." /tmp/agent-combat-file.out

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
prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-id|--resume)
      session_id="$2"
      shift 2
      ;;
    *)
      prompt="$1"
      shift
      ;;
  esac
done
[[ -n "$session_id" ]] || session_id="fake-claude-session"
if [[ "$prompt" == *"You are synthesizing the final implementation plan"* ]]; then
  jq -n --arg session_id "$session_id" '{
    type: "result",
    subtype: "success",
    is_error: false,
    session_id: $session_id,
    result: "# Final Plan\n\n- Ship the converged implementation.\n"
  }'
elif [[ "$prompt" == *"Set status to"* ]]; then
  message="fresh"
  if [[ "$prompt" == *"resume"* ]]; then
    message="resume"
  fi
  jq -n --arg session_id "$session_id" --arg message "$message" '{
    type: "result",
    subtype: "success",
    is_error: false,
    session_id: $session_id,
    structured_output: {status: "ok", message: $message},
    result: "Done."
  }'
elif [[ "$prompt" == *"You are an independent judge"* ]]; then
  count_file="${FAKE_JUDGE_COUNT_FILE:-}"
  count=0
  if [[ -n "$count_file" && -f "$count_file" ]]; then
    count="$(cat "$count_file")"
  fi
  count="$((count + 1))"
  if [[ -n "$count_file" ]]; then
    printf '%s\n' "$count" >"$count_file"
  fi
  if [[ "${FAKE_JUDGE_ANOTHER:-}" == "1" && "$count" -eq 1 ]]; then
    jq -n --arg session_id "$session_id" '{
      type: "result",
      subtype: "success",
      is_error: false,
      session_id: $session_id,
      structured_output: {
        converged: false,
        unresolved_issues: ["Artifacts are underspecified."],
        agreements_lacking_justification: [],
        recommendation: "another_round",
        focus_for_next_round: "Resolve artifact paths and resume rules.",
        reasoning: "One focused replay should settle artifact handling."
      },
      result: "Done."
    }'
  else
    jq -n --arg session_id "$session_id" '{
      type: "result",
      subtype: "success",
      is_error: false,
      session_id: $session_id,
      structured_output: {
        converged: true,
        unresolved_issues: [],
        agreements_lacking_justification: [],
        recommendation: "synthesize",
        focus_for_next_round: null,
        reasoning: "The plans now converge enough for synthesis."
      },
      result: "Done."
    }'
  fi
elif [[ "$prompt" == *"strengths_to_steal"* ]]; then
  jq -n --arg session_id "$session_id" '{
    type: "result",
    subtype: "success",
    is_error: false,
    session_id: $session_id,
    structured_output: {
      strengths_to_steal: ["Codex keeps artifacts explicit."],
      revised_plan_markdown: "# Claude Revised Plan\n\n- Build the smallest useful version.\n- Keep artifacts explicit.\n",
      critique: ["The competing plan is too terse."],
      unresolved_issues: [{
        issue: "Scope",
        why_it_matters: "The plan needs an explicit stopping point.",
        suggested_test_or_decision_rule: "Accept if the smoke test passes."
      }]
    },
    result: "Done."
  }'
else
  jq -n --arg session_id "$session_id" '{
    type: "result",
    subtype: "success",
    is_error: false,
    session_id: $session_id,
    structured_output: {plan_markdown: "# Claude Plan\n\n- Build the smallest useful version.\n"},
    result: "Done."
  }'
fi
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
prompt=""
resume_mode=0
if [[ "${1:-}" == "resume" ]]; then
  resume_mode=1
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
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
      if [[ "$resume_mode" -eq 1 ]]; then
        thread_id="$1"
        resume_mode=2
      else
        prompt="$1"
      fi
      shift
      ;;
  esac
done
[[ -n "$output_last" ]] || {
  echo "missing --output-last-message" >&2
  exit 1
}
if [[ "$prompt" == *"strengths_to_steal"* ]]; then
  if [[ "${FAKE_CODEX_FAIL_DEBATE:-}" == "1" ]]; then
    echo "simulated codex debate failure" >&2
    exit 7
  fi
  jq -n '{
    strengths_to_steal: ["Claude keeps the implementation small."],
    revised_plan_markdown: "# Codex Revised Plan\n\n- Keep state auditable on disk.\n- Keep the implementation small.\n",
    critique: ["The competing plan needs clearer artifacts."],
    unresolved_issues: [{
      issue: "Artifacts",
      why_it_matters: "Resume depends on durable files.",
      suggested_test_or_decision_rule: "Accept if r1.json and objections exist."
    }]
  }' >"$output_last"
elif [[ "$prompt" == *'"status":"ok"'* ]]; then
  jq -n '{status: "ok", message: "fresh"}' >"$output_last"
elif [[ "$prompt" == *"Reply with exactly: resumed"* ]]; then
  printf 'resumed\n' >"$output_last"
else
  jq -n '{plan_markdown: "# Codex Plan\n\n- Keep state auditable on disk.\n"}' >"$output_last"
fi
jq -cn --arg thread_id "$thread_id" '{type: "thread.started", thread_id: $thread_id}'
jq -cn '{type: "turn.completed", usage: {}}'
SH

cat >"$FAKE_BIN/gum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo "gum fake"
    ;;
  style)
    printf 'style\n' >>"${FAKE_GUM_LOG:?}"
    shift
    printf '%s\n' "$@"
    ;;
  confirm)
    printf 'confirm\n' >>"${FAKE_GUM_LOG:?}"
    exit 0
    ;;
  *)
    echo "unexpected gum command" >&2
    exit 1
    ;;
esac
SH

chmod +x "$FAKE_BIN/claude" "$FAKE_BIN/codex" "$FAKE_BIN/gum"

FAKE_GUM_LOG="$TMP_DIR/gum.log" script -q "$TMP_DIR/gum.typescript" \
  env PATH="$FAKE_BIN:$PATH" FAKE_GUM_LOG="$TMP_DIR/gum.log" \
  "$ROOT_DIR/agent-combat" --dry-run --interactive "gum display" >/dev/null
grep -q "style" "$TMP_DIR/gum.log"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-combat" \
  --contract-check \
  --workdir "$TMP_DIR/contract" \
  --claude-model fake-claude \
  --codex-model fake-codex >/tmp/agent-combat-contract.out
jq -e '.status == "ok" and .codex.session_id == "fake-codex-thread"' "$TMP_DIR/contract/contract-summary.json" >/dev/null

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-combat" \
  --no-interactive \
  --rounds 1 \
  --no-judge \
  --workdir "$TMP_DIR/run" \
  "draft a tiny implementation plan" >/tmp/agent-combat-round0.out

test -f "$TMP_DIR/run/rounds/r0.json"
test -f "$TMP_DIR/run/rounds/r1.json"
test -f "$TMP_DIR/run/rounds/r1-objections.json"
test -f "$TMP_DIR/run/plan-agent1.md"
test -f "$TMP_DIR/run/plan-agent2.md"
test -f "$TMP_DIR/run/plan-final.md"
jq -e '.published_round == 1 and .agent1.session_id != null and .agent2.session_id == "fake-codex-thread"' "$TMP_DIR/run/config.json" >/dev/null
jq -e '.phase == "done" and .status == "done" and .last_successful_artifact == "plan-final.md"' "$TMP_DIR/run/config.json" >/dev/null
jq -e '.published == true and .agents.agent1.parse_status == "ok" and .agents.agent2.parse_status == "ok"' "$TMP_DIR/run/rounds/r0.json" >/dev/null
jq -e '.published == true and .kind == "debate" and .agents.agent1.parse_status == "ok" and .agents.agent2.parse_status == "ok"' "$TMP_DIR/run/rounds/r1.json" >/dev/null
jq -e '.agent1[0].issue == "Scope" and .agent2[0].issue == "Artifacts"' "$TMP_DIR/run/rounds/r1-objections.json" >/dev/null
grep -q "Claude Revised Plan" "$TMP_DIR/run/plan-agent1.md"
grep -q "Codex Revised Plan" "$TMP_DIR/run/plan-agent2.md"

if PATH="$FAKE_BIN:$PATH" FAKE_CODEX_FAIL_DEBATE=1 "$ROOT_DIR/agent-combat" \
  --no-interactive \
  --rounds 1 \
  --no-judge \
  --workdir "$TMP_DIR/fail-run" \
  "draft a tiny implementation plan" >/tmp/agent-combat-fail.out 2>/tmp/agent-combat-fail.err; then
  echo "expected failed debate run to fail" >&2
  exit 1
fi

test ! -f "$TMP_DIR/fail-run/rounds/r1.json"
jq -e '.published_round == 0 and .last_successful_artifact == "rounds/r0.json"' "$TMP_DIR/fail-run/config.json" >/dev/null
cmp "$TMP_DIR/fail-run/plan-agent1.md" "$TMP_DIR/fail-run/rounds/r0-agent1.md"
cmp "$TMP_DIR/fail-run/plan-agent2.md" "$TMP_DIR/fail-run/rounds/r0-agent2.md"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-combat" \
  --resume "$TMP_DIR/fail-run" >/tmp/agent-combat-resume.out
jq -e '.published_round == 1 and .phase == "done" and .status == "done"' "$TMP_DIR/fail-run/config.json" >/dev/null
test -f "$TMP_DIR/fail-run/rounds/r1.json"
test -f "$TMP_DIR/fail-run/plan-final.md"

"$ROOT_DIR/agent-combat" --show "$TMP_DIR/fail-run" >/tmp/agent-combat-show.out
grep -q "Final plan:" /tmp/agent-combat-show.out

PATH="$FAKE_BIN:$PATH" FAKE_JUDGE_ANOTHER=1 FAKE_JUDGE_COUNT_FILE="$TMP_DIR/judge-count" "$ROOT_DIR/agent-combat" \
  --no-interactive \
  --rounds 0 \
  --max-extra 1 \
  --workdir "$TMP_DIR/judge-run" \
  "draft a tiny implementation plan" >/tmp/agent-combat-judge.out

test -f "$TMP_DIR/judge-run/judge-verdict.json"
test -f "$TMP_DIR/judge-run/rounds/judge-1.json"
test -f "$TMP_DIR/judge-run/rounds/judge-2.json"
test -f "$TMP_DIR/judge-run/rounds/r1-judge-focus.txt"
test -f "$TMP_DIR/judge-run/rounds/r1.json"
test -f "$TMP_DIR/judge-run/plan-final.md"
jq -e '.extra_rounds_used == 1 and .published_round == 1 and .phase == "done" and .status == "done"' "$TMP_DIR/judge-run/config.json" >/dev/null
jq -e '.recommendation == "synthesize" and .converged == true' "$TMP_DIR/judge-run/judge-verdict.json" >/dev/null

mkdir -p "$TMP_DIR/default-cwd"
(
  cd "$TMP_DIR/default-cwd"
  PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-combat" \
    --no-interactive \
    --rounds 0 \
    --max-extra 0 \
    "draft a tiny implementation plan" >/tmp/agent-combat-default.out
)
default_run="$(find "$TMP_DIR/default-cwd" -maxdepth 1 -type d -name 'debate_*' | sort | tail -n 1)"
test -n "$default_run"
test -f "$default_run/requirement.txt"
test -f "$default_run/config.json"
test -f "$default_run/events.jsonl"
test -d "$default_run/rounds"
test -f "$default_run/plan-agent1.md"
test -f "$default_run/plan-agent2.md"
test -f "$default_run/judge-verdict.json"
test -f "$default_run/plan-final.md"
