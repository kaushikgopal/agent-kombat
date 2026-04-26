#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash -n "$ROOT_DIR/agent-kombat"
python3 -m py_compile "$ROOT_DIR/skills/plan/scripts/plan_core.py"

PLAN_CORE="$ROOT_DIR/skills/plan/scripts/plan_core.py"

mkdir -p "$TMP_DIR/plan-local/.agents/plans"
python3 "$PLAN_CORE" classify --repo-root "$TMP_DIR/plan-local" --request "fix auth bug" \
  >"$TMP_DIR/plan-local.json"
jq -e --arg dir "$TMP_DIR/plan-local/.agents/plans" \
  '.plans_dir == $dir and .plans_dir_source == "existing-local"' \
  "$TMP_DIR/plan-local.json" >/dev/null

mkdir -p "$TMP_DIR/plan-guidance"
printf '%s\n' 'Use `docs/plans` as the recommended directory for plans.' \
  >"$TMP_DIR/plan-guidance/AGENTS.md"
python3 "$PLAN_CORE" classify --repo-root "$TMP_DIR/plan-guidance" --request "fix auth bug" \
  >"$TMP_DIR/plan-guidance.json"
jq -e --arg dir "$TMP_DIR/plan-guidance/docs/plans" \
  '.plans_dir == $dir and .plans_dir_source == "repo-guidance"' \
  "$TMP_DIR/plan-guidance.json" >/dev/null

mkdir -p "$TMP_DIR/plan-xdg"
XDG_STATE_HOME="$TMP_DIR/xdg-state" python3 "$PLAN_CORE" classify \
  --repo-root "$TMP_DIR/plan-xdg" \
  --request "fix auth bug" \
  >"$TMP_DIR/plan-xdg.json"
jq -e --arg prefix "$TMP_DIR/xdg-state/agent-skills/plan/plan-xdg-" \
  '.plans_dir_source == "xdg-state" and (.plans_dir | startswith($prefix)) and (.plans_dir | endswith("/plans"))' \
  "$TMP_DIR/plan-xdg.json" >/dev/null

"$ROOT_DIR/agent-kombat" --dry-run --no-interactive --workdir "$TMP_DIR/dry" "build a rate limiter" >/tmp/agent-kombat-dry.out
test ! -e "$TMP_DIR/dry"
grep -q "Dry run: no agent calls will be made" /tmp/agent-kombat-dry.out
grep -q "Workdir: $TMP_DIR/dry" /tmp/agent-kombat-dry.out
grep -q "\"workdir\": \"$TMP_DIR/dry\"" /tmp/agent-kombat-dry.out

mkdir -p "$TMP_DIR/existing-dry"
if "$ROOT_DIR/agent-kombat" --dry-run --no-interactive --workdir "$TMP_DIR/existing-dry" \
  "build a rate limiter" >/tmp/agent-kombat-dry-collision.out 2>&1; then
  echo "expected dry-run workdir collision to fail" >&2
  exit 1
fi
grep -q "workdir already exists: $TMP_DIR/existing-dry" /tmp/agent-kombat-dry-collision.out

"$ROOT_DIR/agent-kombat" --dry-run --no-interactive --claude-model sonnet "x" >/tmp/agent-kombat-judge-model.out
grep -q "Judge: Claude Code (sonnet)" /tmp/agent-kombat-judge-model.out
jq -e '.judge.model == "sonnet" and .judge.model_source == "derived:claude"' \
  <(sed -n '/^{/,$p' /tmp/agent-kombat-judge-model.out) >/dev/null

if "$ROOT_DIR/agent-kombat" --no-interactive >/tmp/agent-kombat-missing.out 2>&1; then
  echo "expected missing requirement to fail" >&2
  exit 1
fi
grep -q "missing requirement" /tmp/agent-kombat-missing.out

"$ROOT_DIR/agent-kombat" --dry-run --no-interactive --rounds 1 --no-judge "draft a tiny implementation plan" >/tmp/agent-kombat-cheap.out
grep -q '"rounds_planned": 1' /tmp/agent-kombat-cheap.out
grep -q '"judge_enabled": false' /tmp/agent-kombat-cheap.out

cat >"$TMP_DIR/sample-plan.md" <<'MD'
# Sample Plan

Build a tiny CLI that prints hello.
MD

"$ROOT_DIR/agent-kombat" --dry-run --no-interactive --requirement-file "$TMP_DIR/sample-plan.md" \
  "debate this plan" >/tmp/agent-kombat-file.out
