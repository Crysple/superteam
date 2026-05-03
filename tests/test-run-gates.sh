#!/bin/bash
# test-run-gates.sh - Tests for scripts/run-gates.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_GATES="$PLUGIN_ROOT/scripts/run-gates.sh"

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

echo "=== test-run-gates ==="

# ---------------------------------------------------------------------------
# (1) No args exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no args exits 2 ---"

RC=0
(cd "$TMPDIR" && bash "$RUN_GATES" 2>/dev/null) || RC=$?
assert_exit "no args exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (2) Missing scripts directory exits 2
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) missing scripts dir exits 2 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2"
RC=0
(cd "$WORK2" && bash "$RUN_GATES" 99 2>/dev/null) || RC=$?
assert_exit "missing scripts dir exits 2" 2 "$RC"

# ---------------------------------------------------------------------------
# (3) All gates pass -> exit 0, all_passed=true
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) all gates pass ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/scripts/increment-1"
mkdir -p "$WORK3/.superteam/gate-results"

cat > "$WORK3/.superteam/scripts/increment-1/gate-check-alpha.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

cat > "$WORK3/.superteam/scripts/increment-1/gate-check-beta.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

RC=0
(cd "$WORK3" && bash "$RUN_GATES" 1 >/dev/null 2>&1) || RC=$?
assert_exit "all-pass exits 0" 0 "$RC"

RESULTS_FILE="$WORK3/.superteam/gate-results/increment-1.json"
assert_eq "results file created" "true" "$([ -f "$RESULTS_FILE" ] && echo true || echo false)"
assert_eq "all_passed is true" "true" "$(jq -r '.all_passed' "$RESULTS_FILE")"
assert_eq "total is 2" "2" "$(jq -r '.total' "$RESULTS_FILE")"
assert_eq "passed is 2" "2" "$(jq -r '.passed' "$RESULTS_FILE")"
assert_eq "failed is 0" "0" "$(jq -r '.failed' "$RESULTS_FILE")"
assert_eq "increment field" "1" "$(jq -r '.increment' "$RESULTS_FILE")"

# ---------------------------------------------------------------------------
# (4) One gate fails -> exit 1, all_passed=false
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) one gate fails ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/scripts/increment-2"
mkdir -p "$WORK4/.superteam/gate-results"

cat > "$WORK4/.superteam/scripts/increment-2/gate-check-pass.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

cat > "$WORK4/.superteam/scripts/increment-2/gate-check-fail.sh" <<'GATE'
#!/bin/bash
echo "FAIL reason"
exit 1
GATE

RC=0
(cd "$WORK4" && bash "$RUN_GATES" 2 >/dev/null 2>&1) || RC=$?
assert_exit "one failing gate exits 1" 1 "$RC"

RF4="$WORK4/.superteam/gate-results/increment-2.json"
assert_eq "all_passed is false" "false" "$(jq -r '.all_passed' "$RF4")"
assert_eq "failed is 1" "1" "$(jq -r '.failed' "$RF4")"
assert_eq "passed is 1" "1" "$(jq -r '.passed' "$RF4")"

# ---------------------------------------------------------------------------
# (5) "final" special case writes to final-integration.json
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) final special case ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/scripts/final"
mkdir -p "$WORK5/.superteam/gate-results"

cat > "$WORK5/.superteam/scripts/final/gate-check-final.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

RC=0
(cd "$WORK5" && bash "$RUN_GATES" final >/dev/null 2>&1) || RC=$?
assert_exit "final exits 0" 0 "$RC"

RF5="$WORK5/.superteam/gate-results/final-integration.json"
assert_eq "final-integration.json created" "true" "$([ -f "$RF5" ] && echo true || echo false)"
assert_eq "increment field is 'final'" "final" "$(jq -r '.increment' "$RF5")"

# ---------------------------------------------------------------------------
# (6) "version-N" special case writes to version-N.json
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) version-N special case ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam/scripts/version-3"
mkdir -p "$WORK6/.superteam/gate-results"

cat > "$WORK6/.superteam/scripts/version-3/gate-check-skill.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

RC=0
(cd "$WORK6" && bash "$RUN_GATES" version-3 >/dev/null 2>&1) || RC=$?
assert_exit "version-3 exits 0" 0 "$RC"

