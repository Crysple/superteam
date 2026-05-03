#!/bin/bash
# init-session.sh - Deterministic session initialization
# Creates all directories, writes template state files, detects validation
# commands, resolves the global-guide template, and runs the startup
# self-test. Replaces ~170 lines of deterministic init work previously
# done inline by the TL agent.
#
# Usage: bash scripts/init-session.sh <PLUGIN_ROOT> <FORM_NAME> <PROJECT_ROOT> [<MAX_PARALLEL>]
#
# Arguments:
# PLUGIN_ROOT  -- Absolute path to the plugin directory
# FORM_NAME    -- Task form name (e.g., engineering, skill-dev)
# PROJECT_ROOT -- Project root directory (usually .)
# MAX_PARALLEL -- Optional max parallel pairs (default: 2)
#
# Design principle: "Deterministic > Agentic" - don't LLM what should be
# mechanical. This script handles all session bootstrapping so the TL
# can focus on planning and orchestration.
#
# Exit codes:
# 0 = init succeeded (INIT_STATUS=pass)
# 1 = init failed (INIT_STATUS=fail)
# 2 = usage error

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 3 ]; then
  cat <<'USAGE'
Usage: bash scripts/init-session.sh <PLUGIN_ROOT> <FORM_NAME> <PROJECT_ROOT> [<MAX_PARALLEL>]

  PLUGIN_ROOT  -- Absolute path to the plugin directory
  FORM_NAME    -- Task form name (e.g., engineering, skill-dev)
  PROJECT_ROOT -- Project root directory (usually .)
  MAX_PARALLEL -- Optional max parallel pairs (default: 2)

Creates session directories, writes template state files, detects
validation commands, resolves global-guide.md, and runs self-test.

Outputs structured key=value pairs to stdout on success:
  INIT_STATUS=pass
  GLOBAL_GUIDE_PATH=.superteam/resolved-global-guide.md
  VALIDATION_COMMANDS=<detected commands>
USAGE
  exit 2
fi

PLUGIN_ROOT="$1"
FORM_NAME="$2"
PROJECT_ROOT="$3"
MAX_PARALLEL="${4:-2}"

