#!/bin/bash
# verify-phase-transition.sh - Verifies preconditions before phase transitions
# Prevents advancing to the next phase when contracts, gates, or verdicts
# are missing or malformed. Follows "linter-as-teacher" pattern: errors
# explain WHAT failed, WHY it matters, and HOW to fix it.
#
# Usage: bash scripts/verify-phase-transition.sh <from_phase> <to_phase>
#
# Supported transitions:
# architect execute  -- contracts and gate scripts are ready
# execute integrate  -- all increments passed with approved verdicts
# integrate deliver  -- integration verdict is APPROVED or PASS
#
# Output:
# .superteam/phase-transition-results.json
#
# Exit codes:
# 0 = all checks passed, transition is safe
# 1 = one or more checks failed, transition blocked
# 2 = usage error (bad arguments, unknown transition)

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 2 ]; then
  cat <<'USAGE'
Usage: bash scripts/verify-phase-transition.sh <from_phase> <to_phase>

Supported transitions:
  architect execute  - verify contracts and gate scripts are ready
  execute integrate  - verify all increments passed with approved verdicts
  integrate deliver  - verify integration verdict is APPROVED or PASS

Results written to .superteam/phase-transition-results.json

Exit codes:
  0 = all checks passed
  1 = one or more checks failed
  2 = usage error
USAGE
  exit 2
fi

FROM_PHASE="$1"
TO_PHASE="$2"

SUPERTEAM_DIR=".superteam"
PLAN_FILE="$SUPERTEAM_DIR/plan.md"
RESULTS_FILE="$SUPERTEAM_DIR/phase-transition-results.json"

# ---------------------------------------------------------------------------
# Helpers (shared library)
# ---------------------------------------------------------------------------

_VPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_VPT_DIR/lib.sh"

# Accumulators for check results
CHECKS_JSON="[]"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Record a check result. Arguments: <status> <check_description> <detail>
record_check() {
  local status="$1" check="$2" detail="$3"
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ "$status" = "pass" ]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  else
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi

  # Escape strings for JSON via python3
  local json_entry
  json_entry=$(python3 -c "
import json, sys
print(json.dumps({
  'check': sys.argv[1],
  'status': sys.argv[2],
  'detail': sys.argv[3]
}))
" "$check" "$status" "$detail")

  # Print each check as it runs
  if [ "$status" = "pass" ]; then
    echo "  [PASS] $check"
  else
    echo "  [FAIL] $check"
    echo "$detail"
  fi

  if [ "$CHECKS_JSON" = "[]" ]; then
    CHECKS_JSON="[$json_entry]"
  else
    CHECKS_JSON="${CHECKS_JSON%]},$json_entry]"
  fi
}