RF6="$WORK6/.superteam/gate-results/version-3.json"
assert_eq "version-3.json created" "true" "$([ -f "$RF6" ] && echo true || echo false)"
assert_eq "increment field is 'version-3'" "version-3" "$(jq -r '.increment' "$RF6")"

# ---------------------------------------------------------------------------
# (7) preconditions.sh is also run when present
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) preconditions.sh is included ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam/scripts/increment-5"
mkdir -p "$WORK7/.superteam/gate-results"

cat > "$WORK7/.superteam/scripts/increment-5/preconditions.sh" <<'GATE'
#!/bin/bash
echo "preconditions ok"
exit 0
GATE

RC=0
(cd "$WORK7" && bash "$RUN_GATES" 5 >/dev/null 2>&1) || RC=$?
assert_exit "preconditions.sh included, exits 0" 0 "$RC"

RF7="$WORK7/.superteam/gate-results/increment-5.json"
assert_eq "total includes preconditions" "1" "$(jq -r '.total' "$RF7")"
assert_contains "preconditions in gates output" "preconditions.sh" "$(jq -r '.gates[0].script' "$RF7")"

# ---------------------------------------------------------------------------
# (8) Gate with REQUIRES but no gate-inputs.json records as fail
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) REQUIRES without gate-inputs.json fails gate ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam/scripts/increment-6"
mkdir -p "$WORK8/.superteam/gate-results"

cat > "$WORK8/.superteam/scripts/increment-6/gate-check-needs-input.sh" <<'GATE'
#!/bin/bash
# REQUIRES: some_file_path
# CATEGORY: execution-evidence
echo "PASS"
exit 0
GATE

RC=0
(cd "$WORK8" && bash "$RUN_GATES" 6 >/dev/null 2>&1) || RC=$?
assert_exit "missing gate-inputs exits 1" 1 "$RC"

RF8="$WORK8/.superteam/gate-results/increment-6.json"
assert_eq "all_passed is false" "false" "$(jq -r '.all_passed' "$RF8")"
assert_eq "gate recorded as fail" "fail" "$(jq -r '.gates[0].status' "$RF8")"

# ---------------------------------------------------------------------------
# (9) Gate with REQUIRES and matching gate-inputs.json passes
# ---------------------------------------------------------------------------
echo ""
echo "--- (9) REQUIRES satisfied by gate-inputs.json ---"

WORK9="$TMPDIR/t9"
mkdir -p "$WORK9/.superteam/scripts/increment-7"
mkdir -p "$WORK9/.superteam/gate-results"

DUMMY_FILE="$WORK9/dummy.txt"
printf 'hello\n' > "$DUMMY_FILE"

cat > "$WORK9/.superteam/gate-inputs.json" <<INPUTS
{"some_file_path": "$DUMMY_FILE"}
INPUTS

cat > "$WORK9/.superteam/scripts/increment-7/gate-check-needs-input.sh" <<'GATE'
#!/bin/bash
# REQUIRES: some_file_path
# CATEGORY: execution-evidence
[ -f "$1" ] && echo "PASS" && exit 0
echo "FAIL"
exit 1
GATE

RC=0
(cd "$WORK9" && bash "$RUN_GATES" 7 >/dev/null 2>&1) || RC=$?
assert_exit "gate-inputs satisfied exits 0" 0 "$RC"

RF9="$WORK9/.superteam/gate-results/increment-7.json"
assert_eq "gate passed with input" "pass" "$(jq -r '.gates[0].status' "$RF9")"

# ---------------------------------------------------------------------------
# (10) Results JSON contains timestamp and gates array
# ---------------------------------------------------------------------------
echo ""
echo "--- (10) results JSON schema ---"

RF3="$WORK3/.superteam/gate-results/increment-1.json"
TS="$(jq -r '.timestamp' "$RF3")"
assert_contains "timestamp present and non-empty" "T" "$TS"
GATES_LEN="$(jq -r '.gates | length' "$RF3")"
assert_eq "gates is array of length 2" "2" "$GATES_LEN"
assert_eq "gate entry has script field" "gate-check-alpha.sh" "$(jq -r '[.gates[] | select(.script=="gate-check-alpha.sh")] | .[0].script' "$RF3")"
assert_eq "gate entry has status field" "pass" "$(jq -r '[.gates[] | select(.script=="gate-check-alpha.sh")] | .[0].status' "$RF3")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
