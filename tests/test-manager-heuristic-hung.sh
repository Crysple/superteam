#!/bin/bash
# test-manager-heuristic-hung.sh - Tests for manager-heuristic-hung.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/manager-heuristic-hung.sh"

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

echo "=== test-manager-heuristic-hung ==="

# ---------------------------------------------------------------------------
# (1) No state.json: exits 0 (fail-soft)
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no state.json exits 0 ---"

WORK1="$TMPDIR/t1"
mkdir -p "$WORK1"
RC=0
(cd "$WORK1" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no state.json exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (2) state.json with no current increment/version: exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) no current increment or version exits 0 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
cat > "$WORK2/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_increment": 0,
    "current_version": ""
  }
}
EOF
RC=0
(cd "$WORK2" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no current increment/version exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) Fresh work file (recent mtime): exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) fresh work file exits 0 ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/attempts"
cat > "$WORK3/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_increment": 1,
    "current_version": ""
  }
}
EOF
# Create a fresh work file
touch "$WORK3/.superteam/attempts/increment-1.md"
RC=0
(cd "$WORK3" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "fresh work file exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (4) Stale work file (old mtime): exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) stale work file exits 1 ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/attempts"
cat > "$WORK4/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_increment": 1,
    "current_version": ""
  }
}
EOF
# Create a work file with old mtime (600s ago)
touch -t $(date -v-600S +%Y%m%d%H%M) "$WORK4/.superteam/attempts/increment-1.md" 2>/dev/null || \
  touch -d "600 seconds ago" "$WORK4/.superteam/attempts/increment-1.md" 2>/dev/null || \
  touch "$WORK4/.superteam/attempts/increment-1.md" && sleep 1  # fallback
RC=0
(cd "$WORK4" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "stale work file exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (5) Skill-dev form: stale status file exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) skill-dev stale status file exits 1 ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/status"
cat > "$WORK5/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_increment": 0,
    "current_version": "1"
  }
}
EOF
# Create a stale status file
touch -t $(date -v-600S +%Y%m%d%H%M) "$WORK5/.superteam/status/version-1-generator.md" 2>/dev/null || \
  touch -d "600 seconds ago" "$WORK5/.superteam/status/version-1-generator.md" 2>/dev/null || \
  touch "$WORK5/.superteam/status/version-1-generator.md" && sleep 1
RC=0
(cd "$WORK5" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "skill-dev stale status file exits 1" 1 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
