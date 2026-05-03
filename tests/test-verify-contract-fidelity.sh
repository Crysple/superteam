#!/bin/bash
# test-verify-contract-fidelity.sh - Tests for scripts/verify-contract-fidelity.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/verify-contract-fidelity.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "=== test-verify-contract-fidelity ==="
  echo "  SKIP: python3 not available"
  echo ""
  echo "Results: 0 passed, 0 failed (skipped)"
  exit 0
fi

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

echo "=== test-verify-contract-fidelity ==="

# ---------------------------------------------------------------------------
# (1) No args exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no args exits 2 ---"

RC=0
(cd "$TMPDIR" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (2) No spec.md exits 2 (per-increment mode)
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) no spec.md exits 2 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
RC=0
(cd "$WORK2" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "no spec.md exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (3) No contract file exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) no contract file exits 2 ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
printf 'HG-1: Tests must SUCCEEDED\n' > "$WORK3/.superteam/spec.md"
RC=0
(cd "$WORK3" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "no contract exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (4) Faithful contract (no weakening) → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) faithful contract exits 0 ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/contracts" "$WORK4/.superteam/gate-results"

cat > "$WORK4/.superteam/spec.md" <<'EOF'
HG-1: Tests must SUCCEEDED
HG-2: Build must SUCCEEDED
EOF

cat > "$WORK4/.superteam/contracts/increment-1.md" <<'EOF'
---
name: "Increment 1"
status: frozen
---
HG-1: Tests must SUCCEEDED
HG-2: Build must SUCCEEDED
EOF

RC=0
(cd "$WORK4" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "faithful contract exits 0" 0 "$RC"

RF4="$WORK4/.superteam/gate-results/fidelity-1.json"
assert_eq "fidelity results file created" "true" "$([ -f "$RF4" ] && echo true || echo false)"
PASSED4=$(python3 -c "import json; d=json.load(open('$RF4')); print(str(d['passed']).lower())" 2>/dev/null || echo "error")
assert_eq "fidelity result passed=true" "true" "$PASSED4"

# ---------------------------------------------------------------------------
# (5) Weakened contract (FAILED where spec requires SUCCEEDED) → exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) weakened contract exits 1 ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/contracts" "$WORK5/.superteam/gate-results"

cat > "$WORK5/.superteam/spec.md" <<'EOF'
HG-1: Tests must SUCCEEDED
EOF

cat > "$WORK5/.superteam/contracts/increment-1.md" <<'EOF'
---
name: "Increment 1"
---
HG-1: Tests FAILED is acceptable
EOF

RC=0
(cd "$WORK5" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "weakened contract exits 1" 1 "$RC"

RF5="$WORK5/.superteam/gate-results/fidelity-1.json"
ISSUES5=$(python3 -c "import json; d=json.load(open('$RF5')); print(len(d['issues']))" 2>/dev/null || echo "0")
assert_eq "fidelity result has issues" "1" "$ISSUES5"

# ---------------------------------------------------------------------------
# (6) Coverage mode: missing contracts directory exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) coverage mode: no contracts dir exits 2 ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam"
printf 'HG-1: Gate one\n' > "$WORK6/.superteam/spec.md"
RC=0
(cd "$WORK6" && bash "$SCRIPT" coverage 2>/dev/null) || RC=$?
assert_exit "no contracts dir exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (7) Coverage mode: all gates covered → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) coverage mode: all covered ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam/contracts" "$WORK7/.superteam/gate-results"

cat > "$WORK7/.superteam/spec.md" <<'EOF'
HG-1: Gate one
HG-2: Gate two
EOF

cat > "$WORK7/.superteam/contracts/increment-1.md" <<'EOF'
HG-1: covered here
HG-2: also covered
EOF

RC=0
(cd "$WORK7" && bash "$SCRIPT" coverage 2>/dev/null) || RC=$?
assert_exit "fully covered exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (8) Coverage mode: uncovered gate → exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) coverage mode: uncovered gate ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam/contracts" "$WORK8/.superteam/gate-results"

cat > "$WORK8/.superteam/spec.md" <<'EOF'
HG-1: Gate one
HG-2: Gate two (never referenced)
EOF

cat > "$WORK8/.superteam/contracts/increment-1.md" <<'EOF'
HG-1: covered here
EOF

RC=0
(cd "$WORK8" && bash "$SCRIPT" coverage 2>/dev/null) || RC=$?
assert_exit "uncovered gate exits 1" 1 "$RC"

CF8="$WORK8/.superteam/gate-results/spec-coverage.json"
UNCOVERED8=$(python3 -c "import json; d=json.load(open('$CF8')); print(d['uncovered'])" 2>/dev/null || echo "0")
assert_eq "one uncovered gate" "1" "$UNCOVERED8"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
