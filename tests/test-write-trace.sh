#!/bin/bash
# test-write-trace.sh - Tests for scripts/write-trace.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRITE_TRACE="$PLUGIN_ROOT/scripts/write-trace.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-write-trace ==="

# ---------------------------------------------------------------------------
# (1) No args exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no args exits 2 ---"

RC=0
(cd "$TMPDIR" && bash "$WRITE_TRACE" 2>/dev/null) || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (2) Happy path: all input files present → trace with correct fields
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) happy path ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam/contracts" "$WORK2/.superteam/verdicts" \
         "$WORK2/.superteam/gate-results" "$WORK2/.superteam/attempts"

cat > "$WORK2/.superteam/contracts/increment-1.md" <<'EOF'
---
name: "Fix Auth Bug"
status: frozen
spec_items: [HG-1, HG-2]
---
Contract body.
EOF

cat > "$WORK2/.superteam/verdicts/increment-1.md" <<'EOF'
---
verdict: APPROVED
---
Verdict body.
EOF

cat > "$WORK2/.superteam/gate-results/increment-1.json" <<'EOF'
{
  "increment": "1",
  "all_passed": true,
  "total": 3,
  "passed": 3,
  "failed": 0,
  "gates": []
}
EOF

cat > "$WORK2/.superteam/attempts/increment-1.md" <<'EOF'
## Attempt 1
First attempt.

## Attempt 2
Second attempt.
EOF

RC=0
(cd "$WORK2" && bash "$WRITE_TRACE" 1 2>/dev/null) || RC=$?
assert_exit "happy path exits 0" 0 "$RC"

TRACE2="$WORK2/.superteam/traces/increment-1.yaml"
assert_eq "trace file created" "true" "$([ -f "$TRACE2" ] && echo true || echo false)"

CONTENT2=$(cat "$TRACE2")
assert_contains "increment field" "increment: 1" "$CONTENT2"
assert_contains "name field" "Fix Auth Bug" "$CONTENT2"
assert_contains "contract status" "frozen" "$CONTENT2"
assert_contains "verdict field" "APPROVED" "$CONTENT2"
assert_contains "gates total" "total: 3" "$CONTENT2"
assert_contains "gates passed" "passed: 3" "$CONTENT2"
assert_contains "gates failed" "failed: 0" "$CONTENT2"
assert_contains "all_passed true" "all_passed: true" "$CONTENT2"
assert_contains "attempt_count 2" "attempt_count: 2" "$CONTENT2"
assert_contains "timestamp present" "timestamp:" "$CONTENT2"

# ---------------------------------------------------------------------------
# (3) Missing all input files → trace still created (empty/zero fields)
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) missing input files handled gracefully ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"

RC=0
(cd "$WORK3" && bash "$WRITE_TRACE" 99 2>/dev/null) || RC=$?
assert_exit "missing files exits 0" 0 "$RC"

TRACE3="$WORK3/.superteam/traces/increment-99.yaml"
assert_eq "trace created despite missing files" "true" "$([ -f "$TRACE3" ] && echo true || echo false)"

CONTENT3=$(cat "$TRACE3")
assert_contains "increment field present" "increment: 99" "$CONTENT3"
assert_contains "zero attempt count" "attempt_count: 0" "$CONTENT3"
assert_contains "zero gates total" "total: 0" "$CONTENT3"

# ---------------------------------------------------------------------------
# (4) Attempt count reflects ## Attempt headings accurately
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) attempt count from headings ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/attempts"

cat > "$WORK4/.superteam/attempts/increment-2.md" <<'EOF'
## Attempt 1
Work.
## Attempt 2
Work.
## Attempt 3
Work.
EOF

RC=0
(cd "$WORK4" && bash "$WRITE_TRACE" 2 2>/dev/null) || RC=$?
assert_exit "3 attempts exits 0" 0 "$RC"

TRACE4="$WORK4/.superteam/traces/increment-2.yaml"
assert_contains "attempt_count is 3" "attempt_count: 3" "$(cat "$TRACE4")"

# ---------------------------------------------------------------------------
# (5) Gate results with failures reflected correctly
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) gate failures in trace ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/gate-results"

cat > "$WORK5/.superteam/gate-results/increment-3.json" <<'EOF'
{
  "increment": "3",
  "all_passed": false,
  "total": 4,
  "passed": 2,
  "failed": 2,
  "gates": []
}
EOF

RC=0
(cd "$WORK5" && bash "$WRITE_TRACE" 3 2>/dev/null) || RC=$?
assert_exit "failing gates exits 0" 0 "$RC"

TRACE5="$WORK5/.superteam/traces/increment-3.yaml"
CONTENT5=$(cat "$TRACE5")
assert_contains "total 4" "total: 4" "$CONTENT5"
assert_contains "failed 2" "failed: 2" "$CONTENT5"
assert_contains "all_passed false" "all_passed: false" "$CONTENT5"

# ---------------------------------------------------------------------------
# (6) traces/ directory is created if absent
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) traces dir auto-created ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam"

RC=0
(cd "$WORK6" && bash "$WRITE_TRACE" 7 2>/dev/null) || RC=$?
assert_exit "auto-create traces dir exits 0" 0 "$RC"
assert_eq "traces dir exists" "true" "$([ -d "$WORK6/.superteam/traces" ] && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
