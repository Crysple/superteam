#!/bin/bash
# verdict-gate.sh - PreToolUse hook for Write/Edit tools
# BLOCKS verdict file writes unless corresponding gate-results JSON exists.
# Prevents LLM-only verdicts: every verdict must be backed by actual test data.

set -euo pipefail

SUPERTEAM_DIR=".superteam"
GATE_RESULTS_DIR="$SUPERTEAM_DIR/gate-results"
VERDICTS_DIR="$SUPERTEAM_DIR/verdicts"

# Read tool input from stdin (Claude Code passes tool call JSON on stdin)
TOOL_INPUT=$(cat 2>/dev/null || true)

# Empty stdin or missing file_path - never block on hook errors
if [ -z "$TOOL_INPUT" ]; then exit 0; fi

FILE_PATH=$(echo "$TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || true)
if [ -z "$FILE_PATH" ]; then exit 0; fi

# Fast path: not a verdict write
if ! echo "$FILE_PATH" | grep -q "$VERDICTS_DIR/" 2>/dev/null; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Slow path: verdict write - enforce gate-results requirement
# ---------------------------------------------------------------------------

FILENAME=$(basename "$FILE_PATH")
GATES_ARG=""  # argument to pass to run-gates.sh
GATE_FILE=""  # expected gate-results JSON path
DISPLAY_ID="" # human-readable label for error messages

case "$FILENAME" in
  plan-evaluation.md|draft-*)
    # Plan evaluations and drafts don't need gate-results
    exit 0
    ;;
  increment-*.md)
    INCREMENT=$(echo "$FILENAME" | sed 's/^increment-\([0-9]*\)\.md$/\1/')
    GATES_ARG="$INCREMENT"
    GATE_FILE="$GATE_RESULTS_DIR/increment-${INCREMENT}.json"
    DISPLAY_ID="increment $INCREMENT"
    ;;
  version-*.md)
    # Skill-dev form: version-based work units
    # run-gates.sh accepts "version-N" and writes gate-results/version-N.json
    INCREMENT=$(echo "$FILENAME" | sed 's/^version-\([0-9]*\)\.md$/\1/')
    GATES_ARG="version-${INCREMENT}"
    GATE_FILE="$GATE_RESULTS_DIR/version-${INCREMENT}.json"
    DISPLAY_ID="version $INCREMENT"
    ;;
  final-integration.md|integration*.md)
    GATES_ARG="final"
    GATE_FILE="$GATE_RESULTS_DIR/final-integration.json"
    DISPLAY_ID="final integration"
    ;;
  *strict-evaluation*.md)
    GATES_ARG="final"
    GATE_FILE="$GATE_RESULTS_DIR/final-integration.json"
    DISPLAY_ID="strict evaluation"
    ;;
  *)
    # Unknown verdict filename - allow through to avoid false blocks
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Validate: exists, non-empty, contains "gates" key
# ---------------------------------------------------------------------------

block_verdict() {
  local reason="$1"
  echo ""
  echo "=============================="
  echo "VERDICT BLOCKED: ${reason} for ${DISPLAY_ID}."
  echo "You must run: bash scripts/run-gates.sh ${GATES_ARG}"
  echo "If scripts dir missing (exit 2), this is a GATE-CHALLENGE. Message TL."
  echo "DO NOT write verdicts based on LLM reasoning alone."
  echo "=============================="
  exit 1
}

if [ ! -f "$GATE_FILE" ]; then
  block_verdict "Gate results file missing"
fi

if [ ! -s "$GATE_FILE" ]; then
  block_verdict "Gate results file is empty"
fi

if ! grep -q '"gates"' "$GATE_FILE" 2>/dev/null; then
  block_verdict 'Gate results file is malformed (missing "gates" key)'
fi

# Gate-results validated - allow the verdict write
exit 0
