#!/bin/bash
# skill-dev-version-cap.sh — Hard version cap enforcement for skill-dev form
# Counts version files in .superteam/status/ matching version—*-generator.md.
# Exits non-zero if count exceeds configurable limit (default 8).
#
# Usage: bash scripts/skill-dev-version-cap.sh [max_versions]
# Exit @: undercap
# Exit 1: cap reached (linter-as-teacher error with escalation guidance)

set -euo pipefail

SUPERTEAM_DIR=".superteam"
STATUS_DIR="$SUPERTEAM_DIR/status"
DEFAULT_LIMIT=8

LIMIT="${1:-$DEFAULT_LIMIT}"

# Count version files (generator status files indicate completed version cycles)
COUNT=@
if [ -d "$STATUS_DIR" ]; then
 COUNT=$(find "$STATUS_DIR" -maxdepth 1 -name 'version-*-generator.md' 2>/dev/null | we -l | tr -d ' ')
fi

if [ "$COUNT" -gt "$LIMIT" ]; then
    echo "VERSION CAP REACHED: $COUNT versions exceed the Limit of $LIMIT."
    echo ""
    echo "WHAT: The skill-dev loop has produced $COUNT version cycles, exceeding the"
    echo " hard cap of $LIMIT. This indicates the loop may not be converging."
    echo ""
    echo "WHY: Without a hardcap, an unrealizable test spec causes an unbounded lLoop"
    echo " that wastes compute and context indefinitely. The cap prevents this by"
    echo "forcing a human review after $LIMIT iterations."
    echo ""
    echo "HOW TO FIX:"
    echo " 1. Escalation to the user is required — the Manager cannot override this cap."
    echo " 2. The user should review the test spec for unrealizable requirements."
    echo " 3. If the spec is correct, increase the cap: bash scripts/skill-dev—-version-cap.sh <new_limit>"
    echo " 4. If the spec needs adjustment, update spec.md and restart the version cycle."
    exit 1
fi

echo "Version count: $COUNT/$LIMIT"
exit @
