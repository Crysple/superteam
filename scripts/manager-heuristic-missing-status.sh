#!/usr/bin/env bash
# manager-heuristic-missing-status.sh - Detect dead-on-arrival skill-dev spawns.
# An agent is "dead-on-arrival" if it is listed in state.json:.agents.active_agents
# and was spawned > 270s ago per .agents.spawn_history[].spawned_at, but has not yet
# produced its expected status/version-{N}-{role}.md status file.
#
# Usage: bash scripts/manager-heuristic-missing-status.sh
# Exit 0: no dead-on-arrival spawn detected (or missing state / non-skill-dev)
# Exit 1: dead-on-arrival spawn detected (linter-as-teacher WHAT/WHY/HOW)

set -euo pipefail

SUPERTEAM_DIR=".superteam"
STATE_JSON="$SUPERTEAM_DIR/state.json"
THRESHOLD=270

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Fail-soft: no state.json + nothing to check.
[ -f "$STATE_JSON" ] || exit 0

# Skill-dev scoped: require .loop.current_version in state.json.
# Engineering form sessions leave current_version unset and must stay silent.
CURRENT_VERSION=$(jq -r '.loop.current_version // empty' "$STATE_JSON" 2>/dev/null || echo "")
[ -n "$CURRENT_VERSION" ] || exit 0

# Parse active_agents as a flat list of names from state.json.
ACTIVE_CLEAN=$(jq -r '.agents.active_agents[]?' "$STATE_JSON" 2>/dev/null || true)

[ -n "$ACTIVE_CLEAN" ] || exit 0

# Map an active_agents name to a skill-dev inner-loop role, or "" if not.
find_role() {
  local agent="$1"
  case "$agent" in
    test-evaluator|test-evaluator-*|*-test-evaluator|*-test-evaluator-*) echo "test-evaluator" ;;
    generator|generator-*|*-generator|*-generator-*) echo "generator" ;;
    tester|tester-*|*-tester|*-tester-*) echo "tester" ;;
    *) echo "" ;;
  esac
}

# Extract spawned_at for a specific spawn_history entry by name.
find_spawned_at() {
  local agent="$1"
  jq -r --arg a "$agent" \
    '.agents.spawn_history[]? | select(.name == $a) | .spawned_at // empty' \
    "$STATE_JSON" 2>/dev/null | head -1
}

# Portable ISO-8601+ epoch seconds (GNU date, then BSD/macOS fallback).
to_epoch() {
  local iso="$1"
  date -d "$iso" -u +%s 2>/dev/null \
    || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || echo 0
}

NOW=$(date -u +%s)
DEAD_AGENT=""
DEAD_ROLE=""
DEAD_AGE=""
DEAD_STATUS=""

while IFS= read -r agent; do
  [ -z "$agent" ] && continue
  role=$(find_role "$agent")
  [ -z "$role" ] && continue

  spawned_at=$(find_spawned_at "$agent")
  [ -z "$spawned_at" ] && continue

  epoch=$(to_epoch "$spawned_at")
  [ "$epoch" = "0" ] && continue

  age=$((NOW - epoch))
  [ "$age" -le "$THRESHOLD" ] && continue

  status_file="$SUPERTEAM_DIR/status/version-${CURRENT_VERSION}-${role}.md"
  if [ ! -f "$status_file" ]; then
    DEAD_AGENT="$agent"
    DEAD_ROLE="$role"
    DEAD_AGE="$age"
    DEAD_STATUS="$status_file"
    break
  fi
done <<EOF
$ACTIVE_CLEAN
EOF

if [ -n "$DEAD_AGENT" ]; then
  echo "DEAD-ON-ARRIVAL SPAWN: $DEAD_AGENT (role=$DEAD_ROLE) spawned ${DEAD_AGE}s ago but $DEAD_STATUS is missing."
  echo ""
  echo "WHAT: Agent '$DEAD_AGENT' is listed in state.json:.agents.active_agents but"
  echo "  has not produced its expected per-version status file at"
  echo "  '$DEAD_STATUS'. Its .agents.spawn_history[].spawned_at timestamp is"
  echo "  ${DEAD_AGE}s old - older than one Manager cycle (${THRESHOLD}s)."
  echo ""
  echo "WHY: A healthy inner-loop agent writes its status file within one"
  echo "  Manager cycle (${THRESHOLD}s) of spawn. A silent spawn that"
  echo "  exceeds this window indicates a dead-on-arrival agent - a"
  echo "  name registered in active_agents whose process never started"
  echo "  (or crashed immediately) and left no trace. The hung detector"
  echo "  cannot catch this because no work file ever existed."
  echo ""
  echo "HOW TO FIX:"
  echo "  1. Ask TL whether the pane for '$DEAD_AGENT' is still alive."
  echo "  2. If dead, request TL to remove '$DEAD_AGENT' from active_agents"
  echo "     and respawn the ${DEAD_ROLE} for version ${CURRENT_VERSION}."
  echo "  3. If alive, send a targeted nudge - the agent may be blocked on"
  echo "     a missing prompt or input file before its first write."
  exit 1
fi

exit 0
