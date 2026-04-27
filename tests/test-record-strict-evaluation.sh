#!/bin/bash
# test-record-strict-evaluation.sh - Tests for scripts/record-strict-evaluation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD_STRICT="$PLUGIN_ROOT/scripts/record-strict-evaluation.sh"

if ! command -v flock >/dev/null 2>&1; then
  echo "=== test-record-strict-evaluation ==="
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

echo "=== test-record-strict-evaluation ==="

# ---------------------------------------------------------------------------
# (1) Missing stream exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) missing stream rejected ---"

WORK1="$TMPDIR/t1"
mkdir -p "$WORK1/.superteam"
REPORT1="$TMPDIR/report1.md"
printf 'body text\n' > "$REPORT1"

RC=0
(cd "$WORK1" && bash "$RECORD_STRICT" --cycle 1 --verdict FAIL --report-file "$REPORT1" 2>/dev/null) || RC=$?
assert_exit "missing stream exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (2) Happy path: FAIL verdict with frontmatter arrays
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) happy path with frontmatter ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
touch "$WORK2/.superteam/strict-evaluations.jsonl"

REPORT2="$TMPDIR/report2.md"
cat > "$REPORT2" <<'REPORT'
---
hard_gates_failed: ["G-1", "G-2"]
soft_gates_unmet: ["S-1"]
spec_requirements_unsatisfied: []
specific_gaps: ["gap-a"]
---
The body of the report goes here.
REPORT

RC=0
(cd "$WORK2" && bash "$RECORD_STRICT" --cycle 1 --verdict FAIL --report-file "$REPORT2") || RC=$?
assert_exit "FAIL verdict exits 0" 0 "$RC"

LINE="$(tail -1 "$WORK2/.superteam/strict-evaluations.jsonl")"
assert_eq "cycle is 1" "1" "$(printf '%s' "$LINE" | jq -r '.cycle')"
assert_eq "verdict is FAIL" "FAIL" "$(printf '%s' "$LINE" | jq -r '.verdict')"
assert_eq "hard_gates_failed length 2" "2" "$(printf '%s' "$LINE" | jq -r '.hard_gates_failed | length')"
assert_eq "hard_gates_failed[0] is G-1" "G-1" "$(printf '%s' "$LINE" | jq -r '.hard_gates_failed[0]')"
assert_eq "soft_gates_unmet length 1" "1" "$(printf '%s' "$LINE" | jq -r '.soft_gates_unmet | length')"
assert_eq "spec_requirements_unsatisfied is empty array" "0" "$(printf '%s' "$LINE" | jq -r '.spec_requirements_unsatisfied | length')"
assert_eq "specific_gaps[0] is gap-a" "gap-a" "$(printf '%s' "$LINE" | jq -r '.specific_gaps[0]')"
assert_contains "summary contains body text" "body of the report" "$(printf '%s' "$LINE" | jq -r '.summary')"

# ---------------------------------------------------------------------------
# (3) Happy path: PASS verdict
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) PASS verdict ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
touch "$WORK3/.superteam/strict-evaluations.jsonl"

REPORT3="$TMPDIR/report3.md"
printf 'All requirements met.\n' > "$REPORT3"

RC=0
(cd "$WORK3" && bash "$RECORD_STRICT" --cycle 0 --verdict PASS --report-file "$REPORT3") || RC=$?
assert_exit "PASS verdict exits 0" 0 "$RC"

LINE="$(tail -1 "$WORK3/.superteam/strict-evaluations.jsonl")"
assert_eq "verdict is PASS" "PASS" "$(printf '%s' "$LINE" | jq -r '.verdict')"
assert_eq "cycle 0 accepted" "0" "$(printf '%s' "$LINE" | jq -r '.cycle')"
assert_eq "hard_gates_failed defaults to []" "0" "$(printf '%s' "$LINE" | jq -r '.hard_gates_failed | length')"

# ---------------------------------------------------------------------------
# (4) Idempotency: duplicate cycle rejected, stream unchanged
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) idempotency: duplicate cycle rejected ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam"
touch "$WORK4/.superteam/strict-evaluations.jsonl"

REPORT4="$TMPDIR/report4.md"
printf 'first write\n' > "$REPORT4"

(cd "$WORK4" && bash "$RECORD_STRICT" --cycle 5 --verdict FAIL --report-file "$REPORT4")

LINES_BEFORE="$(wc -l < "$WORK4/.superteam/strict-evaluations.jsonl" | tr -d ' ')"

REPORT4B="$TMPDIR/report4b.md"
printf 'second write\n' > "$REPORT4B"

RC=0
(cd "$WORK4" && bash "$RECORD_STRICT" --cycle 5 --verdict PASS --report-file "$REPORT4B" 2>/dev/null) || RC=$?
assert_exit "duplicate cycle exits 1" 1 "$RC"

LINES_AFTER="$(wc -l < "$WORK4/.superteam/strict-evaluations.jsonl" | tr -d ' ')"
assert_eq "stream unchanged after duplicate" "$LINES_BEFORE" "$LINES_AFTER"

# ---------------------------------------------------------------------------
# (5) Missing required args each exit 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) missing required args ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam"
touch "$WORK5/.superteam/strict-evaluations.jsonl"

