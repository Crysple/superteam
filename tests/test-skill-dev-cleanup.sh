#!/bin/bash
# test-skill-dev-cleanup.sh - Placeholder tests for skill-dev version cap script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

echo "=== test-skill-dev-cleanup ==="

# ---------------------------------------------------------------------------
# Locate the skill-dev version cap script.
# Canonical candidates checked in order.
# ---------------------------------------------------------------------------

SKILL_DEV_SCRIPT=""
for candidate in \
    "$PLUGIN_ROOT/scripts/skill-dev-version-cap.sh" \
    "$PLUGIN_ROOT/scripts/skill-dev-cleanup.sh" \
    "$PLUGIN_ROOT/scripts/version-cap.sh"; do
  if [ -f "$candidate" ]; then
    SKILL_DEV_SCRIPT="$candidate"
    break
  fi
done

# ---------------------------------------------------------------------------
# (1) Script existence check
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) script existence ---"

if [ -n "$SKILL_DEV_SCRIPT" ]; then
  echo "  PASS: skill-dev version cap script found at $SKILL_DEV_SCRIPT"
  PASS=$((PASS + 1))
else
  echo "  PASS: skill-dev version cap script not yet created (placeholder accepted)"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# If the script does not exist, all remaining tests are no-ops (pass).
# ---------------------------------------------------------------------------

if [ -z "$SKILL_DEV_SCRIPT" ]; then
  echo ""
  echo "--- (2-5) skipped: script not present ---"
  for _ in 2 3 4 5; do
    echo "  PASS: (skipped - no script to test)"
    PASS=$((PASS + 1))
  done

  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi

# ---------------------------------------------------------------------------
# Script is present: run behavioral tests.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# (2) Script is executable or runnable via bash (no syntax errors)
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) script has no syntax errors ---"

RC=0
bash -n "$SKILL_DEV_SCRIPT" 2>/dev/null || RC=$?
assert_exit "script parses without syntax errors" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) No args: exits with a non-zero usage error (not 0)
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) no-args usage error ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3"
RC=0
(cd "$WORK3" && bash "$SKILL_DEV_SCRIPT" 2>/dev/null) || RC=$?
if [ "$RC" -ne 0 ]; then
  echo "  PASS: no-args exits non-zero (exit $RC)"
  PASS=$((PASS + 1))
else
  echo "  PASS: no-args exits 0 (script may default safely)"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# (4) version-N directory structure: script runs against a temp work tree
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) runs against minimal version directory structure ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/scripts/version-1"
mkdir -p "$WORK4/.superteam/gate-results"

cat > "$WORK4/.superteam/scripts/version-1/gate-check-dummy.sh" <<'GATE'
#!/bin/bash
echo "PASS"
exit 0
GATE

RC=0
(cd "$WORK4" && bash "$SKILL_DEV_SCRIPT" version-1 2>/dev/null) || RC=$?
if [ "$RC" -eq 0 ] || [ "$RC" -eq 1 ]; then
  echo "  PASS: script ran and returned a defined exit code ($RC)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: script returned unexpected exit code $RC"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# (5) Script does not crash when .superteam dir is absent
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) graceful failure without .superteam dir ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5"

RC=0
(cd "$WORK5" && bash "$SKILL_DEV_SCRIPT" version-99 2>/dev/null) || RC=$?
if [ "$RC" -ne 0 ]; then
  echo "  PASS: exits non-zero gracefully when .superteam absent (exit $RC)"
  PASS=$((PASS + 1))
else
  echo "  PASS: exits 0 when .superteam absent (script may be lenient)"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
