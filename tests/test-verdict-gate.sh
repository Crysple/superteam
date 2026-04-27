#!/bin/bash
# test-verdict-gate.sh - Tests for verdict-gate.sh case statement
# Regression tests for Increment 1 bug fix: version-*.md case handling
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected_exit="$2" actual_exit="$3"
  if [ "$expected_exit" -eq "$actual_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-verdict-gate ==="

# Setup: create minimal superteam structure
SUPERTEAM="$TMPDIR/.superteam"
mkdir -p "$SUPERTEAM/gate-results" "$SUPERTEAM/verdicts"

# Helper: run verdict-gate.sh with given file_path in stdin, return exit code
run_gate() {
  local file_path="$1"
  local exit_code=0
  echo "{\"file_path\": \"$file_path\"}" | \
    (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-gate.sh" >/dev/null 2>&1) || exit_code=$?
  printf '%d' "$exit_code"
}

# Test 1: Non-verdict write is allowed (exit 0)
assert_exit "non-verdict write allowed" 0 "$(run_gate "$SUPERTEAM/contracts/increment-1.md")"

# Test 2: Plan evaluation is allowed (exit 0)
assert_exit "plan-evaluation.md allowed" 0 "$(run_gate "$SUPERTEAM/verdicts/plan-evaluation.md")"

# Test 3: Draft verdict is allowed (exit 0)
assert_exit "draft verdict allowed" 0 "$(run_gate "$SUPERTEAM/verdicts/draft-analysis.md")"

# Test 4: increment-*.md verdict blocked without gate results
assert_exit "increment verdict blocked without results" 1 "$(run_gate "$SUPERTEAM/verdicts/increment-1.md")"

# Test 5: increment-*.md verdict allowed with valid gate results
echo '{"gates": [{"status": "pass"}]}' > "$SUPERTEAM/gate-results/increment-1.json"
assert_exit "increment verdict allowed with results" 0 "$(run_gate "$SUPERTEAM/verdicts/increment-1.md")"

# Test 6: version-*.md verdict blocked without gate results
assert_exit "version verdict blocked without results" 1 "$(run_gate "$SUPERTEAM/verdicts/version-1.md")"

# Test 7: version-*.md verdict allowed with version-N gate results
# run-gates.sh "version-1" writes to gate-results/version-1.json - verdict-gate must match
echo '{"gates":[{"status": "pass"}]}' > "$SUPERTEAM/gate-results/version-1.json"
assert_exit "version verdict allowed with results" 0 "$(run_gate "$SUPERTEAM/verdicts/version-1.md")"

# Test 8: Integration - run-gates.sh produces file that verdict-gate.sh expects
rm -f "$SUPERTEAM/gate-results/version-2.json"
mkdir -p "$SUPERTEAM/scripts/version-2"
cat > "$SUPERTEAM/scripts/version-2/gate-check-skill.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE
(cd "$TMPDIR" && bash "$PLUGIN_ROOT/scripts/run-gates.sh" version-2 >/dev/null 2>&1) || true
assert_exit "version verdict allowed after run-gates.sh" 0 "$(run_gate "$SUPERTEAM/verdicts/version-2.md")"

# Test 9: final-integration.md verdict blocked without gate results
assert_exit "final verdict blocked without results" 1 "$(run_gate "$SUPERTEAM/verdicts/final-integration.md")"

# Test 10: final-integration.md verdict allowed with gate results
echo '{"gates": [{"status": "pass"}]}' > "$SUPERTEAM/gate-results/final-integration.json"
assert_exit "final verdict allowed with results" 0 "$(run_gate "$SUPERTEAM/verdicts/final-integration.md")"

# Test 11: Unknown verdict filename is allowed through
assert_exit "unknown verdict filename allowed" 0 "$(run_gate "$SUPERTEAM/verdicts/custom-review.md")"

# Test 12: Empty gate-results file is blocked
echo -n > "$SUPERTEAM/gate-results/increment-3.json"
assert_exit "empty gate results blocked" 1 "$(run_gate "$SUPERTEAM/verdicts/increment-3.md")"

# Test 13: Malformed gate-results (missing "gates" key) is blocked
echo '{"results": []}' > "$SUPERTEAM/gate-results/increment-4.json"
assert_exit "malformed gate results blocked" 1 "$(run_gate "$SUPERTEAM/verdicts/increment-4.md")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