REPORT5="$TMPDIR/report5.md"
printf 'body\n' > "$REPORT5"

RC=0
(cd "$WORK5" && bash "$RECORD_STRICT" --verdict FAIL --report-file "$REPORT5" 2>/dev/null) || RC=$?
assert_exit "missing --cycle exits 1" 1 "$RC"

RC=0
(cd "$WORK5" && bash "$RECORD_STRICT" --cycle 1 --report-file "$REPORT5" 2>/dev/null) || RC=$?
assert_exit "missing --verdict exits 1" 1 "$RC"

RC=0
(cd "$WORK5" && bash "$RECORD_STRICT" --cycle 1 --verdict FAIL 2>/dev/null) || RC=$?
assert_exit "missing --report-file exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (6) Invalid verdict enum rejected
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) invalid verdict enum ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam"
touch "$WORK6/.superteam/strict-evaluations.jsonl"

REPORT6="$TMPDIR/report6.md"
printf 'body\n' > "$REPORT6"

RC=0
(cd "$WORK6" && bash "$RECORD_STRICT" --cycle 1 --verdict MAYBE --report-file "$REPORT6" 2>/dev/null) || RC=$?
assert_exit "invalid verdict exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (7) Non-integer cycle rejected
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) non-integer cycle rejected ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam"
touch "$WORK7/.superteam/strict-evaluations.jsonl"

REPORT7="$TMPDIR/report7.md"
printf 'body\n' > "$REPORT7"

RC=0
(cd "$WORK7" && bash "$RECORD_STRICT" --cycle "abc" --verdict FAIL --report-file "$REPORT7" 2>/dev/null) || RC=$?
assert_exit "non-integer cycle exits 1" 1 "$RC"

RC=0
(cd "$WORK7" && bash "$RECORD_STRICT" --cycle "-1" --verdict FAIL --report-file "$REPORT7" 2>/dev/null) || RC=$?
assert_exit "negative cycle exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (8) Unreadable report file exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) unreadable report file ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam"
touch "$WORK8/.superteam/strict-evaluations.jsonl"

RC=0
(cd "$WORK8" && bash "$RECORD_STRICT" --cycle 1 --verdict FAIL --report-file "/nonexistent/path.md" 2>/dev/null) || RC=$?
assert_exit "missing report file exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (9) Report file without frontmatter: body is full content, arrays default []
# ---------------------------------------------------------------------------
echo ""
echo "--- (9) no frontmatter defaults to empty arrays ---"

WORK9="$TMPDIR/t9"
mkdir -p "$WORK9/.superteam"
touch "$WORK9/.superteam/strict-evaluations.jsonl"

REPORT9="$TMPDIR/report9.md"
printf 'Plain body without frontmatter.\n' > "$REPORT9"

RC=0
(cd "$WORK9" && bash "$RECORD_STRICT" --cycle 2 --verdict FAIL --report-file "$REPORT9") || RC=$?
assert_exit "no-frontmatter report exits 0" 0 "$RC"

LINE="$(tail -1 "$WORK9/.superteam/strict-evaluations.jsonl")"
assert_eq "hard_gates_failed defaults []" "0" "$(printf '%s' "$LINE" | jq -r '.hard_gates_failed | length')"
assert_eq "soft_gates_unmet defaults []" "0" "$(printf '%s' "$LINE" | jq -r '.soft_gates_unmet | length')"
assert_contains "summary is full body" "Plain body without frontmatter" "$(printf '%s' "$LINE" | jq -r '.summary')"

# ---------------------------------------------------------------------------
# (10) --payload accepted without error (forward-compat; ignored)
# ---------------------------------------------------------------------------
echo ""
echo "--- (10) --payload forward-compat ---"

WORK10="$TMPDIR/t10"
mkdir -p "$WORK10/.superteam"
touch "$WORK10/.superteam/strict-evaluations.jsonl"

REPORT10="$TMPDIR/report10.md"
printf 'body\n' > "$REPORT10"

RC=0
(cd "$WORK10" && bash "$RECORD_STRICT" --cycle 1 --verdict PASS --report-file "$REPORT10" --payload '{"extra":true}') || RC=$?
assert_exit "--payload accepted for forward-compat" 0 "$RC"

# ---------------------------------------------------------------------------
# (11) Multiple distinct cycles produce multiple lines
# ---------------------------------------------------------------------------
echo ""
echo "--- (11) multiple distinct cycles ---"

WORK11="$TMPDIR/t11"
mkdir -p "$WORK11/.superteam"
touch "$WORK11/.superteam/strict-evaluations.jsonl"

REP="$TMPDIR/rep.md"
printf 'body\n' > "$REP"

(cd "$WORK11" && bash "$RECORD_STRICT" --cycle 1 --verdict FAIL --report-file "$REP")
(cd "$WORK11" && bash "$RECORD_STRICT" --cycle 2 --verdict PASS --report-file "$REP")
(cd "$WORK11" && bash "$RECORD_STRICT" --cycle 3 --verdict FAIL --report-file "$REP")

LINES="$(wc -l < "$WORK11/.superteam/strict-evaluations.jsonl" | tr -d ' ')"
assert_eq "three distinct cycles produce three lines" "3" "$LINES"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
