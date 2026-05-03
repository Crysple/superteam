#!/bin/bash
# startup-self-test.sh - Pipeline startup validation
# Runs at superteam initialization to verify all hooks produce meaningful results
# against the current codebase. Catches configuration errors (wrong paths,
# missing tools, broken scripts) BEFORE any work begins.
#
# Exit non-zero if any hook fails with a config error.
# This prevents silent enforcement failure - if invariant hooks are broken,
# we find out immediately rather than after N increments of unguarded commits.

set -euo pipefail

SUPERTEAM_DIR=".superteam"
VALIDATION_COMMANDS_FILE="$SUPERTEAM_DIR/validation-commands.txt"

# ---------------------------------------------------------------------------
# Early exit: if superteam directory doesn't exist, nothing to validate
# ---------------------------------------------------------------------------

if [ ! -d "$SUPERTEAM_DIR" ]; then
  echo "No $SUPERTEAM_DIR directory found - skipping self-test (superteam not initialized)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers (shared library)
# ---------------------------------------------------------------------------

_SELF_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SELF_TEST_DIR/../scripts/lib.sh"

# ---------------------------------------------------------------------------
# Self-test 0: Required external tools
# ---------------------------------------------------------------------------

echo "=== Startup Self-Test ==="
echo ""
ERRORS=""
ERROR_COUNT=0

echo "--- Checking required tools ---"

if command -v python3 >/dev/null 2>&1; then
  echo "  OK: python3 is available ($(python3 --version 2>&1))"
else
  echo "  MISSING: python3 not found in PATH"
  ERROR_COUNT=$((ERROR_COUNT + 1))
  ERRORS="${ERRORS}
  - python3 is required but not found (needed by gate scripts and verification tooling)"
fi

# ---------------------------------------------------------------------------
# Self-test 1: Superteam directory structure
# ---------------------------------------------------------------------------

echo "--- Checking superteam directory structure ---"

REQUIRED_DIRS=(
  "$SUPERTEAM_DIR"
  "$SUPERTEAM_DIR/contracts"
  "$SUPERTEAM_DIR/scripts"
  "$SUPERTEAM_DIR/attempts"
  "$SUPERTEAM_DIR/traces"
  "$SUPERTEAM_DIR/knowledge"
)

for dir in "${REQUIRED_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "  MISSING DIR: $dir"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    ERRORS="${ERRORS}
  - Missing directory: $dir"
  else
    echo "  OK: $dir"
  fi
done

# ---------------------------------------------------------------------------
# Self-test 2: Required state files
# ---------------------------------------------------------------------------

echo ""
echo "--- Checking required state files ---"

REQUIRED_FILES=(
  "$SUPERTEAM_DIR/state.json"
  "$SUPERTEAM_DIR/metrics.md"
  "$SUPERTEAM_DIR/lessons-learned.md"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "  MISSING FILE: $file"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    ERRORS="${ERRORS}
  - Missing state file: $file"
  else
    echo "  OK: $file"
  fi
done

# ---------------------------------------------------------------------------
# Self-test 3: Validation commands are resolvable
# ---------------------------------------------------------------------------

echo ""
echo "--- Checking validation commands ---"

if [ -f "$VALIDATION_COMMANDS_FILE" ]; then
  VALIDATION_COMMANDS=$(cat "$VALIDATION_COMMANDS_FILE")
  IFS=',' read -ra COMMANDS <<< "$VALIDATION_COMMANDS"
  for cmd in "${COMMANDS[@]}"; do
    cmd=$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$cmd" ]; then
      continue
    fi

    # Extract the base command (first word)
    BASE_CMD=$(echo "$cmd" | awk '{print $1}')

    if command -v "$BASE_CMD" >/dev/null 2>&1; then
      echo "  OK: '$BASE_CMD' is available"
    else
      echo "  WARNING: '$BASE_CMD' not found in PATH (from: $cmd)"
      echo "    This invariant check may fail at runtime."
      # This is a warning, not an error - the tool might be installed later
      # or available via npx/gradlew/etc.
    fi
  done
else
  echo "  validation-commands.txt not found (no recognized project config)"
fi

# ---------------------------------------------------------------------------
# Self-test 4: Hook scripts are executable
# ---------------------------------------------------------------------------

echo ""
echo "--- Checking hook scripts ---"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOK_SCRIPTS=(
  "$SCRIPT_DIR/invariant-check.sh"
  "$SCRIPT_DIR/completion-nudge.sh"
  "$SCRIPT_DIR/startup-self-test.sh"
  "$SCRIPT_DIR/verdict-gate.sh"
  "$SCRIPT_DIR/verdict-validation.sh"
)

for script in "${HOOK_SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    echo "  MISSING: $script"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    ERRORS="${ERRORS}
  - Missing hook script: $script"
  elif [ ! -x "$script" ]; then
    echo "  NOT EXECUTABLE: $script"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    ERRORS="${ERRORS}
  - Hook script not executable: $script (run: chmod +x $script)"
  else
    echo "  OK: $script"
  fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

echo ""
if [ "$ERROR_COUNT" -gt 0 ]; then
  echo "=============================="
  echo "STARTUP SELF-TEST FAILED: $ERROR_COUNT error(s)"
  echo "=============================="
  echo ""
  echo "Fix the following before proceeding:"
  echo -e "$ERRORS"
  echo ""
  echo "The superteam cannot guarantee invariant enforcement with these errors."
  echo "Fix them and restart, or the pipeline may silently skip quality checks."
  exit 1
fi

echo "=============================="
echo "STARTUP SELF-TEST PASSED"
echo "=============================="
echo "All hooks and state files verified. Pipeline is ready."
exit 0
