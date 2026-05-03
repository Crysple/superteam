#!/bin/bash
# test-plan-eval-counter.sh - Tests for plan-eval-counter.sh
# Covers: no file, under threshold, at threshold, over threshold.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/plan-eval-counter.sh"

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
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-plan-eval-counter ==="

# --- (1) no plan evaluation file exits 0 ---
echo ""
echo "--- (1) no plan-evaluation.md ---"
RC=0
output=$(cd "$TMPDIR" && bash "$SCRIPT" 2>&1) || RC=$?
assert_exit "no file exits 0" 0 "$RC"
echo "$output" | grep -q "0 REVISE" && echo "  PASS: reports 0 REVISE cycles" && PASS=$((PASS + 1)) || { echo "  FAIL: missing 0 REVISE message"; FAIL=$((FAIL + 1)); }

# --- (2) under threshold exits 0 ---
echo ""
echo "--- (2) under threshold (1 < 3) ---"
WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam/verdicts"
cat > "$WORK2/.superteam/verdicts/plan-evaluation.md" <<'EOF'
---
verdict: REVISE
cycle: 1
---

## Cycle 1 Feedback

Minor adjustments needed.
EOF
RC=0
output=$(cd "$WORK2" && bash "$SCRIPT" 2>&1) || RC=$?
assert_exit "under threshold exits 0" 0 "$RC"
echo "$output" | grep -q "REVISE count: 1" && echo "  PASS: reports 1 REVISE cycle" && PASS=$((PASS + 1)) || { echo "  FAIL: missing REVISE count"; FAIL=$((FAIL + 1)); }

# --- (3) at threshold exits 1 ---
echo ""
echo "--- (3) at threshold (3) ---"
WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/verdicts"
cat > "$WORK3/.superteam/verdicts/plan-evaluation.md" <<'EOF'
---
verdict: REVISE
cycle: 1
---

Cycle 1
---
verdict: REVISE
cycle: 2
---

Cycle 2
---
verdict: REVISE
cycle: 3
---

Cycle 3
EOF
RC=0
output=$(cd "$WORK3" && bash "$SCRIPT" 2>&1) || RC=$?
assert_exit "at threshold exits 1" 1 "$RC"
echo "$output" | grep -q "THRESHOLD REACHED" && echo "  PASS: THRESHOLD REACHED message" && PASS=$((PASS + 1)) || { echo "  FAIL: THRESHOLD REACHED missing"; FAIL=$((FAIL + 1)); }

# --- (4) over threshold exits 1 ---
echo ""
echo "--- (4) over threshold (5) ---"
WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/verdicts"
for i in 1 2 3 4 5; do
  echo "---
verdict: REVISE
cycle: $i
---" >> "$WORK4/.superteam/verdicts/plan-evaluation.md"
done
RC=0
output=$(cd "$WORK4" && bash "$SCRIPT" 2>&1) || RC=$?
assert_exit "over threshold exits 1" 1 "$RC"
echo "$output" | grep -q "REVISE count: 5" && echo "  PASS: reports 5 REVISE cycles" && PASS=$((PASS + 1)) || { echo "  FAIL: missing REVISE count"; FAIL=$((FAIL + 1)); }

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
