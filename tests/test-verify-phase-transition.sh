#!/bin/bash
# test-verify-phase-transition.sh - Tests for scripts/verify-phase-transition.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/verify-phase-transition.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "=== test-verify-phase-transition ==="
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

echo "=== test-verify-phase-transition ==="

# ---------------------------------------------------------------------------
# (1) No args exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no args exits 2 ---"

RC=0
(cd "$TMPDIR" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (2) Unknown transition exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) unknown transition exits 2 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
RC=0
(cd "$WORK2" && bash "$SCRIPT" foo bar 2>/dev/null) || RC=$?
assert_exit "unknown transition exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (3) architect->execute: missing plan.md → blocked (exit 1)
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) architect->execute: missing plan.md ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
RC=0
(cd "$WORK3" && bash "$SCRIPT" architect execute 2>/dev/null) || RC=$?
assert_exit "missing plan.md exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (4) architect->execute: valid plan with 1 increment → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) architect->execute: valid setup ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/contracts" \
         "$WORK4/.superteam/scripts/increment-1" \
         "$WORK4/.superteam/scripts/final"

cat > "$WORK4/.superteam/plan.md" <<'EOF'
---
total_increments: 1
---
# Plan
EOF

cat > "$WORK4/.superteam/contracts/increment-1.md" <<'EOF'
---
name: "Increment 1"
status: frozen
---
EOF

cat > "$WORK4/.superteam/scripts/increment-1/gate-compile.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE
chmod +x "$WORK4/.superteam/scripts/increment-1/gate-compile.sh"

cat > "$WORK4/.superteam/scripts/final/gate-integration.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE
chmod +x "$WORK4/.superteam/scripts/final/gate-integration.sh"

RC=0
(cd "$WORK4" && bash "$SCRIPT" architect execute 2>/dev/null) || RC=$?
assert_exit "valid architect->execute exits 0" 0 "$RC"

RF4="$WORK4/.superteam/phase-transition-results.json"
assert_eq "results file created" "true" "$([ -f "$RF4" ] && echo true || echo false)"
CONTENT4=$(python3 -c "import json; d=json.load(open('$RF4')); print(str(d['passed']).lower())" 2>/dev/null || echo "error")
assert_eq "results JSON passed=true" "true" "$CONTENT4"

# ---------------------------------------------------------------------------
# (5) architect->execute: contract not frozen → blocked (exit 1)
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) architect->execute: non-frozen contract ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/contracts" \
         "$WORK5/.superteam/scripts/increment-1" \
         "$WORK5/.superteam/scripts/final"

cat > "$WORK5/.superteam/plan.md" <<'EOF'
---
total_increments: 1
---
EOF

cat > "$WORK5/.superteam/contracts/increment-1.md" <<'EOF'
---
name: "Increment 1"
status: draft
---
EOF

cat > "$WORK5/.superteam/scripts/increment-1/gate-compile.sh" <<'GATE'
#!/bin/bash
exit 0
GATE
chmod +x "$WORK5/.superteam/scripts/increment-1/gate-compile.sh"

cat > "$WORK5/.superteam/scripts/final/gate-integration.sh" <<'GATE'
#!/bin/bash
exit 0
GATE
chmod +x "$WORK5/.superteam/scripts/final/gate-integration.sh"

RC=0
(cd "$WORK5" && bash "$SCRIPT" architect execute 2>/dev/null) || RC=$?
assert_exit "non-frozen contract exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (6) execute->integrate: all APPROVED + gate results → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) execute->integrate: all APPROVED ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam/verdicts" "$WORK6/.superteam/gate-results"

cat > "$WORK6/.superteam/plan.md" <<'EOF'
---
total_increments: 2
---
EOF

for i in 1 2; do
  cat > "$WORK6/.superteam/verdicts/increment-${i}.md" <<EOF
---
verdict: APPROVED
---
EOF
  echo '{"all_passed": true}' > "$WORK6/.superteam/gate-results/increment-${i}.json"
done

RC=0
(cd "$WORK6" && bash "$SCRIPT" execute integrate 2>/dev/null) || RC=$?
assert_exit "all APPROVED exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (7) execute->integrate: one REVISE verdict → blocked
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) execute->integrate: REVISE verdict ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam/verdicts" "$WORK7/.superteam/gate-results"

cat > "$WORK7/.superteam/plan.md" <<'EOF'
---
total_increments: 1
---
EOF

cat > "$WORK7/.superteam/verdicts/increment-1.md" <<'EOF'
---
verdict: REVISE
---
EOF
echo '{"all_passed": false}' > "$WORK7/.superteam/gate-results/increment-1.json"

RC=0
(cd "$WORK7" && bash "$SCRIPT" execute integrate 2>/dev/null) || RC=$?
assert_exit "REVISE verdict exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (8) execute->integrate: missing verdict → blocked
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) execute->integrate: missing verdict ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam"

cat > "$WORK8/.superteam/plan.md" <<'EOF'
---
total_increments: 1
---
EOF

RC=0
(cd "$WORK8" && bash "$SCRIPT" execute integrate 2>/dev/null) || RC=$?
assert_exit "missing verdict exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (9) integrate->deliver: APPROVED verdict → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (9) integrate->deliver: APPROVED ---"

WORK9="$TMPDIR/t9"
mkdir -p "$WORK9/.superteam/verdicts"

cat > "$WORK9/.superteam/verdicts/final-integration.md" <<'EOF'
---
verdict: APPROVED
---
EOF

RC=0
(cd "$WORK9" && bash "$SCRIPT" integrate deliver 2>/dev/null) || RC=$?
assert_exit "APPROVED integrate->deliver exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (10) integrate->deliver: PASS verdict → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (10) integrate->deliver: PASS ---"

WORK10="$TMPDIR/t10"
mkdir -p "$WORK10/.superteam/verdicts"

cat > "$WORK10/.superteam/verdicts/integration-verdict.md" <<'EOF'
---
verdict: PASS
---
EOF

RC=0
(cd "$WORK10" && bash "$SCRIPT" integrate deliver 2>/dev/null) || RC=$?
assert_exit "PASS integrate->deliver exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (11) integrate->deliver: REVISE verdict → blocked
# ---------------------------------------------------------------------------
echo ""
echo "--- (11) integrate->deliver: REVISE ---"

WORK11="$TMPDIR/t11"
mkdir -p "$WORK11/.superteam/verdicts"

cat > "$WORK11/.superteam/verdicts/final-integration.md" <<'EOF'
---
verdict: REVISE
---
EOF

RC=0
(cd "$WORK11" && bash "$SCRIPT" integrate deliver 2>/dev/null) || RC=$?
assert_exit "REVISE integrate->deliver exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (12) integrate->deliver: no verdict file → blocked
# ---------------------------------------------------------------------------
echo ""
echo "--- (12) integrate->deliver: no verdict file ---"

WORK12="$TMPDIR/t12"
mkdir -p "$WORK12/.superteam/verdicts"

RC=0
(cd "$WORK12" && bash "$SCRIPT" integrate deliver 2>/dev/null) || RC=$?
assert_exit "no verdict file exits 1" 1 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
