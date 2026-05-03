#!/bin/bash
# test-manager-heuristic-infra.sh - Tests for manager-heuristic-infra.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/manager-heuristic-infra.sh"

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

echo "=== test-manager-heuristic-infra ==="

# ---------------------------------------------------------------------------
# (1) No args: exits 2 (usage error)
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no args exits 2 ---"

RC=0
bash "$SCRIPT" 2>/dev/null || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (2) Dedicated infra doc exists: exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) dedicated infra doc exists exits 0 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam/attempts"
cat > "$WORK2/.superteam/attempts/infra-failure-1.md" <<'EOF'
---
increment: 1
failure_type: infrastructure
remediation_attempts: 3
status: concluded
---
EOF
RC=0
(cd "$WORK2" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "dedicated infra doc exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) Attempts file references infra doc: exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) attempts file references infra doc exits 0 ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/attempts"
cat > "$WORK3/.superteam/attempts/increment-1.md" <<'EOF'
Ran document-infra-failure.sh and verified infrastructure failure.
EOF
RC=0
(cd "$WORK3" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "attempts file references infra doc exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (4) No documentation: exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) no documentation exits 1 ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/attempts"
RC=0
(cd "$WORK4" && bash "$SCRIPT" 1 2>/dev/null) || RC=$?
assert_exit "no documentation exits 1" 1 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
