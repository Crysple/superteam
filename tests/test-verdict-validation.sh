#!/bin/bash
# test-verdict-validation.sh - Tests for verdict-validation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

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

echo "=== test-verdict-validation ==="

# Test 1: No superteam dir - exits 0
EMPTY_DIR=$(mktemp -d)
EXIT_CODE=0
OUTPUT=$( (cd "$EMPTY_DIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "no superteam dir exits 0" "$EXIT_CODE"
rm -rf "$EMPTY_DIR"

# Test 2: No recent verdicts - exits 0 silently
SUPERTEAM="$TMPDIR/.superteam"
mkdir -p "$SUPERTEAM/verdicts"

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "no recent verdicts exits 0" "$EXIT_CODE"

# Test 3: Valid verdict APPROVED - no warning
cat > "$SUPERTEAM/verdicts/increment-1.md" <<'EOF'
---
verdict: APPROVED
---
EOF
touch "$SUPERTEAM/verdicts/increment-1.md"

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "valid APPROVED exits 0" "$EXIT_CODE"
assert_not_contains "no warning for APPROVED" "Invalid verdict" "$OUTPUT"

# Test 4: Valid verdict REVISE - no warning
cat > "$SUPERTEAM/verdicts/increment-2.md" <<'EOF'
---
verdict: REVISE
---
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "valid REVISE exits 0" "$EXIT_CODE"
assert_not_contains "no warning for REVISE" "Invalid verdict" "$OUTPUT"

# Test 5: Valid verdict GATE-CHALLENGE - no warning
cat > "$SUPERTEAM/verdicts/increment-3.md" <<'EOF'
---
verdict: GATE-CHALLENGE
---
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "valid GATE-CHALLENGE exits 0" "$EXIT_CODE"
assert_not_contains "no warning for GATE-CHALLENGE" "Invalid verdict" "$OUTPUT"

# Test 6: Invalid verdict - shows warning but exits 0 (nudge pattern)
cat > "$SUPERTEAM/verdicts/increment-4.md" <<'EOF'
---
verdict: PARTIAL-PASS
---
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$TMPDIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "invalid verdict still exits 0 (nudge)" "$EXIT_CODE"
assert_contains "warns about invalid verdict" "Invalid verdict" "$OUTPUT"

# Test 7: No verdict field - no warning (just skipped)
CLEAN_DIR=$(mktemp -d)
CLEAN_SUPERTEAM="$CLEAN_DIR/.superteam"
mkdir -p "$CLEAN_SUPERTEAM/verdicts"
cat > "$CLEAN_SUPERTEAM/verdicts/increment-5.md" <<'EOF'
---
status: complete
---
EOF

EXIT_CODE=0
OUTPUT=$( (cd "$CLEAN_DIR" && bash "$PLUGIN_ROOT/hooks/verdict-validation.sh" 2>&1) ) || EXIT_CODE=$?
assert_exit_0 "missing verdict field exits 0" "$EXIT_CODE"
assert_not_contains "no warning for missing field" "Invalid verdict" "$OUTPUT"
rm -rf "$CLEAN_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
