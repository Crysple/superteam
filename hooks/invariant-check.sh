#!/bin/bash
# invariant-check.sh - PreToolUse hook for Bash tool
# Fires before git commit commands. Verifies invariants (tests, lint, types)
# by reading validation commands from .superteam/validation-commands.txt.
# Exits non-zero to BLOCK the commit if any invariant fails.
#
# Design: "linter-as-teacher" -- error messages explain WHAT failed and HOW to fix,
# not just "invariant violated". This teaches the Generator to self-correct.

set -euo pipefail

SUPERTEAM_DIR=".superteam"
VALIDATION_COMMANDS_FILE="$SUPERTEAM_DIR/validation-commands.txt"

# ---------------------------------------------------------------------------
# Helpers (shared library)
# ---------------------------------------------------------------------------

_INV_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_INV_CHECK_DIR/../scripts/lib.sh"

# ---------------------------------------------------------------------------
# Gate: Only fire on git commit commands
# ---------------------------------------------------------------------------

# Read the tool input from stdin (Claude Code passes tool call as JSON on stdin)
TOOL_INPUT=$(cat 2>/dev/null || true)

# Check if this is a git commit command
if ! echo "$TOOL_INPUT" | grep -q "git commit" 2>/dev/null; then
  # Not a git commit - allow the command through
  exit 0
fi

# ---------------------------------------------------------------------------
# Pre-flight: Ensure validation commands file exists
# ---------------------------------------------------------------------------

if [ ! -f "$VALIDATION_COMMANDS_FILE" ]; then
  # No validation commands file - allow through (supports non-superteam workflows)
  exit 0
fi

# ---------------------------------------------------------------------------
# Read validation commands from validation-commands.txt
# ---------------------------------------------------------------------------

# validation-commands.txt contains a comma-separated list of shell commands
# e.g., "npm test, tsc --noEmit, eslint . --quiet"
VALIDATION_COMMANDS=$(cat "$VALIDATION_COMMANDS_FILE")

if [ -z "$VALIDATION_COMMANDS" ]; then
  # No validation commands configured - nothing to enforce
  exit 0
fi

# ---------------------------------------------------------------------------
# Run each invariant check
# ---------------------------------------------------------------------------

FAILURES=""
FAILURE_COUNT=0

# Split on comma and trim whitespace
IFS=',' read -ra COMMANDS <<< "$VALIDATION_COMMANDS"
for cmd in "${COMMANDS[@]}"; do
  # Trim leading/trailing whitespace
  cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -z "$cmd" ]; then
    continue
  fi

  echo "--- Running invariant check: $cmd ---"

  # Capture output and exit code
  OUTPUT=""
  EXIT_CODE=0
  OUTPUT=$(eval "$cmd" 2>&1) || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    FAILURES="${FAILURES}
=== FAILED: $cmd (exit code $EXIT_CODE) ===
${OUTPUT}
"
    echo "FAILED: $cmd (exit code $EXIT_CODE)"
  else
    echo "PASSED: $cmd"
  fi
done

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------

if [ "$FAILURE_COUNT" -gt 0 ]; then
  echo ""
  echo "=============================="
  echo "COMMIT BLOCKED: $FAILURE_COUNT invariant(s) failed"
  echo "=============================="
  echo ""
  echo "The following checks must pass before you can commit:"
  echo "$FAILURES"
  echo ""
  echo "Fix the failures above and try committing again."
  echo "If you believe an invariant check is incorrect, report a GATE-CHALLENGE"
  echo "to the Evaluator, who can escalate to the Architect for script review."
  exit 1
fi

echo "All invariant checks passed."
exit 0
