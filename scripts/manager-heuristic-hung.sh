#!/bin/bash
# manager-heuristic-hung.sh - Detect hung agents via mtime-based progress check
# An agent is "hung" if it is alive but making no progress: its work file
# has not been updated in > 540s (2x Manager cycle of 270s).
#
# Usage: bash scripts/manager-heuristic-hung.sh
# Exit 0: no hung agents detected
# Exit 1: hung agent detected (prints details with linter-as-teacher guidance)

set -euo pipefail

SUPERTEAM_DIR=".superteam"
STATE_JSON="$SUPERTEAM_DIR/state.json"
THRESHOLD=540

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [ ! -f "$STATE_JSON" ]; then
  echo "No state.json - cannot check for hung agents"
  exit 0
fi

# Treat 0 as "no current increment" (fresh init value from state-mutate.sh).
CURRENT_INCREMENT=$(jq -r '.loop.current_increment // empty' "$STATE_JSON" 2>/dev/null || echo "")
if [ "$CURRENT_INCREMENT" = "0" ]; then
  CURRENT_INCREMENT=""
fi
CURRENT_VERSION=$(jq -r '.loop.current_version // empty' "$STATE_JSON" 2>/dev/null || echo "")

if [ -z "$CURRENT_INCREMENT" ] && [ -z "$CURRENT_VERSION" ]; then
  echo "No current increment or version - nothing to check"
  exit 0
fi

NOW=$(date +%s)
HUNG=""

# Check engineering form work files
if [ -n "$CURRENT_INCREMENT" ]; then
  WORK_FILE="$SUPERTEAM_DIR/attempts/increment-${CURRENT_INCREMENT}.md"
  if [ -f "$WORK_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$WORK_FILE" 2>/dev/null || stat -f %m "$WORK_FILE" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_MTIME))
    if [ "$AGE" -gt "$THRESHOLD" ]; then
      HUNG="$WORK_FILE"
      HUNG_AGE="$AGE"
    fi
  fi
fi

# Check skill-dev form status files if engineering file not found
if [ -z "$HUNG" ]; then
  for status_file in "$SUPERTEAM_DIR"/status/version-*.md; do
    [ -f "$status_file" ] || continue
    FILE_MTIME=$(stat -c %Y "$status_file" 2>/dev/null || stat -f %m "$status_file" 2>/dev/null || echo 0)
    AGE=$((NOW - FILE_MTIME))
    if [ "$AGE" -gt "$THRESHOLD" ]; then
      HUNG="$status_file"
      HUNG_AGE="$AGE"
      break
    fi
  done
fi

if [ -n "$HUNG" ]; then
  echo "POTENTIALLY HUNG: Agent working on $HUNG has not updated in ${HUNG_AGE}s (threshold: ${THRESHOLD}s)."
  echo ""
  echo "WHAT: The work file '$HUNG' has an mtime older than ${THRESHOLD}s,"
  echo "  indicating the assigned agent may be stuck in an infinite loop,"
  echo "  waiting for a message that will never arrive, or otherwise hung."
  echo ""
  echo "WHY: A healthy agent updates its work file at least once per Manager"
  echo "  cycle (270s). Two full cycles (${THRESHOLD}s) without an update"
  echo "  strongly suggests no progress is being made."
  echo ""
  echo "HOW TO FIX:"
  echo "  1. Check if the agent is still responding (send a ping via TL)."
  echo "  2. If unresponsive, request TL to kill and respawn the agent."
  echo "  3. If responsive but looping, send a nudge to try a different approach."
  exit 1
fi

echo "No hung agents detected (all work files updated within ${THRESHOLD}s)"
exit 0