# Validate PLUGIN_ROOT is an absolute path
if [[ "$PLUGIN_ROOT" != /* ]]; then
  echo "INIT_STATUS=fail"
  echo "INIT_ERROR=PLUGIN_ROOT must be an absolute path, got: $PLUGIN_ROOT"
  exit 1
fi

# Validate PLUGIN_ROOT exists
if [ ! -d "$PLUGIN_ROOT" ]; then
  echo "INIT_STATUS=fail"
  echo "INIT_ERROR=PLUGIN_ROOT directory does not exist: $PLUGIN_ROOT"
  exit 1
fi

# Change to project root for all relative operations
cd "$PROJECT_ROOT"

SUPERTEAM_DIR=".superteam"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GLOBAL_WIKI="${SUPERTEAM_WIKI_PATH:-$HOME/.superteam}"

# ---------------------------------------------------------------------------
# Step 1: Create session directories
# ---------------------------------------------------------------------------

echo "--- Creating session directories ---"

mkdir -p "$SUPERTEAM_DIR/contracts"
mkdir -p "$SUPERTEAM_DIR/scripts/final"
mkdir -p "$SUPERTEAM_DIR/attempts"
mkdir -p "$SUPERTEAM_DIR/traces"
mkdir -p "$SUPERTEAM_DIR/verdicts"
mkdir -p "$SUPERTEAM_DIR/gate-results"
mkdir -p "$SUPERTEAM_DIR/knowledge/findings"

echo "  OK: Session directories created"

# ---------------------------------------------------------------------------
# Step 2: Create global wiki directories
# ---------------------------------------------------------------------------

echo "--- Creating global wiki directories ---"

mkdir -p "$GLOBAL_WIKI/knowledge" "$GLOBAL_WIKI/skills" "$GLOBAL_WIKI/projects"
chmod 700 "$GLOBAL_WIKI"

echo "  OK: Global wiki directories created"

# ---------------------------------------------------------------------------
# Step 3: Create global wiki index (only if missing)
# ---------------------------------------------------------------------------

echo "--- Checking global wiki index ---"

if [ ! -f "$GLOBAL_WIKI/index.md" ]; then
  cat > "$GLOBAL_WIKI/index.md" <<'WIKIINDEX'
# Superteam Knowledge Index

## Skills
| Skill | Description | Path |
| | | |

## Knowledge
| Topic | Description | Path |
| | | |

## Projects
| Project | Description | Path |
| | | |
WIKIINDEX
  echo "  OK: Created $GLOBAL_WIKI/index.md"
else
  echo "  OK: $GLOBAL_WIKI/index.md already exists (skipped)"
fi

# ---------------------------------------------------------------------------
# Step 4: Copy SCHEMA.md to global wiki (always overwrite)
# ---------------------------------------------------------------------------

echo "--- Copying SCHEMA.md ---"

if [ -f "$PLUGIN_ROOT/docs/SCHEMA.md" ]; then
  cp "$PLUGIN_ROOT/docs/SCHEMA.md" "$GLOBAL_WIKI/SCHEMA.md"
  echo "  OK: SCHEMA.md copied to global wiki"
else
  echo "  WARNING: $PLUGIN_ROOT/docs/SCHEMA.md not found (skipped)"
fi

# ---------------------------------------------------------------------------
# Step 5: Create knowledge store log (only if missing)
# ---------------------------------------------------------------------------

echo "--- Checking knowledge store log ---"

if [ ! -f "$GLOBAL_WIKI/log.md" ]; then
  echo "# Knowledge store log" > "$GLOBAL_WIKI/log.md"
  echo "  OK: Created $GLOBAL_WIKI/log.md"
else
  echo "  OK: $GLOBAL_WIKI/log.md already exists (skipped)"
fi

# ---------------------------------------------------------------------------
# Step 6: Detect validation commands
# ---------------------------------------------------------------------------

echo "--- Detecting validation commands ---"

VALIDATION_COMMANDS=""

if [ -f "package.json" ]; then
  VALIDATION_COMMANDS="npm test, tsc --noEmit, eslint . --quiet"
  echo "  Detected: package.json -> $VALIDATION_COMMANDS"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  VALIDATION_COMMANDS="pytest, mypy ., ruff check ."
  echo "  Detected: Python project -> $VALIDATION_COMMANDS"
elif [ -f "go.mod" ]; then
  VALIDATION_COMMANDS="go test ./..., go vet ./..."
  echo "  Detected: go.mod -> $VALIDATION_COMMANDS"
elif [ -f "Cargo.toml" ]; then
  VALIDATION_COMMANDS="cargo test, cargo clippy"
  echo "  Detected: Cargo.toml -> $VALIDATION_COMMANDS"
else
  echo "  No recognized project config found (validation commands empty)"
fi

# Write validation commands to a separate read-only file (consumed by invariant-check.sh)
if [ -n "$VALIDATION_COMMANDS" ]; then
  echo "$VALIDATION_COMMANDS" > "$SUPERTEAM_DIR/validation-commands.txt"
  chmod 444 "$SUPERTEAM_DIR/validation-commands.txt"
  echo "  OK: Written to $SUPERTEAM_DIR/validation-commands.txt (read-only)"
else
  echo "  Skipped: validation-commands.txt (no commands detected)"
fi

# ---------------------------------------------------------------------------
# Step 7: Write template state files
# ---------------------------------------------------------------------------

echo "--- Writing template state files ---"

# --- metrics.md ---
cat > "$SUPERTEAM_DIR/metrics.md" <<METRICS
---
started: "${TIMESTAMP}"
completed: null
---

## Phase Timing
| Phase | Started | Completed | Duration |
|-------|---------|-----------|----------|

## Per-Increment Metrics
| # | Name | Type | Attempts | Iterations | Duration | Status |
| | | | | | | |

## Manager Heuristics (Current)
- Avg iterations per increment: 0
- Avg time per increment: 0
- Exploration increments inserted: 0
- Architect restarts: 0

## Summary
- Total iterations: 0
- Context resets: 0
- Plan mutations: 0
- Exploration increments: 0
- Explorer queries: 0
- Architect checkpoints: 0
METRICS
echo "  OK: metrics.md"

# --- lessons-learned.md ---
cat > "$SUPERTEAM_DIR/lessons-learned.md" <<LESSONS
---
last_updated: "${TIMESTAMP}"
---

(No lessons yet - Generator and Evaluator will append discoveries after each increment.)
LESSONS
echo "  OK: lessons-learned.md"

# --- knowledge/index.md ---
cat > "$SUPERTEAM_DIR/knowledge/index.md" <<KINDEX
---
last_updated: "${TIMESTAMP}"
total_findings: 0
---

## Topics Explored

| # | Topic | File | Requested By | Depth |
|---|-------|------|--------------|-------|
KINDEX
echo "  OK: knowledge/index.md"

# --- state.json (unified, CAS-managed) ---
# Introduced Increment 1 (docs/SCHEMA.md §"Unified state"). Loop-state
# (.loop.*, .agents.architect_status, .agents.explorer_status, etc.) is
# owned here as of Increment 5; TL state was migrated in Increment 4.
# `state-mutate.sh --init` writes the frozen schema; it is idempotent
# on an already-valid state.json.
STATE_MUTATE_SCRIPT="$PLUGIN_ROOT/scripts/state-mutate.sh"
if [ -f "$STATE_MUTATE_SCRIPT" ]; then
  SUPERTEAM_SESSION_STARTED="$TIMESTAMP" \
  SUPERTEAM_TASK_FORM="$FORM_NAME" \
  SUPERTEAM_FORM_DIR="$PLUGIN_ROOT/task-forms/$FORM_NAME/" \
  SUPERTEAM_MAX_PARALLEL="$MAX_PARALLEL" \
  bash "$STATE_MUTATE_SCRIPT" --init
  echo "  OK: state.json (revision=0, schema_version=1)"
else
  echo "  WARNING: $STATE_MUTATE_SCRIPT not found; skipping state.json init"
fi

# --- events.jsonl (append-only event stream) ---
# Introduced Increment 2 (spec.md FR-2.3 / EC-5). scripts/record-event.sh
# is the sole appender (C-4) and refuses to run when this file is
# absent - seeding it here makes init-session the canonical creator.
: > "$SUPERTEAM_DIR/events.jsonl"
echo "  OK: events.jsonl (empty, append-only)"

# --- strict-evaluations.jsonl (append-only strict-evaluation log) ---
# Introduced Increment 3 (spec.md FR-3.1 / FR-3.2 / FR-3.5).
# scripts/record-strict-evaluation.sh is the sole appender and refuses
# to run when this file is absent - seeding it here makes init-session
# the canonical creator.
: > "$SUPERTEAM_DIR/strict-evaluations.jsonl"
echo "  OK: strict-evaluations.jsonl (empty, append-only)"

# ---------------------------------------------------------------------------
# Step 8: Resolve global-guide.md
# ---------------------------------------------------------------------------

echo "--- Resolving global-guide.md ---"

GLOBAL_GUIDE_PATH="$SUPERTEAM_DIR/resolved-global-guide.md"

if [ -f "$PLUGIN_ROOT/global-guide.md" ]; then
  # Read template and replace ${PLUGIN_ROOT} with actual value
  sed "s|\${PLUGIN_ROOT}|${PLUGIN_ROOT}|g" "$PLUGIN_ROOT/global-guide.md" > "$GLOBAL_GUIDE_PATH"
  echo "  OK: Resolved $PLUGIN_ROOT/global-guide.md -> $GLOBAL_GUIDE_PATH"
else
  cat > "$GLOBAL_GUIDE_PATH" <<'FALLBACK'
Use your configured external knowledge MCP to search any unknown terms or company-internal knowledge. Always try local search (Grep/Glob) before escalating.
FALLBACK
  echo "  OK: Wrote fallback global guide (template not found at $PLUGIN_ROOT/global-guide.md)"
fi

# ---------------------------------------------------------------------------
# Step 9: Run startup self-test
# ---------------------------------------------------------------------------

echo "--- Running startup self-test ---"

SELFTEST_EXIT=0
SELFTEST_OUTPUT=""
SELFTEST_OUTPUT=$(bash "$PLUGIN_ROOT/hooks/startup-self-test.sh" 2>&1) || SELFTEST_EXIT=$?

echo "$SELFTEST_OUTPUT"

if [ "$SELFTEST_EXIT" -ne 0 ]; then
  echo ""
  echo "INIT_STATUS=fail"
  echo "INIT_ERROR=Startup self-test failed (exit $SELFTEST_EXIT). See output above."
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 10: Output success
# ---------------------------------------------------------------------------

echo ""
echo "INIT_STATUS=pass"
echo "GLOBAL_GUIDE_PATH=$GLOBAL_GUIDE_PATH"
echo "VALIDATION_COMMANDS=$VALIDATION_COMMANDS"

exit 0
