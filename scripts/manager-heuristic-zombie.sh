#!/bin/bash
# manager-heuristic-zombie.sh - Detect zombie agents (form-aware).
# A zombie is an inner-loop agent listed in state.json:.agents.active_agents whose
# work unit has already completed.
# Engineering form: verdicts/increment-{N}.md: verdict == APPROVED.
# Skill-dev form: status/version-{N}-{role}.md:phase has reached a
# role-specific terminal value (FR-2.3 B2 safety net).
#
# Usage: bash scripts/manager-heuristic-zombie.sh
# Exit 0: no zombies detected (or state files missing - fail-soft)
# Exit 1: zombies detected (prints agent names)

set -euo pipefail

SUPERTEAM_DIR=".superteam"
STATE_JSON="$SUPERTEAM_DIR/state.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [ ! -f "$STATE_JSON" ]; then
  echo "No state.json - cannot check for zombies"
  exit 0
fi

ACTIVE_AGENTS=$(jq -r '.agents.active_agents | join(" ")' "$STATE_JSON" 2>/dev/null || echo "")
CURRENT_INCREMENT=$(jq -r '.loop.current_increment // empty' "$STATE_JSON" 2>/dev/null || echo "")
if [ "$CURRENT_INCREMENT" = "0" ]; then
  CURRENT_INCREMENT=""
fi
COMPLETED_INCREMENT=$(jq -r '.loop.completed_increment // empty' "$STATE_JSON" 2>/dev/null || echo "")
CURRENT_VERSION=$(jq -r '.loop.current_version // empty' "$STATE_JSON" 2>/dev/null || echo "")
TASK_FORM=$(jq -r '.session.task_form // ""' "$STATE_JSON" 2>/dev/null || echo "")

# Detect form: task_form is authoritative; fall back to marker inference
# (no current_increment + has current_version = skill-dev).
IS_SKILLDEV=false
if [ "$TASK_FORM" = "skill-dev" ]; then
  IS_SKILLDEV=true
elif [ -z "$TASK_FORM" ] && [ -z "$CURRENT_INCREMENT" ] && [ -n "$CURRENT_VERSION" ]; then
  IS_SKILLDEV=true
fi

ZOMBIES=""

if [ "$IS_SKILLDEV" = true ]; then
  # Skill-dev branch: inner-loop agent still in active_agents while its
  # per-role status file shows a terminal phase.
  [ -n "$CURRENT_VERSION" ] || { echo "No zombie agents detected"; exit 0; }

  # Parse active_agents into flat names from state.json.
  ACTIVE_CLEAN=$(jq -r '.agents.active_agents[]?' "$STATE_JSON" 2>/dev/null || true)

  # Map an active_agents name to an inner-loop role. test-evaluator first
  # to avoid the tester* pattern swallowing test-evaluator-* names.
  find_role() {
    local agent="$1"
    case "$agent" in
      test-evaluator|test-evaluator-*|*-test-evaluator|*-test-evaluator-*) echo "test-evaluator" ;;
      generator|generator-*|*-generator|*-generator-*) echo "generator" ;;
      tester|tester-*|*-tester|*-tester-*) echo "tester" ;;
      *) echo "" ;;
    esac
  }

  # Role-specific terminal phase enum (FORM.md §Phase A/B; Soft Gate 4.S2).
  is_terminal_phase() {
    local role="$1" phase="$2"
    case "$role" in
      generator) [ "$phase" = "ready-for-testing" ] ;;
      tester) [ "$phase" = "test-evaluating" ] ;;
      test-evaluator) [ "$phase" = "complete" ] || [ "$phase" = "verdict-ready" ] ;;
      *) return 1 ;;
    esac
  }

  while IFS= read -r agent; do
    [ -z "$agent" ] && continue
    role=$(find_role "$agent")
    [ -z "$role" ] && continue
    status_file="$SUPERTEAM_DIR/status/version-${CURRENT_VERSION}-${role}.md"
    [ -f "$status_file" ] || continue
    phase=$(parse_yaml_field "$status_file" "phase")
    [ -n "$phase" ] || continue
    if is_terminal_phase "$role" "$phase"; then
      ZOMBIES="${ZOMBIES} ${agent}"
    fi
  done <<EOF
$ACTIVE_CLEAN
EOF
else
  # Engineering branch: inner-loop role still in active_agents while the
  # current increment already has an APPROVED verdict. Behavior preserved
  # byte-for-byte from the original script.
  if [ -z "$CURRENT_INCREMENT" ]; then
    exit 0
  fi

  for role in generator evaluator tester test-evaluator; do
    if echo "$ACTIVE_AGENTS" | tr ' ' '\n' | grep -qx "$role"; then
      if [ -f "$SUPERTEAM_DIR/verdicts/increment-${CURRENT_INCREMENT}.md" ]; then
        verdict=$(parse_yaml_field "$SUPERTEAM_DIR/verdicts/increment-${CURRENT_INCREMENT}.md" "verdict")
        if [ "$verdict" = "APPROVED" ]; then
          ZOMBIES="${ZOMBIES} $role"
        fi
      fi
    fi
  done
fi

if [ -n "$ZOMBIES" ]; then
  echo "ZOMBIE AGENTS DETECTED: ${ZOMBIES}"
  echo "These agents are still in .agents.active_agents (state.json) but their work unit has completed."
  echo "Action: TL should send shutdown messages and remove from .agents.active_agents."
  exit 1
fi

echo "No zombie agents detected"
exit 0
