#!/bin/bash
# test-completion-nudge.sh - Tests for completion-nudge.sh
# Regression test for Increment 1 bug fix: glob pattern matching
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

assert_contains() {
  local desc="$1" expected="$2" output="$3"
  if echo "$output" | grep -q "$expected" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (output did not contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" unexpected="$2" output="$3"
  if echo "$output" | grep -q "$unexpected" 2>/dev/null; then
    echo "  FAIL: $desc (output contained '$unexpected')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_exit_0() {
  local desc="$1" exit_code="$2"
  if [ "$exit_code" -eq 0 ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (exit $exit_code, expected 0)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-completion-nudge ==="

# Test 1: No superteam state - exits 0 silently
EMPTY_DIR=$(mktemp -d)
EXIT_CODE=0
OUTPUT=$( (cd "$EMPTY_DIR" && bash "$PLUGIN_ROOT/hooks/completion-nudge.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "no state.json exits 0" "$EXIT_CODE"
rm -rf "$EMPTY_DIR"

# Test 2: Superteam state exists, increment active - shows contract nudge
SUPERTEAM="$TMPDIR/.superteam"
mkdir -p "$SUPERTEAM/contracts" "$SUPERTEAM/verdicts"

jq -n '{revision: 0, schema_version: 1, loop: {current_increment:1, total_increments: 3}}' \
  > "$SUPERTEAM/state.json"

cat > "$SUPERTEAM/contracts/increment-1.md" <<'EOF'
---
increment: 1
name: "Test Increment"
status: frozen
---
# Test contract content
Hard gate test
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/completion-nudge.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "active increment exits 0 (nudge, not block)" "$EXIT_CODE"
assert_contains "shows completion nudge header" "COMPLETION NUDGE" "$OUTPUT"
assert_contains "shows contract content" "Test contract content" "$OUTPUT"

# Test 3: Verdict exists - no warning about missing evaluation
mkdir -p "$SUPERTEAM/verdicts"
cat > "$SUPERTEAM/verdicts/increment-1.md" <<'EOF'
---
verdict: APPROVED
---
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/completion-nudge.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "with verdict exits 0" "$EXIT_CODE"
assert_not_contains "no missing verdict warning" "No evaluation verdict found" "$OUTPUT"

# Test 4: No verdict - shows warning (regression: glob must match exact filename)
rm -f "$SUPERTEAM/verdicts/increment-1.md"
EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/completion-nudge.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "missing verdict still exits 0" "$EXIT_CODE"
assert_contains "warns about missing verdict" "No evaluation verdict found" "$OUTPUT"

# Test 5: Empty increment - no contract shown
jq -n '{revision: 0, schema_version: 1, loop: {current_increment: null}}' \
  > "$SUPERTEAM/state.json"

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/completion-nudge.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "empty increment exits 0" "$EXIT_CODE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