# Write the final results JSON and exit with appropriate code
write_results_and_exit() {
  local transition="${FROM_PHASE}-${TO_PHASE}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local all_passed="true"
  [ "$FAILED_CHECKS" -gt 0 ] && all_passed="false"

  mkdir -p "$(dirname "$RESULTS_FILE")"

  python3 -c "
import json, sys

results = {
  'transition': sys.argv[1],
  'timestamp': sys.argv[2],
  'passed': sys.argv[3] == 'true',
  'total_checks': int(sys.argv[4]),
  'passed_checks': int(sys.argv[5]),
  'failed_checks': int(sys.argv[6]),
  'checks': json.loads(sys.argv[7])
}
with open(sys.argv[8], 'w') as f:
  json.dump(results, f, indent=2)
" "$transition" "$timestamp" "$all_passed" "$TOTAL_CHECKS" "$PASSED_CHECKS" "$FAILED_CHECKS" "$CHECKS_JSON" "$RESULTS_FILE"

  echo ""
  echo "=============================="
  if [ "$FAILED_CHECKS" -gt 0 ]; then
    echo "TRANSITION $transition: BLOCKED ($FAILED_CHECKS/$TOTAL_CHECKS checks failed)"
  else
    echo "TRANSITION $transition: CLEAR (all $TOTAL_CHECKS checks passed)"
  fi
  echo "=============================="
  echo "Results written to: $RESULTS_FILE"

  if [ "$FAILED_CHECKS" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# ---------------------------------------------------------------------------
# Transition: architect -> execute
# ---------------------------------------------------------------------------

verify_architect_execute() {
  echo "--- Verifying transition: architect -> execute ---"

  # 1. Parse total_increments from plan.md
  if [ ! -f "$PLAN_FILE" ]; then
    record_check "fail" "plan.md exists" \
      "WHAT: $PLAN_FILE does not exist. WHY: The plan defines the increment structure needed for execution. HOW: Run the architect phase first to generate the plan."
    write_results_and_exit
  fi

  local total_increments
  total_increments=$(parse_yaml_field "$PLAN_FILE" "total_increments")

  if [ -z "$total_increments" ] || ! [[ "$total_increments" =~ ^[0-9]+$ ]] || [ "$total_increments" -lt 1 ]; then
    record_check "fail" "plan.md has valid total_increments" \
      "WHAT: total_increments field is missing or invalid (got: '${total_increments:-<empty>}'). WHY: Without knowing the number of increments, execution cannot proceed. HOW: Ensure plan.md frontmatter contains 'total_increments: N' where N >= 1."
    write_results_and_exit
  fi

  record_check "pass" "plan.md has valid total_increments" \
    "Found total_increments: $total_increments"

  # 2. For each increment 1..N, verify contract and scripts
  local n
  for n in $(seq 1 "$total_increments"); do
    local contract="$SUPERTEAM_DIR/contracts/increment-${n}.md"
    local scripts_dir="$SUPERTEAM_DIR/scripts/increment-${n}"

    # 2a. Contract exists
    if [ ! -f "$contract" ]; then
      record_check "fail" "increment-${n} contract exists" \
        "WHAT: $contract does not exist. WHY: Each increment needs a frozen contract before execution. HOW: Run the architect phase to generate contracts."
      continue
    fi

    # 2b. Contract has status: frozen
    local contract_status
    contract_status=$(parse_yaml_field "$contract" "status")
    if [ "$contract_status" != "frozen" ]; then
      record_check "fail" "increment-${n} contract is frozen" \
        "WHAT: Contract status is '${contract_status:-<empty>}', expected 'frozen'. WHY: Only frozen contracts are safe to execute against - they guarantee the scope will not change mid-execution. HOW: Set 'status: frozen' in $contract frontmatter after architect review."
    else
      record_check "pass" "increment-${n} contract is frozen" \
        "Contract $contract has status: frozen"
    fi

    # 2c. Scripts directory exists
    if [ ! -d "$scripts_dir" ]; then
      record_check "fail" "increment-${n} scripts directory exists" \
        "WHAT: $scripts_dir does not exist. WHY: Gate scripts enforce quality checks for each increment. HOW: The architect phase should create this directory with at least one gate-*.sh script."
      continue
    fi

    # 2d. At least one gate script
    local gate_count
    gate_count=$(find "$scripts_dir" -maxdepth 1 -name 'gate-*.sh' -type f 2>/dev/null | wc -l)
    if [ "$gate_count" -lt 1 ]; then
      record_check "fail" "increment-${n} has gate scripts" \
        "WHAT: No gate-*.sh files found in $scripts_dir. WHY: Hard gates are the deterministic quality checks that verify each increment's deliverables. HOW: Create at least one gate script (e.g., gate-compile.sh, gate-tests.sh) in $scripts_dir."
    else
      record_check "pass" "increment-${n} has gate scripts" \
        "Found $gate_count gate script(s) in $scripts_dir"
    fi

    # 2e. Each gate script is non-empty with valid shebang
    for gate_script in "$scripts_dir"/gate-*.sh; do
      [ -f "$gate_script" ] || continue
      local gate_name
      gate_name=$(basename "$gate_script")

      if [ ! -s "$gate_script" ]; then
        record_check "fail" "increment-${n}/${gate_name} is non-empty" \
          "WHAT: $gate_script is empty (0 bytes). WHY: An empty gate script will pass trivially, defeating the purpose of hard gates. HOW: Add the test logic to $gate_script - it should exit 0 on pass, non-zero on fail."
        continue
      fi

      local first_line
      first_line=$(head -1 "$gate_script")
      if ! echo "$first_line" | grep -qE '^#!.*(bash|sh|python|node|env )'; then
        record_check "fail" "increment-${n}/${gate_name} has valid shebang" \
          "WHAT: First line is '${first_line}', not a recognized shebang. WHY: Without a shebang, the script may be executed by the wrong interpreter and produce misleading results. HOW: Add '#!/bin/bash' (or appropriate shebang) as the first line of $gate_script."
      else
        record_check "pass" "increment-${n}/${gate_name} has valid shebang" \
          "Valid shebang: $first_line"
      fi
    done
  done

  # 3. Verify final gate scripts directory
  local final_dir="$SUPERTEAM_DIR/scripts/final"
  if [ ! -d "$final_dir" ]; then
    record_check "fail" "final scripts directory exists" \
      "WHAT: $final_dir does not exist. WHY: Final gate scripts run after all increments to verify integration. HOW: Create $final_dir with at least one gate-*.sh script."
  else
    local final_gate_count
    final_gate_count=$(find "$final_dir" -maxdepth 1 -name 'gate-*.sh' -type f 2>/dev/null | wc -l)
    if [ "$final_gate_count" -lt 1 ]; then
      record_check "fail" "final directory has gate scripts" \
        "WHAT: No gate-*.sh files found in $final_dir. WHY: Final gates verify the fully integrated result - without them, integration quality is unchecked. HOW: Create at least one gate script (e.g., gate-integration.sh) in $final_dir."
    else
      record_check "pass" "final directory has gate scripts" \
        "Found $final_gate_count gate script(s) in $final_dir"
    fi
  fi

  write_results_and_exit
}

# ---------------------------------------------------------------------------
# Transition: execute -> integrate
# ---------------------------------------------------------------------------

verify_execute_integrate() {
  echo "--- Verifying transition: execute -> integrate ---"

  # 1. Parse total_increments from plan.md
  if [ ! -f "$PLAN_FILE" ]; then
    record_check "fail" "plan.md exists" \
      "WHAT: $PLAN_FILE does not exist. WHY: Cannot determine how many increments to verify without the plan. HOW: This file should have been created during the architect phase."
    write_results_and_exit
  fi

  local total_increments
  total_increments=$(parse_yaml_field "$PLAN_FILE" "total_increments")

  if [ -z "$total_increments" ] || ! [[ "$total_increments" =~ ^[0-9]+$ ]] || [ "$total_increments" -lt 1 ]; then
    record_check "fail" "plan.md has valid total_increments" \
      "WHAT: total_increments field is missing or invalid (got: '${total_increments:-<empty>}'). WHY: Cannot verify execution results without knowing the expected increment count. HOW: Ensure plan.md frontmatter contains 'total_increments: N' where N >= 1."
    write_results_and_exit
  fi

  record_check "pass" "plan.md has valid total_increments" \
    "Found total_increments: $total_increments"

  # 2. For each increment, verify verdict and gate results
  local n
  for n in $(seq 1 "$total_increments"); do
    local verdict_file="$SUPERTEAM_DIR/verdicts/increment-${n}.md"
    local gate_results="$SUPERTEAM_DIR/gate-results/increment-${n}.json"

    # 2a. Verdict file exists
    if [ ! -f "$verdict_file" ]; then
      record_check "fail" "increment-${n} verdict exists" \
        "WHAT: $verdict_file does not exist. WHY: Each increment must be evaluated and approved before integration. HOW: Run the evaluator for increment $n."
      continue
    fi

    # 2b. Verdict is APPROVED
    local verdict
    verdict=$(parse_yaml_field "$verdict_file" "verdict")
    if [ "$verdict" != "APPROVED" ]; then
      record_check "fail" "increment-${n} verdict is APPROVED" \
        "WHAT: Verdict is '${verdict:-<empty>}', expected 'APPROVED'. WHY: Only approved increments should be integrated - unapproved code may have known defects. HOW: Address evaluator feedback and re-run until verdict is APPROVED."
    else
      record_check "pass" "increment-${n} verdict is APPROVED" \
        "Increment ${n} approved"
    fi

    # 2c. Gate results file exists
    if [ ! -f "$gate_results" ]; then
      record_check "fail" "increment-${n} gate results exist" \
        "WHAT: $gate_results does not exist. WHY: Gate results provide the deterministic evidence that hard checks passed. HOW: Run 'bash scripts/run-gates.sh ${n}' to generate gate results."
    else
      record_check "pass" "increment-${n} gate results exist" \
        "Gate results present at $gate_results"
    fi
  done

  write_results_and_exit
}

# ---------------------------------------------------------------------------
# Transition: integrate -> deliver
# ---------------------------------------------------------------------------

verify_integrate_deliver() {
  echo "--- Verifying transition: integrate -> deliver ---"

  local verdicts_dir="$SUPERTEAM_DIR/verdicts"

  # 1. Find integration verdict file
  if [ ! -d "$verdicts_dir" ]; then
    record_check "fail" "verdicts directory exists" \
      "WHAT: $verdicts_dir does not exist. WHY: Integration verdicts live in this directory. HOW: Run the integration evaluation phase first."
    write_results_and_exit
  fi

  local verdict_file=""
  for candidate in "$verdicts_dir"/*integration*.md "$verdicts_dir"/*final*.md; do
    if [ -f "$candidate" ]; then
      # Exclude plan-evaluation.md - it's not an integration verdict
      local basename_candidate
      basename_candidate=$(basename "$candidate")
      if [ "$basename_candidate" = "plan-evaluation.md" ]; then
        continue
      fi
      verdict_file="$candidate"
      break
    fi
  done

  if [ -z "$verdict_file" ]; then
    record_check "fail" "integration verdict file exists" \
      "WHAT: No file matching '*integration*.md' or '*final*.md' found in $verdicts_dir. WHY: The integration verdict confirms the fully assembled system is ready for delivery. HOW: Run the integration evaluator to produce a verdict file (e.g., verdicts/integration-verdict.md or verdicts/final-verdict.md)."
    write_results_and_exit
  fi

  record_check "pass" "integration verdict file exists" \
    "Found verdict file: $verdict_file"

  # 2. Parse verdict field
  local verdict
  verdict=$(parse_yaml_field "$verdict_file" "verdict")

  if [ -z "$verdict" ]; then
    record_check "fail" "integration verdict field is present" \
      "WHAT: No 'verdict:' field found in $verdict_file frontmatter. WHY: The verdict field is the authoritative decision on whether integration passed. HOW: Ensure the integration evaluator writes 'verdict: APPROVED' (or REVISE) in the YAML frontmatter."
    write_results_and_exit
  fi

  # 3. Check verdict value
  case "$verdict" in
    APPROVED|PASS)
      record_check "pass" "integration verdict is APPROVED or PASS" \
        "Integration approved - safe to deliver (verdict: $verdict)"
      ;;
    REVISE|FAIL)
      record_check "fail" "integration verdict is APPROVED or PASS" \
        "WHAT: Integration verdict is '${verdict}'. WHY: The evaluator found issues that must be addressed before delivery. HOW: Read the feedback in $verdict_file, fix the issues, re-run integration evaluation, and retry this transition."
      ;;
    GATE-CHALLENGE)
      record_check "fail" "integration verdict is APPROVED or PASS" \
        "WHAT: Integration verdict is 'GATE-CHALLENGE'. WHY: The evaluator is challenging one or more gate definitions rather than the code itself. HOW: Review the gate challenge in $verdict_file, update the disputed gate scripts if appropriate, then re-run integration evaluation."
      ;;
    *)
      record_check "fail" "integration verdict is APPROVED or PASS" \
        "INVALID VERDICT: '${verdict}' is not a recognized value. WHY: Only 'APPROVED' or 'PASS' permits delivery. Valid values are APPROVED, PASS, REVISE, FAIL, or GATE-CHALLENGE. HOW: Fix the verdict field in $verdict_file to a valid value and re-run integration evaluation."
      ;;
  esac

  write_results_and_exit
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${FROM_PHASE}-${TO_PHASE}" in
  architect-execute)
    verify_architect_execute
    ;;
  execute-integrate)
    verify_execute_integrate
    ;;
  integrate-deliver)
    verify_integrate_deliver
    ;;
  *)
    echo "ERROR: Unknown transition '${FROM_PHASE} -> ${TO_PHASE}'"
    echo ""
    echo "Supported transitions:"
    echo "  architect execute  - verify contracts and gate scripts"
    echo "  execute integrate  - verify verdicts and gate results"
    echo "  integrate deliver  - verify integration verdict"
    exit 2
    ;;
esac
