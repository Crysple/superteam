#!/bin/bash
# verify-contract-fidelity.sh - Structural fidelity checks between spec and contract
# Detects weakening patterns where a contract's hard gates diverge from
# the spec's requirements (e.g., accepting FAILED where spec requires SUCCEEDED).
#
# Usage:
# bash scripts/verify-contract-fidelity.sh <increment_number>
# bash scripts/verify-contract-fidelity.sh coverage
#
# Modes:
# <number>  -- Check fidelity for a single increment
# coverage  -- Check that every spec hard gate is covered by at least one contract
#
# Reads:
# .superteam/spec.md                       - source-of-truth spec with HG- gates
# .superteam/contracts/increment-{N}.md   - contract for the increment
#
# Writes:
# .superteam/gate-results/fidelity-{N}.json      - per-increment fidelity results
# .superteam/gate-results/spec-coverage.json     - spec coverage results (coverage mode)
#
# Exit codes:
# 0 = no fidelity issues found / full coverage
# 1 = fidelity issues detected / coverage gaps
# 2 = usage error or missing files

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/verify-contract-fidelity.sh <increment_number|coverage>"
  echo "  <number>  -- Check contract hard gates against spec for weakening patterns."
  echo "  coverage  -- Check that every spec hard gate is covered by at least one contract."
  exit 2
fi

SUPERTEAM_DIR=".superteam"
SPEC_FILE="$SUPERTEAM_DIR/spec.md"
RESULTS_DIR="$SUPERTEAM_DIR/gate-results"

if [ ! -f "$SPEC_FILE" ]; then
  echo "ERROR: Spec file not found at $SPEC_FILE"
  exit 2
fi

mkdir -p "$RESULTS_DIR"

# ---------------------------------------------------------------------------
# Coverage mode: check all contracts cover all spec gates
# ---------------------------------------------------------------------------

if [ "$1" = "coverage" ]; then
  CONTRACTS_DIR="$SUPERTEAM_DIR/contracts"
  COVERAGE_FILE="$RESULTS_DIR/spec-coverage.json"

  if [ ! -d "$CONTRACTS_DIR" ]; then
    echo "ERROR: Contracts directory not found at $CONTRACTS_DIR"
    exit 2
  fi

  python3 - "$SPEC_FILE" "$CONTRACTS_DIR" "$COVERAGE_FILE" <<'COVERAGEPY'
import sys
import json
import re
import os
from datetime import datetime, timezone

spec_path = sys.argv[1]
contracts_dir = sys.argv[2]
coverage_path = sys.argv[3]

hg_pattern = re.compile(r"(HG-[\w.]+)")

# Extract all HG- gates from spec
with open(spec_path, "r") as f:
    spec_lines = f.readlines()

spec_gates = {}
for i, line in enumerate(spec_lines, 1):
    m = hg_pattern.search(line)
    if m:
        spec_gates[m.group(1)] = {"line": i, "text": line.strip()}

# Scan all contracts for HG- references
contract_gates = {}  # gate_id -> list of increments that reference it
contract_files = sorted(
    f for f in os.listdir(contracts_dir)
    if f.startswith("increment-") and f.endswith(".md")
)

for cf in contract_files:
    inc_match = re.search(r"increment-(\d+)", cf)
    if not inc_match:
        continue
    inc_num = int(inc_match.group(1))
    with open(os.path.join(contracts_dir, cf), "r") as f:
        for line in f:
            m = hg_pattern.search(line)
            if m:
                gate_id = m.group(1)
                if gate_id not in contract_gates:
                    contract_gates[gate_id] = []
                contract_gates[gate_id].append(inc_num)

# Check coverage
uncovered = []
covered = []
for gate_id, info in sorted(spec_gates.items()):
    if gate_id in contract_gates:
        covered.append({
            "gate": gate_id,
            "spec_line": info["line"],
            "covered_by_increments": contract_gates[gate_id]
        })
    else:
        uncovered.append({
            "gate": gate_id,
            "spec_line": info["line"],
            "spec_text": info["text"]
        })

passed = len(uncovered) == 0
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

result = {
    "timestamp": timestamp,
    "spec_gates_total": len(spec_gates),
    "covered": len(covered),
    "uncovered": len(uncovered),
    "passed": passed,
    "covered_gates": covered,
    "uncovered_gates": uncovered
}

with open(coverage_path, "w") as f:
    json.dump(result, f, indent=2)

print("========================")
print("SPEC COVERAGE CHECK")
print("========================")
print(f"Spec hard gates: {len(spec_gates)}")
print(f"Covered: {len(covered)}")
print(f"Uncovered: {len(uncovered)}")
print()

if uncovered:
    for u in uncovered:
        print(f"  UNCOVERED: {u['gate']} (spec.md:{u['spec_line']})")
        print(f"  {u['spec_text']}")
        print()
    print("RESULT: COVERAGE GAPS DETECTED")
else:
    print("RESULT: ALL SPEC GATES COVERED")

print(f"Results written to: {coverage_path}")
sys.exit(0 if passed else 1)
COVERAGEPY
  exit $?
fi

# ---------------------------------------------------------------------------
# Per-increment fidelity mode
# ---------------------------------------------------------------------------

INCREMENT="$1"
CONTRACT_FILE="$SUPERTEAM_DIR/contracts/increment-${INCREMENT}.md"
RESULTS_FILE="$RESULTS_DIR/fidelity-${INCREMENT}.json"

