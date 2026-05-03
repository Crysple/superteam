#!/bin/bash
# test-manager-heuristic-zombie.sh - Tests for scripts/manager-heuristic-zombie.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/manager-heuristic-zombie.sh"

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

echo "=== test-manager-heuristic-zombie ==="

# ---------------------------------------------------------------------------
# (1) No state.json exits 0 (fail-soft)
# ---------------------------------------------------------------------------
echo ""
echo "--- (1) no state.json exits 0 ---"

WORK1="$TMPDIR/t1"
mkdir -p "$WORK1"
RC=0
(cd "$WORK1" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no state.json exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (2) Engineering: no current_increment (=0) exits 0
# ---------------------------------------------------------------------------
echo ""
echo "--- (2) engineering: no active increment exits 0 ---"

WORK2="$TMPDIR/t2"
mkdir -p "$WORK2/.superteam"
cat > "$WORK2/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 0},
  "agents": {"active_agents": []},
  "session": {"task_form": "engineering"}
}
EOF
RC=0
(cd "$WORK2" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no active increment exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (3) Engineering: generator active, no verdict file → exits 0 (not zombie)
# ---------------------------------------------------------------------------
echo ""
echo "--- (3) engineering: active agent, no verdict → not zombie ---"

WORK3="$TMPDIR/t3"
mkdir -p "$WORK3/.superteam/verdicts"
cat > "$WORK3/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 1},
  "agents": {"active_agents": ["generator"]},
  "session": {"task_form": "engineering"}
}
EOF
RC=0
(cd "$WORK3" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "no verdict file exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (4) Engineering: generator active, REVISE verdict → exits 0 (not zombie)
# ---------------------------------------------------------------------------
echo ""
echo "--- (4) engineering: REVISE verdict → not zombie ---"

WORK4="$TMPDIR/t4"
mkdir -p "$WORK4/.superteam/verdicts"
cat > "$WORK4/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 1},
  "agents": {"active_agents": ["generator"]},
  "session": {"task_form": "engineering"}
}
EOF
cat > "$WORK4/.superteam/verdicts/increment-1.md" <<'EOF'
---
verdict: REVISE
---
EOF
RC=0
(cd "$WORK4" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "REVISE verdict exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (5) Engineering: generator active, APPROVED verdict → exits 1 (zombie!)
# ---------------------------------------------------------------------------
echo ""
echo "--- (5) engineering: APPROVED verdict → zombie ---"

WORK5="$TMPDIR/t5"
mkdir -p "$WORK5/.superteam/verdicts"
cat > "$WORK5/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 1},
  "agents": {"active_agents": ["generator"]},
  "session": {"task_form": "engineering"}
}
EOF
cat > "$WORK5/.superteam/verdicts/increment-1.md" <<'EOF'
---
verdict: APPROVED
---
EOF
RC=0
OUTPUT5=$(cd "$WORK5" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "APPROVED with active generator exits 1" 1 "$RC"
assert_contains "zombie message mentions generator" "generator" "$OUTPUT5"

# ---------------------------------------------------------------------------
# (6) Engineering: multiple roles — only evaluator active, APPROVED → zombie
# ---------------------------------------------------------------------------
echo ""
echo "--- (6) engineering: evaluator zombie ---"

WORK6="$TMPDIR/t6"
mkdir -p "$WORK6/.superteam/verdicts"
cat > "$WORK6/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 2},
  "agents": {"active_agents": ["evaluator"]},
  "session": {"task_form": "engineering"}
}
EOF
cat > "$WORK6/.superteam/verdicts/increment-2.md" <<'EOF'
---
verdict: APPROVED
---
EOF
RC=0
(cd "$WORK6" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "evaluator zombie exits 1" 1 "$RC"

# ---------------------------------------------------------------------------
# (7) Skill-dev: generator active, phase=implementing → exits 0 (not terminal)
# ---------------------------------------------------------------------------
echo ""
echo "--- (7) skill-dev: non-terminal phase → not zombie ---"

WORK7="$TMPDIR/t7"
mkdir -p "$WORK7/.superteam/status"
cat > "$WORK7/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 0, "current_version": "1"},
  "agents": {"active_agents": ["generator-1"]},
  "session": {"task_form": "skill-dev"}
}
EOF
cat > "$WORK7/.superteam/status/version-1-generator.md" <<'EOF'
---
phase: implementing
---
EOF
RC=0
(cd "$WORK7" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "non-terminal generator phase exits 0" 0 "$RC"

# ---------------------------------------------------------------------------
# (8) Skill-dev: generator active, phase=ready-for-testing → exits 1 (zombie!)
# ---------------------------------------------------------------------------
echo ""
echo "--- (8) skill-dev: generator at ready-for-testing → zombie ---"

WORK8="$TMPDIR/t8"
mkdir -p "$WORK8/.superteam/status"
cat > "$WORK8/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 0, "current_version": "2"},
  "agents": {"active_agents": ["generator-v2"]},
  "session": {"task_form": "skill-dev"}
}
EOF
cat > "$WORK8/.superteam/status/version-2-generator.md" <<'EOF'
---
phase: ready-for-testing
---
EOF
RC=0
OUTPUT8=$(cd "$WORK8" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "terminal generator phase exits 1" 1 "$RC"
assert_contains "zombie message" "ZOMBIE" "$OUTPUT8"

# ---------------------------------------------------------------------------
# (9) Skill-dev: test-evaluator active, phase=complete → exits 1 (zombie!)
# ---------------------------------------------------------------------------
echo ""
echo "--- (9) skill-dev: test-evaluator at complete → zombie ---"

WORK9="$TMPDIR/t9"
mkdir -p "$WORK9/.superteam/status"
cat > "$WORK9/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 0, "current_version": "3"},
  "agents": {"active_agents": ["test-evaluator"]},
  "session": {"task_form": "skill-dev"}
}
EOF
cat > "$WORK9/.superteam/status/version-3-test-evaluator.md" <<'EOF'
---
phase: complete
---
EOF
RC=0
OUTPUT9=$(cd "$WORK9" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "terminal test-evaluator exits 1" 1 "$RC"
assert_contains "zombie message" "ZOMBIE" "$OUTPUT9"

# ---------------------------------------------------------------------------
# (10) Skill-dev: tester active, phase=test-evaluating → exits 1 (zombie!)
# ---------------------------------------------------------------------------
echo ""
echo "--- (10) skill-dev: tester at test-evaluating → zombie ---"

WORK10="$TMPDIR/t10"
mkdir -p "$WORK10/.superteam/status"
cat > "$WORK10/.superteam/state.json" <<'EOF'
{
  "loop": {"current_increment": 0, "current_version": "4"},
  "agents": {"active_agents": ["tester-v4"]},
  "session": {"task_form": "skill-dev"}
}
EOF
cat > "$WORK10/.superteam/status/version-4-tester.md" <<'EOF'
---
phase: test-evaluating
---
EOF
RC=0
OUTPUT10=$(cd "$WORK10" && bash "$SCRIPT" 2>/dev/null) || RC=$?
assert_exit "terminal tester phase exits 1" 1 "$RC"
assert_contains "zombie message" "ZOMBIE" "$OUTPUT10"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
