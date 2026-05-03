#!/bin/bash
# test-manager-heuristic-missing-status.sh - Tests for manager-heuristic-missing-status.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/manager-heuristic-missing-status.sh"

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

echo "=== test-manager-heuristic-missing-status ==="

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
# (2) No current_version (engineering form): exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) no current_version exits 0 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
cat > "$WORK2/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_version": ""
  }
}
EOF
RC=0
(cd "$WORK2" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no current_version exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) No active agents: exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) no active agents exits 0 ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam"
cat > "$WORK3/.superteam/state.json" <<'EOF'
{
  "loop": {
    "current_version": "1"
  },
  "agents": {
    "active_agents": []
  }
}
EOF
RC=0
(cd "$WORK3" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no active agents exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (4) Fresh spawn with status file: exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) fresh spawn with status file exits 0 ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/status"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$WORK4/.superteam/state.json" <<EOF
{
  "loop": {
    "current_version": "1"
  },
  "agents": {
    "active_agents": ["generator-1"],
    "spawn_history": [
      {
        "name": "generator-1",
        "spawned_at": "$NOW"
      }
    ]
  }
}
EOF
cat > "$WORK4/.superteam/status/version-1-generator.md" <<'EOF'
---
phase: ready-for-testing
---
EOF
RC=0
(cd "$WORK4" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "fresh spawn with status file exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (5) Dead-on-arrival spawn (old, no status file): exits 1
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) dead-on-arrival spawn exits 1 ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/status"
OLD_TIME=$(date -u -d "600 seconds ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
          date -v-600S -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
          echo "2025-01-01T00:00:00Z")
cat > "$WORK5/.superteam/state.json" <<EOF
{
  "loop": {
    "current_version": "1"
  },
  "agents": {
    "active_agents": ["generator-1"],
    "spawn_history": [
      {
        "name": "generator-1",
        "spawned_at": "$OLD_TIME"
      }
    ]
  }
}
EOF
# No status file created
RC=0
(cd "$WORK5" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "dead-on-arrival spawn exits 1" 1 "$RC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