if [ ! -f "$CONTRACT_FILE" ]; then
  echo "ERROR: Contract file not found at $CONTRACT_FILE"
  exit 2
fi

# ---------------------------------------------------------------------------
# Extract hard gate lines
# ---------------------------------------------------------------------------

SPEC_GATES_TMP=$(mktemp)
CONTRACT_GATES_TMP=$(mktemp)
trap 'rm -f "$SPEC_GATES_TMP" "$CONTRACT_GATES_TMP"' EXIT

grep "HG-" "$SPEC_FILE" > "$SPEC_GATES_TMP" || true
grep "HG-" "$CONTRACT_FILE" > "$CONTRACT_GATES_TMP" || true

SPEC_GATE_COUNT=$(wc -l < "$SPEC_GATES_TMP" | xargs)
CONTRACT_GATE_COUNT=$(wc -l < "$CONTRACT_GATES_TMP" | xargs)

# ---------------------------------------------------------------------------
# Detect weakening patterns via python3
# ---------------------------------------------------------------------------

python3 - "$INCREMENT" "$SPEC_GATES_TMP" "$CONTRACT_GATES_TMP" "$SPEC_GATE_COUNT" "$CONTRACT_GATE_COUNT" "$RESULTS_FILE" <<'PYEOF'
import sys
import json
import re
from datetime import datetime, timezone

increment = int(sys.argv[1])
spec_gates_path = sys.argv[2]
contract_gates_path = sys.argv[3]
spec_gate_count = int(sys.argv[4])
contract_gate_count = int(sys.argv[5])
results_path = sys.argv[6]

with open(spec_gates_path, "r") as f:
    spec_lines = f.readlines()

with open(contract_gates_path, "r") as f:
    contract_lines = f.readlines()

# Build lookup: HG-id -> full line text (from spec)
hg_pattern = re.compile(r"(HG-[\w.]+)")

spec_gates = {}
for line in spec_lines:
    m = hg_pattern.search(line)
    if m:
        spec_gates[m.group(1)] = line.strip()

contract_gates = {}
for line in contract_lines:
    m = hg_pattern.search(line)
    if m:
        contract_gates[m.group(1)] = line.strip()

issues = []

# Check 1: Contract contains FAILED/ABORTED/TIMED_OUT where spec requires SUCCEEDED
failure_statuses = re.compile(r'\b(FAILED|ABORTED|TIMED_OUT)\b')
succeeded_pattern = re.compile(r'\bSUCCEEDED\b')

for gate_id, contract_text in contract_gates.items():
    spec_text = spec_gates.get(gate_id, "")

    # CRITICAL: spec says SUCCEEDED but contract allows a failure status
    if spec_text and succeeded_pattern.search(spec_text) and failure_statuses.search(contract_text):
        match = failure_statuses.search(contract_text)
        issues.append({
            "severity": "CRITICAL",
            "contract_gate": gate_id,
            "spec_gate": gate_id,
            "issue": "WEAKENED",
            "detail": f"Contract allows {match.group()} where spec requires SUCCEEDED"
        })

    # WARNING: Contract uses "ANY" or "any" in pass criteria
    if re.search(r'\bANY\b|\bany\b', contract_text):
        issues.append({
            "severity": "WARNING",
            "contract_gate": gate_id,
            "spec_gate": gate_id,
            "issue": "OVERLY_BROAD",
            "detail": f"Contract uses 'any' in pass criteria: {contract_text[:80]}"
        })

    # WARNING: Contract adds OR/escape clauses not in spec
    or_pattern = re.compile(r'\bOR\b|\bor\b(?!\w)')
    contract_or_matches = set(m.start() for m in or_pattern.finditer(contract_text))
    spec_or_matches = set(m.start() for m in or_pattern.finditer(spec_text)) if spec_text else set()
    if contract_or_matches and (not spec_text or len(contract_or_matches) > len(spec_or_matches)):
        issues.append({
            "severity": "WARNING",
            "contract_gate": gate_id,
            "spec_gate": gate_id,
            "issue": "ESCAPE_CLAUSE",
            "detail": "Contract adds OR/escape clauses not present in spec"
        })

passed = len(issues) == 0
timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

result = {
    "increment": increment,
    "timestamp": timestamp,
    "spec_gates_found": spec_gate_count,
    "contract_gates_found": contract_gate_count,
    "issues": issues,
    "passed": passed
}

with open(results_path, "w") as f:
    json.dump(result, f, indent=2)

# Human-readable summary
print("=" * 50)
print(f"CONTRACT FIDELITY CHECK - Increment {increment}")
print("=" * 50)
print(f"Spec gates found: {spec_gate_count}")
print(f"Contract gates found: {contract_gate_count}")
print(f"Issues found: {len(issues)}")
print()

if issues:
    for i, issue in enumerate(issues, 1):
        print(f"  {i}. [{issue['severity']}] {issue['contract_gate']}: {issue['issue']}")
        print(f"     {issue['detail']}")
        print()
    print("RESULT: FIDELITY ISSUES DETECTED")
else:
    print("RESULT: ALL GATES FAITHFUL TO SPEC")

print(f"Results written to: {results_path}")

sys.exit(0 if passed else 1)
PYEOF
