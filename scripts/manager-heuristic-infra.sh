#!/bin/bash
# manager-heuristic-infra.sh - Validate infrastructure failure classification
# Checks that document-infra-failure.sh was actually run before accepting
# an infrastructure failure classification for an increment.
#
# Usage: bash scripts/manager-heuristic-infra.sh <increment-number>
# Exit 0: infra classification is backed by documentation
# Exit 1: premature classification (no documentation found)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/manager-heuristic-infra.sh <increment-number>"
  exit 2
fi

INCREMENT="$1"
SUPERTEAM_DIR=".superteam"
INFRA_DOC="$SUPERTEAM_DIR/attempts/infra-failure-${INCREMENT}.md"
ATTEMPTS="$SUPERTEAM_DIR/attempts/increment-${INCREMENT}.md"

# Check 1: Does a dedicated infra failure document exist?
if [ -f "$INFRA_DOC" ]; then
  echo "PASS: Infrastructure failure documented at $INFRA_DOC"
  exit 0
fi

# Check 2: Does the attempts file reference document-infra-failure.sh?
if [ -f "$ATTEMPTS" ]; then
  if grep -q "document-infra-failure\|infrastructure.*documented\|infra.*classification.*verified" "$ATTEMPTS" 2>/dev/null; then
    echo "PASS: Infrastructure failure referenced in attempts file"
    exit 0
  fi
fi

echo "FAIL: Premature infrastructure classification for increment $INCREMENT"
echo ""
echo "No evidence that document-infra-failure.sh was run"
echo "Before classifying a failure as infrastructure"
echo "  1. Run: bash scripts/document-infra-failure.sh $INCREMENT"
echo "  2. Verify the output document exists"
echo "  3. Then reclassify"
exit 1
