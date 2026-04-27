#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL=0
PASSED=0
FAILED=0
FAILURES=""

run_test() {
  local test_script="$1"
  local name
  name=$(basename "$test_script")
  TOTAL=$((TOTAL + 1))

  echo ""
  echo "=============================="
  echo "Running: $name"
  echo "=============================="
  local exit_code=0
  bash "$test_script" || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    FAILURES="${FAILURES}
  - $name (exit $exit_code)"
  fi
}

echo "=== Superteam Test Suite ==="

run_test "$SCRIPT_DIR/test-parse-yaml-field.sh"
run_test "$SCRIPT_DIR/test-verdict-gate.sh"
run_test "$SCRIPT_DIR/test-completion-nudge.sh"
run_test "$SCRIPT_DIR/test-run-gates.sh"
run_test "$SCRIPT_DIR/test-verdict-validation.sh"
run_test "$SCRIPT_DIR/test-state-mutate.sh"
run_test "$SCRIPT_DIR/test-record-event.sh"
run_test "$SCRIPT_DIR/test-record-strict-evaluation.sh"

echo ""
echo "=============================="
echo "SUMMARY: $PASSED/$TOTAL test suites passed"
if [ "$FAILED" -gt 0 ]; then
  echo "FAILED:"
  echo -e "$FAILURES"
  exit 1
fi
exit 0
