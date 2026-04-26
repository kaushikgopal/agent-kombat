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
