#!/bin/bash
# run-gates.sh - Deterministic hard gate runner
# Runs all hard gate scripts for a given increment and writes structured
# JSON results to .superteam/gate-results/increment-N.json.
#
# Usage: bash scripts/run-gates.sh <increment-number>
#
# Design principle: "Deterministic > Agentic" - don't LLM what should be
# mechanical. This script runs all gate scripts and reports results;
# agents read the JSON output instead of running scripts individually
# through LLM reasoning.
#
# Exit codes:
# 0 = all gates passed
# 1 = one or more gates failed
# 2 = usage error or missing files

set -euo pipefail

# ---------------------------------------------------------------------------
# Export REPO_ROOT for child gate scripts
# ---------------------------------------------------------------------------
# Gate scripts resolve their REPO_ROOT via:
# REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# That fallback is wrong when a gate is invoked via its hardlinked path at
# .superteam/scripts/increment-N/ - $SCRIPT_DIR/../.. resolves to
# .superteam/, not the true repo root, and primitives like
# scripts/record-event.sh are not found.
#
# Exporting REPO_ROOT from the invoker's cwd bypasses the fallback entirely:
# every child process sees the correct repo root regardless of which hardlink
# path it was invoked through.
export REPO_ROOT="${REPO_ROOT:-$(pwd)}"

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/run-gates.sh <increment-number>"
  echo "  Runs all hard gate scripts for the given increment."
  echo "  Results written to .superteam/gate-results/increment-N.json"
  exit 2
fi

INCREMENT="$1"
SUPERTEAM_DIR=".superteam"
RESULTS_DIR="$SUPERTEAM_DIR/gate-results"

# Handle "final" and "version-N" as special cases
if [ "$INCREMENT" = "final" ]; then
  SCRIPTS_DIR="$SUPERTEAM_DIR/scripts/final"
  RESULTS_FILE="$RESULTS_DIR/final-integration.json"
elif echo "$INCREMENT" | grep -q '^version-'; then
  # Skill-dev form: version-based work units (e.g., "version-1")
  SCRIPTS_DIR="$SUPERTEAM_DIR/scripts/${INCREMENT}"
  RESULTS_FILE="$RESULTS_DIR/${INCREMENT}.json"
else
  SCRIPTS_DIR="$SUPERTEAM_DIR/scripts/increment-${INCREMENT}"
  RESULTS_FILE="$RESULTS_DIR/increment-${INCREMENT}.json"
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

if [ ! -d "$SCRIPTS_DIR" ]; then
  echo "ERROR: No scripts directory for increment $INCREMENT at $SCRIPTS_DIR"
  echo ""
  echo "This likely means gate scripts were never created for this increment."
  echo "The Architect must create $SCRIPTS_DIR with at least one gate-*.sh script"
  echo "before execution can proceed."
  echo ""
  echo "If you are an Evaluator: issue a GATE-CHALLENGE verdict and escalate to"
  echo "the Architect via TL. Do NOT ask the Generator to create gate scripts."
  echo ""
  echo "If you are a Generator: STOP. Do NOT proceed with implementation."
  echo "Message TL immediately - this is a planning error, not an implementation task."
  exit 2
fi

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Read gate-inputs.json (if present)
# ---------------------------------------------------------------------------

GATE_INPUTS_FILE="$SUPERTEAM_DIR/gate-inputs.json"
GATE_INPUTS_EXISTS="false"
if [ -f "$GATE_INPUTS_FILE" ]; then
  GATE_INPUTS_EXISTS="true"
  echo "Found gate-inputs.json at $GATE_INPUTS_FILE"
fi

# ---------------------------------------------------------------------------
# Helper: parse REQUIRES and CATEGORY headers from a gate script
# ---------------------------------------------------------------------------

parse_requires() {
  # Extract REQUIRES: line - format: # REQUIRES: arg1 arg2 arg3
  local script="$1"
  grep -m1 '^# REQUIRES:' "$script" 2>/dev/null | sed 's/^# REQUIRES: [[:space:]]*//' || true
}

parse_category() {
  # Extract CATEGORY: line - format: # CATEGORY: static|execution-evidence
  local script="$1"
  grep -m1 '^# CATEGORY:' "$script" 2>/dev/null | sed 's/^# CATEGORY: [[:space:]]*//' || true
}

