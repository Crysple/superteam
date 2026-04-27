#!/bin/bash
# test-state-mutate.sh - Tests for scripts/state-mutate.sh
# Covers CAS conflict detection, CAS_RETRY_BOUND semantics, atomic
# tmp+rename (no torn state after racing writers), and schema default
# preservation (watchdog_stall_count=0). Lighter-weight companion to
# the final gate G-3; validates contract-frozen behaviour at unit level.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_MUTATE="$PLUGIN_ROOT/scripts/state-mutate.sh"

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

# ===========================================================================
# (1) --init creates state.json with frozen schema defaults
# ===========================================================================
echo ""
echo "--- (1) --init: schema defaults ---"

(cd "$TMPDIR" && bash "$STATE_MUTATE" --init)

STATE="$TMPDIR/.superteam/state.json"
if [ ! -f "$STATE" ]; then
  echo "  FAIL: state.json not created at $STATE"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: state.json created"
  PASS=$((PASS + 1))
fi

assert_eq "revision initialized to 0" "0" "$(jq -r '.revision' "$STATE")"
assert_eq "schema_version initialized to 1" "1" "$(jq -r '.schema_version' "$STATE")"
assert_eq "watchdog_stall_count default is 0" "0" "$(jq -r '.watchdog_stall_count' "$STATE")"
assert_eq "loop.current_increment default" "0" "$(jq -r '.loop.current_increment' "$STATE")"

# Idempotent: second --init is a no-op (revision stays 0).
(cd "$TMPDIR" && bash "$STATE_MUTATE" --init)
assert_eq "idempotent --init (revision still 0)" "0" "$(jq -r '.revision' "$STATE")"

if ! command -v flock >/dev/null 2>&1; then
  echo ""
  echo "  SKIP: flock not available — skipping sections 2-5 (Linux required)"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi

# ===========================================================================
# (2) --set bumps revision and writes field
# ===========================================================================
echo ""
echo "--- (2) --set: revision bump + field write ---"

(cd "$TMPDIR" && bash "$STATE_MUTATE" --set "phase=planning")
assert_eq "revision bumped to 1" "1" "$(jq -r '.revision' "$STATE")"

# String value path: use a non-JSON-literal value.
(cd "$TMPDIR" && bash "$STATE_MUTATE" --set "phase=execute")
assert_eq "phase written as string" "execute" "$(jq -r '.phase' "$STATE")"
assert_eq "revision bumped to 2" "2" "$(jq -r '.revision' "$STATE")"

# ===========================================================================
# (3) CAS conflict: two concurrent writers, retries disabled
# Option-2 pattern (lessons-learned inc-1): capture via wait <pid>,
# never via in-subshell side-channel files.
# ===========================================================================
echo ""
echo "--- (3) CAS conflict: racing writers with CAS_RETRY_BOUND=0 ---"

RACE_DIR=$(mktemp -d)
(cd "$RACE_DIR" && bash "$STATE_MUTATE" --init)

LOG_A="$RACE_DIR/a.log"
LOG_B="$RACE_DIR/b.log"

(
  cd "$RACE_DIR"
  CAS_RETRY_BOUND=0 bash "$STATE_MUTATE" --set "phase=A" > "$LOG_A" 2>&1
) &
PID_A=$!

(
  cd "$RACE_DIR"
  CAS_RETRY_BOUND=0 bash "$STATE_MUTATE" --set "phase=B" > "$LOG_B" 2>&1
) &
PID_B=$!

EXIT_A=0
EXIT_B=0
wait "$PID_A" || EXIT_A=$?
wait "$PID_B" || EXIT_B=$?

SUCCESSES=0
CONFLICTS=0
[ "$EXIT_A" -eq 0 ] && SUCCESSES=$((SUCCESSES + 1))
[ "$EXIT_B" -eq 0 ] && SUCCESSES=$((SUCCESSES + 1))
[ "$EXIT_A" -eq 9 ] && CONFLICTS=$((CONFLICTS + 1))
[ "$EXIT_B" -eq 9 ] && CONFLICTS=$((CONFLICTS + 1))

assert_eq "exactly one racer succeeded" "1" "$SUCCESSES"
assert_eq "exactly one racer got CAS_CONFLICT_EXIT=9" "1" "$CONFLICTS"

FINAL_VAL="$(jq -r '.phase' "$RACE_DIR/.superteam/state.json")"
case "$FINAL_VAL" in
  A|B)
    echo "  PASS: final state == winner's write (got '$FINAL_VAL')"
    PASS=$((PASS + 1))
    ;;
  *)
    echo "  FAIL: final state was not A or B (got '$FINAL_VAL')"
    FAIL=$((FAIL + 1))
    ;;
esac

FINAL_REV="$(jq -r '.revision' "$RACE_DIR/.superteam/state.json")"
assert_eq "revision after race bumped exactly once" "1" "$FINAL_REV"

rm -rf "$RACE_DIR"

# ===========================================================================
# (4) get command reads a field
# ===========================================================================
echo ""
echo "--- (4) get: read current_increment ---"

GOT="$(cd "$TMPDIR" && bash "$STATE_MUTATE" get current_increment)"
assert_eq "get current_increment returns '0'" "0" "$GOT"

# ===========================================================================
# (5) usage error: --set with no arg exits 2
# ===========================================================================
echo ""
echo "--- (5) usage errors ---"

RC=0
(cd "$TMPDIR" && bash "$STATE_MUTATE" --set 2>/dev/null) || RC=$?
assert_exit "--set without FIELD=VALUE exits 2" 2 "$RC"

RC=0
(cd "$TMPDIR" && bash "$STATE_MUTATE" bogus 2>/dev/null) || RC=$?
assert_exit "unknown subcommand exits 2" 2 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