grep -q "debate this plan" /tmp/agent-kombat-file.out
grep -q -- "<user-input-plan>" /tmp/agent-kombat-file.out
grep -q -- "source: $TMP_DIR/sample-plan.md" /tmp/agent-kombat-file.out
grep -q -- "</user-input-plan>" /tmp/agent-kombat-file.out
grep -q "Build a tiny CLI that prints hello." /tmp/agent-kombat-file.out

"$ROOT_DIR/agent-kombat" --dry-run --no-interactive \
  "debate @$TMP_DIR/sample-plan.md and focus on missing risks" >/tmp/agent-kombat-at-file.out
grep -q "debate @$TMP_DIR/sample-plan.md" /tmp/agent-kombat-at-file.out
grep -q -- "<user-input-plan>" /tmp/agent-kombat-at-file.out
grep -q -- "source: $TMP_DIR/sample-plan.md" /tmp/agent-kombat-at-file.out
grep -q -- "</user-input-plan>" /tmp/agent-kombat-at-file.out
grep -q "Build a tiny CLI that prints hello." /tmp/agent-kombat-at-file.out

if "$ROOT_DIR/agent-kombat" --dry-run --no-interactive \
  "debate @$TMP_DIR/missing-plan.md" >/tmp/agent-kombat-missing-ref.out 2>&1; then
  echo "expected missing @file to fail" >&2
  exit 1
fi
grep -q "referenced @file does not exist" /tmp/agent-kombat-missing-ref.out

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
if [[ -n "${FAKE_CODEX_ARGS_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$FAKE_CODEX_ARGS_LOG"
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
    -c|--config)
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
next_response() {
  if [[ -n "${FAKE_GUM_RESPONSES_FILE:-}" && -f "$FAKE_GUM_RESPONSES_FILE" ]]; then
    local first
    first="$(sed -n '1p' "$FAKE_GUM_RESPONSES_FILE")"
    sed '1d' "$FAKE_GUM_RESPONSES_FILE" >"$FAKE_GUM_RESPONSES_FILE.tmp"
    mv "$FAKE_GUM_RESPONSES_FILE.tmp" "$FAKE_GUM_RESPONSES_FILE"
    printf '%s\n' "$first"
  fi
}
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
  choose|input|write)
    printf '%s\n' "$1" >>"${FAKE_GUM_LOG:?}"
    next_response
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
  "$ROOT_DIR/agent-kombat" --dry-run --interactive "gum display" >/dev/null
grep -q "style" "$TMP_DIR/gum.log"

cat >"$TMP_DIR/gum-responses" <<EOF
Prompt + plan file
focus on missing risks
$TMP_DIR/sample-plan.md
EOF

FAKE_GUM_LOG="$TMP_DIR/intake-gum.log" script -q "$TMP_DIR/intake.typescript" \
  env PATH="$FAKE_BIN:$PATH" \
  FAKE_GUM_LOG="$TMP_DIR/intake-gum.log" \
  FAKE_GUM_RESPONSES_FILE="$TMP_DIR/gum-responses" \
  "$ROOT_DIR/agent-kombat" --dry-run >/tmp/agent-kombat-intake.out
grep -q "choose" "$TMP_DIR/intake-gum.log"
grep -q "write" "$TMP_DIR/intake-gum.log"
grep -q "input" "$TMP_DIR/intake-gum.log"
grep -q "focus on missing risks" /tmp/agent-kombat-intake.out
grep -q "Build a tiny CLI that prints hello." /tmp/agent-kombat-intake.out

FAKE_GUM_LOG="$TMP_DIR/run-gum.log" script -q "$TMP_DIR/run-gum.typescript" \
  env PATH="$FAKE_BIN:$PATH" \
  FAKE_GUM_LOG="$TMP_DIR/run-gum.log" \
  "$ROOT_DIR/agent-kombat" \
  --no-interactive \
  --rounds 0 \
  --max-extra 0 \
  --no-judge \
  --workdir "$TMP_DIR/gum-run" \
  "draft a tiny implementation plan" >/dev/null
grep -q "Waiting for Claude Code" "$TMP_DIR/run-gum.typescript"
grep -q "Waiting for Codex CLI" "$TMP_DIR/run-gum.typescript"
grep -q "Writing: rounds/r0-agent1.raw.json" "$TMP_DIR/run-gum.typescript"
grep -q "Waiting for final synthesis" "$TMP_DIR/run-gum.typescript"

