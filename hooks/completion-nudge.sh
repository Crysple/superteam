#!/bin/bash
# completion-nudge.sh - Stop hook (implicit completion nudge, OpenDev pattern)
# Fires when any teammate tries to exit. Re-presents the contract - this is
# the most effective anti-premature-exit mechanism per v2 spec.
# The nudge is informational (exit 0) - it does not block, but it surfaces
# the contract one final time so the agent can self-correct.

set -euo pipefail

SUPERTEAM_DIR=".superteam"
STATE_JSON="$SUPERTEAM_DIR/state.json"
CONTRACTS_DIR="$SUPERTEAM_DIR/contracts"

if [ ! -f "$STATE_JSON" ]; then
  # No superteam state - not running under the superteam
  exit 0
fi

# Read current increment number from .loop.current_increment in state.json.
CURRENT_INCREMENT=$(jq -r '.loop.current_increment // empty' "$STATE_JSON" 2>/dev/null || true)

if [ -z "$CURRENT_INCREMENT" ]; then
  # No active increment - allow exit
  exit 0
fi

CONTRACT_FILE="$CONTRACTS_DIR/increment-${CURRENT_INCREMENT}.md"

# ---------------------------------------------------------------------------
# Check 1: Does the contract exist?
# ---------------------------------------------------------------------------

if [ ! -f "$CONTRACT_FILE" ]; then
  # No contract for this increment - could be a non-standard phase
  exit 0
fi

# ---------------------------------------------------------------------------
# Check 2: Has evaluation been completed?
# ---------------------------------------------------------------------------

# Look for a verdict file for this increment
VERDICT_EXISTS=false
if [ -f "$SUPERTEAM_DIR/verdicts/increment-${CURRENT_INCREMENT}.md" ]; then
  VERDICT_EXISTS=true
fi

if [ "$VERDICT_EXISTS" = false ]; then
  echo ""
  echo "=============================="
  echo "WARNING: No evaluation verdict found for increment $CURRENT_INCREMENT"
  echo "=============================="
  echo ""
  echo "You must complete evaluation before exiting. The Evaluator must run all"
  echo "contract gates and issue a verdict (APPROVED, REVISE, or GATE-CHALLENGE)."
  echo ""
fi

# ---------------------------------------------------------------------------
# Nudge: Re-present the contract
# ---------------------------------------------------------------------------

CONTRACT_CONTENT=$(cat "$CONTRACT_FILE")

echo ""
echo "=============================="
echo "COMPLETION NUDGE - Increment $CURRENT_INCREMENT"
echo "=============================="
echo ""
echo "Before finishing, verify you have fully addressed the contract:"
echo ""
echo "$CONTRACT_CONTENT"
echo ""
echo "Have ALL hard gates been run and passed? Have soft gates been reviewed"
echo "with specific evidence? If not, continue working - do not exit."
echo ""

# This is a nudge, not a block - always exit 0
exit 0
