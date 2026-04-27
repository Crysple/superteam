#!/bin/bash
# plan-eval-counter.sh - Mechanical counter for Plan Evaluator REVISE cycles
# Reads verdicts/plan-evaluation.md history and counts REVISE entries.
# Exits non-zero if >= 3 (signals escalation to TL).
#
# Usage: bash scripts/plan-eval-counter.sh
# Exit 0: under threshold
# Exit 1: threshold reached (3+ REVISE cycles)

set -euo pipefail

SUPERTEAM_DIR=".superteam"
PLAN_EVAL="$SUPERTEAM_DIR/verdicts/plan-evaluation.md"
THRESHOLD=3

if [ ! -f "$PLAN_EVAL" ]; then
  echo "No plan evaluation history found - 0 REVISE cycles"
  exit 0
fi

REVISE_COUNT=$(grep -c '^verdict:.*REVISE' "$PLAN_EVAL" 2>/dev/null || echo 0)

echo "Plan Evaluator REVISE count: $REVISE_COUNT (threshold: $THRESHOLD)"

if [ "$REVISE_COUNT" -ge "$THRESHOLD" ]; then
  echo ""
  echo "THRESHOLD REACHED: $REVISE_COUNT REVISE cycles detected."
  echo "The Plan Evaluator and Architect may be stuck in a loop."
  echo "Action: Escalate to TL for user mediation."
  exit 1
fi

echo "Under threshold - no escalation needed"
exit 0