PATH="$FAKE_BIN:$PATH" FAKE_CODEX_ARGS_LOG="$TMP_DIR/codex-contract-args.log" "$ROOT_DIR/agent-kombat" \
  --contract-check \
  --workdir "$TMP_DIR/contract" \
  --claude-model fake-claude \
  --codex-model fake-codex >/tmp/agent-kombat-contract.out
jq -e '.status == "ok" and .codex.session_id == "fake-codex-thread"' "$TMP_DIR/contract/contract-summary.json" >/dev/null
grep -Fq 'resume -c sandbox_mode="read-only"' "$TMP_DIR/codex-contract-args.log"

PATH="$FAKE_BIN:$PATH" FAKE_CODEX_ARGS_LOG="$TMP_DIR/codex-run-args.log" "$ROOT_DIR/agent-kombat" \
  --no-interactive \
  --rounds 1 \
  --no-judge \
  --workdir "$TMP_DIR/run" \
  "draft a tiny implementation plan" >/tmp/agent-kombat-round0.out

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
grep -Fq 'resume -c sandbox_mode="read-only"' "$TMP_DIR/codex-run-args.log"

if PATH="$FAKE_BIN:$PATH" FAKE_CODEX_FAIL_DEBATE=1 "$ROOT_DIR/agent-kombat" \
  --no-interactive \
  --rounds 1 \
  --no-judge \
  --workdir "$TMP_DIR/fail-run" \
  "draft a tiny implementation plan" >/tmp/agent-kombat-fail.out 2>/tmp/agent-kombat-fail.err; then
  echo "expected failed debate run to fail" >&2
  exit 1
fi

test ! -f "$TMP_DIR/fail-run/rounds/r1.json"
jq -e '.published_round == 0 and .last_successful_artifact == "rounds/r0.json"' "$TMP_DIR/fail-run/config.json" >/dev/null
cmp "$TMP_DIR/fail-run/plan-agent1.md" "$TMP_DIR/fail-run/rounds/r0-agent1.md"
cmp "$TMP_DIR/fail-run/plan-agent2.md" "$TMP_DIR/fail-run/rounds/r0-agent2.md"

PATH="$FAKE_BIN:$PATH" FAKE_CODEX_ARGS_LOG="$TMP_DIR/codex-resume-args.log" "$ROOT_DIR/agent-kombat" \
  --resume "$TMP_DIR/fail-run" >/tmp/agent-kombat-resume.out
jq -e '.published_round == 1 and .phase == "done" and .status == "done"' "$TMP_DIR/fail-run/config.json" >/dev/null
test -f "$TMP_DIR/fail-run/rounds/r1.json"
test -f "$TMP_DIR/fail-run/plan-final.md"
grep -Fq 'resume -c sandbox_mode="read-only"' "$TMP_DIR/codex-resume-args.log"

"$ROOT_DIR/agent-kombat" --show "$TMP_DIR/fail-run" >/tmp/agent-kombat-show.out
grep -q "Final plan:" /tmp/agent-kombat-show.out

PATH="$FAKE_BIN:$PATH" FAKE_JUDGE_ANOTHER=1 FAKE_JUDGE_COUNT_FILE="$TMP_DIR/judge-count" "$ROOT_DIR/agent-kombat" \
  --no-interactive \
  --rounds 0 \
  --max-extra 1 \
  --workdir "$TMP_DIR/judge-run" \
  "draft a tiny implementation plan" >/tmp/agent-kombat-judge.out

test -f "$TMP_DIR/judge-run/judge-verdict.json"
test -f "$TMP_DIR/judge-run/rounds/judge-1.json"
test -f "$TMP_DIR/judge-run/rounds/judge-2.json"
test -f "$TMP_DIR/judge-run/rounds/r1-judge-focus.txt"
test -f "$TMP_DIR/judge-run/rounds/r1.json"
test -f "$TMP_DIR/judge-run/plan-final.md"
jq -e '.extra_rounds_used == 1 and .published_round == 1 and .phase == "done" and .status == "done"' "$TMP_DIR/judge-run/config.json" >/dev/null
jq -e '.recommendation == "synthesize" and .converged == true' "$TMP_DIR/judge-run/judge-verdict.json" >/dev/null
jq -e 'length == 2 and all(.[]; .kind != null and .published == true)' "$TMP_DIR/judge-run/rounds/judge-2-round-summary.json" >/dev/null

mkdir -p "$TMP_DIR/default-cwd"
(
  cd "$TMP_DIR/default-cwd"
  PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/agent-kombat" \
    --no-interactive \
    --rounds 0 \
    --max-extra 0 \
    "draft a tiny implementation plan" >/tmp/agent-kombat-default.out
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
