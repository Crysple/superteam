#!/bin/bash
# test-invariant-check.sh - Tests for hooks/invariant-check.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/invariant-check.sh"

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

echo "=== test-invariant-check ==="

# Helper: run hook with given stdin and work directory
run_hook() {
  local input="$1" work_dir="$2"
  local rc=0
  printf '%s' "$input" | (cd "$work_dir" && bash "$HOOK" >/dev/null 2>&1) || rc=$?
  printf '%d' "$rc"
}

# ---------------------------------------------------------------------------
# (1) Non-git-commit stdin → exits 0 (passes through)
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) non-git-commit stdin exits 0 ---"

WORK1="$TMPDIR/t1"
mkdir -p "$WORK1/.superteam"
RC=$(run_hook '{"command": "npm test"}' "$WORK1")
assert_exit "non-git-commit exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (2) No validation-commands.txt → exits 0 (passthrough)
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) no validation-commands.txt exits 0 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
RC=$(run_hook '{"command": "git commit -m \"fix\""}' "$WORK2")
assert_exit "no commands file exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) Empty validation-commands.txt → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) empty validation commands exits 0 ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
printf '' > "$WORK3/.superteam/validation-commands.txt"
RC=$(run_hook '{"command": "git commit -m \"fix\""}' "$WORK3")
assert_exit "empty commands exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (4) All validation commands pass → exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) all passing commands exits 0 ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam"
printf 'true, true' > "$WORK4/.superteam/validation-commands.txt"
RC=$(run_hook '{"command": "git commit -m \"fix\""}' "$WORK4")
assert_exit "all passing commands exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (5) One failing validation command → exits 1 (commit blocked)
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) one failing command exits 1 ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam"
printf 'true, false' > "$WORK5/.superteam/validation-commands.txt"
RC=$(run_hook '{"command": "git commit -m \"fix\""}' "$WORK5")
assert_exit "failing command exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (6) Empty stdin → exits 0 (no tool input; hook skips safely)
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) empty stdin exits 0 ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam"
printf 'true' > "$WORK6/.superteam/validation-commands.txt"
RC=$(run_hook '' "$WORK6")
assert_exit "empty stdin exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (7) stdin without "git commit" string → exits 0 (not a commit command)
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) non-commit command exits 0 ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam"
printf 'false' > "$WORK7/.superteam/validation-commands.txt"
RC=$(run_hook '{"command": "git push"}' "$WORK7")
assert_exit "git push is not a commit, exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (8) Multiple passing commands, one failing → exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) mixed pass/fail commands exits 1 ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam"
printf 'true, true, false, true' > "$WORK8/.superteam/validation-commands.txt"
RC=$(run_hook '{"command": "git commit --all"}' "$WORK8")
assert_exit "mixed commands exits 1" 1 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