lookup_gate_input() {
  # Look up a key in gate-inputs.json, return value or empty string
  local key="$1"
  python3 -c "import json,sys; d = json.load(open('$GATE_INPUTS_FILE')); print(d.get('$key', ''))" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Run all gate scripts
# ---------------------------------------------------------------------------

TOTAL=0
PASSED=0
FAILED=0
RESULTS="[]"

for script in "$SCRIPTS_DIR"/gate-*.sh "$SCRIPTS_DIR"/preconditions.sh; do
  [ -f "$script" ] || continue

  SCRIPT_NAME=$(basename "$script")
  TOTAL=$((TOTAL + 1))

  echo "--- Running: $SCRIPT_NAME ---"

  # Parse REQUIRES and CATEGORY headers
  REQUIRES=$(parse_requires "$script")
  CATEGORY=$(parse_category "$script")

  # Warn if Category B gate has no REQUIRES line
  if [ "$CATEGORY" = "execution-evidence" ] && [ -z "$REQUIRES" ]; then
    echo "  WARNING: Category B gate has no REQUIRES - likely a gate authoring error."
  fi

  # If gate has REQUIRES, resolve arguments from gate-inputs.json
  GATE_ARGS=()
  SKIP_GATE="false"
  SKIP_REASON=""
  if [ -n "$REQUIRES" ]; then
    if [ "$GATE_INPUTS_EXISTS" = "false" ]; then
      # No gate-inputs.json - fail all required keys
      FIRST_KEY=$(echo "$REQUIRES" | awk '{print $1}')
      SKIP_GATE="true"
      SKIP_REASON="gate-inputs.json does not exist; $SCRIPT_NAME requires '$FIRST_KEY'"
    else
      for key in $REQUIRES; do
        VALUE=$(lookup_gate_input "$key")
        if [ -z "$VALUE" ]; then
          SKIP_GATE="true"
          SKIP_REASON="$SCRIPT_NAME requires '$key' but gate-inputs.json does not provide it"
          break
        fi
        GATE_ARGS+=("$VALUE")
      done
    fi
  fi

  if [ "$SKIP_GATE" = "true" ]; then
    # Record as FAIL without running the gate
    STATUS="fail"
    FAILED=$((FAILED + 1))
    OUTPUT="$SKIP_REASON"
    EXIT_CODE=1
    DURATION_MS=0
    echo "  FAILED (missing input: $SKIP_REASON)"
  else
    START_MS=$(date +%s%3N 2>/dev/null | grep -E '^[0-9]+$' || echo "$(date +%s)000")
    OUTPUT=""
    EXIT_CODE=0
    OUTPUT=$(bash "$script" "${GATE_ARGS[@]+"${GATE_ARGS[@]}"}" 2>&1) || EXIT_CODE=$?
    END_MS=$(date +%s%3N 2>/dev/null | grep -E '^[0-9]+$' || echo "$(date +%s)000")
    DURATION_MS=$((END_MS - START_MS))

    if [ "$EXIT_CODE" -eq 0 ]; then
      STATUS="pass"
      PASSED=$((PASSED + 1))
      echo "  PASSED ($DURATION_MS ms)"
    else
      STATUS="fail"
      FAILED=$((FAILED + 1))
      echo "  FAILED (exit $EXIT_CODE, $DURATION_MS ms)"
    fi
  fi

  # Escape output for JSON
  ESCAPED_OUTPUT=$(printf '%s' "$OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '"(output encoding failed)"')

  # Build JSON entry
  ENTRY=$(cat <<JSONEOF
{"script": "$SCRIPT_NAME", "status": "$STATUS", "exit_code": $EXIT_CODE, "duration_ms": $DURATION_MS, "output": $ESCAPED_OUTPUT}
JSONEOF
)

  # Append to results array
  if [ "$RESULTS" = "[]" ]; then
    RESULTS="[$ENTRY]"
  else
    RESULTS="${RESULTS%]}, $ENTRY]"
  fi
done

# ---------------------------------------------------------------------------
# Write results JSON
# ---------------------------------------------------------------------------

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ALL_PASSED="true"
[ "$FAILED" -gt 0 ] && ALL_PASSED="false"

cat > "$RESULTS_FILE" <<JSONEOF
{
  "increment": "$INCREMENT",
  "timestamp": "$TIMESTAMP",
  "all_passed": $ALL_PASSED,
  "total": $TOTAL,
  "passed": $PASSED,
  "failed": $FAILED,
  "gates": $RESULTS
}
JSONEOF

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=============================="
if [ "$FAILED" -gt 0 ]; then
  echo "GATE RESULTS: $FAILED/$TOTAL FAILED - all_passed: false"
  echo "EVALUATOR RULE: all_passed=false means your verdict is FAIL."
  echo "You may not reclassify, reinterpret, or invent categories."
else
  echo "GATE RESULTS: ALL $TOTAL PASSED - all_passed: true"
fi
echo "=============================="
echo "Results written to: $RESULTS_FILE"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
