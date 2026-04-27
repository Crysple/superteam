#!/bin/bash
# test-record-event.sh - Tests for scripts/record-event.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD_EVENT="$PLUGIN_ROOT/scripts/record-event.sh"

if ! command -v flock >/dev/null 2>&1; then
  echo "=== test-record-event ==="
  echo "  SKIP: flock not available on this platform (Linux required)"
  echo ""
  echo "Results: 0 passed, 0 failed (skipped)"
  exit 0
fi

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

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "  FAIL: $desc (expected NOT to contain '$needle')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

echo "=== test-record-event ==="

# ---------------------------------------------------------------------------
# (1) Missing stream exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) missing stream rejected ---"

WORK1="$TMPDIR/t1"
mkdir -p "$WORK1/.superteam"
RC=0
(cd "$WORK1" && bash "$RECORD_EVENT" --actor agent --type decision --payload '{}' 2>/dev/null) || RC=$?
assert_exit "missing events.jsonl exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (2) Happy path: record appended with correct schema fields
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) happy path ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
touch "$WORK2/.superteam/events.jsonl"

RC=0
(cd "$WORK2" && bash "$RECORD_EVENT" --actor "orchestrator" --type "decision" --payload '{"reason":"ok"}') || RC=$?
assert_exit "valid record exits 0" 0 "$RC"

LINE="$(tail -1 "$WORK2/.superteam/events.jsonl")"
assert_contains "record contains actor" '"actor":"orchestrator"' "$LINE"
assert_contains "record contains type" '"type":"decision"' "$LINE"
assert_contains "record contains payload key" '"reason"' "$LINE"
assert_contains "record contains ts field" '"ts"' "$LINE"

# ---------------------------------------------------------------------------
# (3) All valid type enum values are accepted
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) valid type enums ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
touch "$WORK3/.superteam/events.jsonl"

for TYPE in decision anomaly mutation escalation transition; do
  RC=0
  (cd "$WORK3" && bash "$RECORD_EVENT" --actor "a" --type "$TYPE" --payload '{}') || RC=$?
  assert_exit "type '$TYPE' accepted" 0 "$RC"
done

# ---------------------------------------------------------------------------
# (4) Invalid type enum rejected
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) invalid type enum ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam"
touch "$WORK4/.superteam/events.jsonl"

RC=0
(cd "$WORK4" && bash "$RECORD_EVENT" --actor "a" --type "bogus" --payload '{}' 2>/dev/null) || RC=$?
assert_exit "invalid type exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (5) Missing required args each exit 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) missing required args ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam"
touch "$WORK5/.superteam/events.jsonl"

RC=0
(cd "$WORK5" && bash "$RECORD_EVENT" --type "decision" --payload '{}' 2>/dev/null) || RC=$?
assert_exit "missing --actor exits 1" 1 "$RC"

RC=0
(cd "$WORK5" && bash "$RECORD_EVENT" --actor "a" --payload '{}' 2>/dev/null) || RC=$?
assert_exit "missing --type exits 1" 1 "$RC"

RC=0
(cd "$WORK5" && bash "$RECORD_EVENT" --actor "a" --type "decision" 2>/dev/null) || RC=$?
assert_exit "missing --payload exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (6) Invalid JSON payload rejected
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) invalid JSON payload ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam"
touch "$WORK6/.superteam/events.jsonl"

RC=0
(cd "$WORK6" && bash "$RECORD_EVENT" --actor "a" --type "anomaly" --payload 'not-json' 2>/dev/null) || RC=$?
assert_exit "invalid JSON payload exits 1" 1 "$RC"

LINES="$(wc -l < "$WORK6/.superteam/events.jsonl" | tr -d ' ')"
assert_eq "stream untouched after invalid payload" "0" "$LINES"

# ---------------------------------------------------------------------------
# (7) Multiple appends produce multiple lines, each valid JSON
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) multiple appends ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam"
touch "$WORK7/.superteam/events.jsonl"

(cd "$WORK7" && bash "$RECORD_EVENT" --actor "a" --type "decision" --payload '{"n":1}')
(cd "$WORK7" && bash "$RECORD_EVENT" --actor "b" --type "mutation" --payload '{"n":2}')
(cd "$WORK7" && bash "$RECORD_EVENT" --actor "c" --type "transition" --payload '{"n":3}')

LINES="$(wc -l < "$WORK7/.superteam/events.jsonl" | tr -d ' ')"
assert_eq "three appends produce three lines" "3" "$LINES"

while IFS= read -r line; do
  RC=0
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 || RC=$?
  assert_exit "each line is valid JSON" 0 "$RC"
done < "$WORK7/.superteam/events.jsonl"

# ---------------------------------------------------------------------------
# (8) Unknown argument exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) unknown argument ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam"
touch "$WORK8/.superteam/events.jsonl"

RC=0
(cd "$WORK8" && bash "$RECORD_EVENT" --actor "a" --type "decision" --payload '{}' --unknown val 2>/dev/null) || RC=$?
assert_exit "unknown argument exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (9) SUPERTEAM_DIR env override is respected
# ---------------------------------------------------------------------------
echo ""
echo "--- (9) SUPERTEAM_DIR env override ---"

WORK9="$TMPDIR/t9"
CUSTOM="$WORK9/custom-dir"
mkdir -p "$CUSTOM"
touch "$CUSTOM/events.jsonl"

RC=0
(cd "$WORK9" && SUPERTEAM_DIR="custom-dir" bash "$RECORD_EVENT" --actor "a" --type "escalation" --payload '{"x":1}') || RC=$?
assert_exit "SUPERTEAM_DIR override exits 0" 0 "$RC"

LINES="$(wc -l < "$CUSTOM/events.jsonl" | tr -d ' ')"
assert_eq "record written to custom dir" "1" "$LINES"

# ---------------------------------------------------------------------------
# (10) Payload is nested as object (not re-stringified)
# ---------------------------------------------------------------------------
echo ""
echo "--- (10) payload embedded as JSON object ---"

WORK10="$TMPDIR/t10"
mkdir -p "$WORK10/.superteam"
touch "$WORK10/.superteam/events.jsonl"

(cd "$WORK10" && bash "$RECORD_EVENT" --actor "a" --type "decision" --payload '{"k":"v","num":42}')
LINE="$(tail -1 "$WORK10/.superteam/events.jsonl")"
PAYLOAD_TYPE="$(printf '%s' "$LINE" | jq -r '.payload | type')"
assert_eq "payload is an object (not a string)" "object" "$PAYLOAD_TYPE"
assert_eq "payload.num is 42" "42" "$(printf '%s' "$LINE" | jq -r '.payload.num')"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
