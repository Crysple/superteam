#!/bin/bash
# test-document-infra-failure.sh - Tests for document-infra-failure.sh
# Covers: template creation, substantive < 3, substantive >= 3, usage error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/document-infra-failure.sh"

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

echo "=== test-document-infra-failure ==="

# --- (1) no args exits 2 ---
echo ""
echo "--- (1) usage: no args ---"
RC=0
bash "$SCRIPT" 2>/dev/null || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# --- (2) template creation ---
echo ""
echo "--- (2) template created when file missing ---"
WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
RC=0
output=$(cd "$WORK2" && bash "$SCRIPT" 1 2>&1) || RC=$?
assert_exit "template created exits 1" 1 "$RC"
echo "$output" | grep -q "Template created" && echo "  PASS: template message printed" && PASS=$((PASS + 1)) || { echo "  FAIL: template message missing"; FAIL=$((FAIL + 1)); }
[ -f "$WORK2/.superteam/attempts/infra-failure-1.md" ] && echo "  PASS: infra-failure-1.md created" && PASS=$((PASS + 1)) || { echo "  FAIL: infra-failure-1.md missing"; FAIL=$((FAIL + 1)); }

# --- (3) template with < 3 substantive attempts ---
echo ""
echo "--- (3) less than 3 substantive attempts ---"
WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/attempts"
cat > "$WORK3/.superteam/attempts/infra-failure-2.md" <<'FM'
---
increment: 2
failure_type: infrastructure
remediation_attempts: 0
status: investigating
---

## Failure Description

The database connection pool exhausted connections.

## Knowledge Base Search

Searched for "connection pool" in wiki - found tuning guide.

## Remediation Attempts

### Attempt 1
- **What was tried:** [description]
- **Actual outcome:** no effect
FM
RC=0
output=$(cd "$WORK3" && bash "$SCRIPT" 2 2>&1) || RC=$?
assert_exit "< 3 substantive exits 1" 1 "$RC"
echo "$output" | grep -qi "INCOMPLETE" && echo "  PASS: INCOMPLETE message printed" && PASS=$((PASS + 1)) || { echo "  FAIL: INCOMPLETE message missing"; FAIL=$((FAIL + 1)); }

# --- (4) validated with >= 3 substantive attempts ---
echo ""
echo "--- (4) >= 3 substantive attempts ---"
WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/attempts"
cat > "$WORK4/.superteam/attempts/infra-failure-3.md" <<'FM'
---
increment: 3
failure_type: infrastructure
remediation_attempts: 0
status: investigating
---

## Failure Description

GPU OOM during batch training.

## Knowledge Base Search

Searched OOM patterns - found batch-size tuning doc.

## Remediation Attempts

### Attempt 1
- **What was tried:** Reduced batch size to 16
- **Actual outcome:** OOM still occurred, but later in training

### Attempt 2
- **What was tried:** Enabled gradient checkpointing
- **Actual outcome:** Memory usage dropped 30%

### Attempt 3
- **What was tried:** Switched to mixed precision training
- **Actual outcome:** OOM resolved, training stable
FM
RC=0
output=$(cd "$WORK4" && bash "$SCRIPT" 3 2>&1) || RC=$?
assert_exit ">= 3 substantive exits 0" 0 "$RC"
echo "$output" | grep -qi "Validated" && echo "  PASS: validated message printed" && PASS=$((PASS + 1)) || { echo "  FAIL: validated message missing"; FAIL=$((FAIL + 1)); }
# Verify frontmatter was updated
grep -q "remediation_attempts: 3" "$WORK4/.superteam/attempts/infra-failure-3.md" && echo "  PASS: remediation_attempts updated to 3" && PASS=$((PASS + 1)) || { echo "  FAIL: remediation_attempts not updated"; FAIL=$((FAIL + 1)); }
grep -q "status: concluded" "$WORK4/.superteam/attempts/infra-failure-3.md" && echo "  PASS: status updated to concluded" && PASS=$((PASS + 1)) || { echo "  FAIL: status not updated"; FAIL=$((FAIL + 1)); }

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
