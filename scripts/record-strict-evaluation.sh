#!/bin/bash
# record-strict-evaluation.sh - Append a single record to
# .superteam/strict-evaluations.jsonl.
#
# Sole appender for the strict-evaluation log (FR-3.1/3.2/3.5). Validates
# arguments, parses YAML frontmatter from the failure report, constructs
# a one-line JSON record with `jq -c`, and appends under an exclusive
# flock on .superteam/strict-evaluations.jsonl.lock. The stream file
# itself is created by scripts/init-session.sh - this primitive refuses
# to run when it is absent (agents must go through init-session first).
#
# Usage:
#  scripts/record-strict-evaluation.sh --cycle <N> --verdict <FAIL|PASS> \
#    --report-file <path>
#
# Optional: --payload '<json>' is accepted for forward-compat but currently
# ignored (contract frontmatter parsing is authoritative).
#
# Record schema (one JSON object per line, UTF-8, LF-terminated):
# {
#   "ts": "<ISO-8601Z>",
#   "cycle": <N>,
#   "verdict": "FAIL" | "PASS",
#   "hard_gates_failed": [...],
#   "soft_gates_unmet": [...],
#   "spec_requirements_unsatisfied": [...],
#   "specific_gaps": [...],
#   "summary": "<body-of-report>"
# }
#
# Idempotent-by-cycle: a second append with an existing .cycle value is
# rejected (non-zero exit, stream untouched). Safe-replay callers must
# treat non-zero+unchanged-stream as success; non-zero+stream-changed is
# impossible under flock.
#
# Env overrides:
# SUPERTEAM_DIR       default: .superteam
# STRICT_EVAL_STREAM  default: $SUPERTEAM_DIR/strict-evaluations.jsonl
# STRICT_EVAL_LOCK    default: $STRICT_EVAL_STREAM.lock
#
# Exit codes:
# 0 = record appended
# 1 = validation failure, duplicate cycle, or stream not initialized

set -euo pipefail

SUPERTEAM_DIR="${SUPERTEAM_DIR:-.superteam}"
STRICT_EVAL_STREAM="${STRICT_EVAL_STREAM:-$SUPERTEAM_DIR/strict-evaluations.jsonl}"
STRICT_EVAL_LOCK="${STRICT_EVAL_LOCK:-$STRICT_EVAL_STREAM.lock}"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/record-strict-evaluation.sh \
  --cycle <N> --verdict <FAIL|PASS> --report-file <path>

  --cycle        Required. Non-negative integer.
  --verdict      Required. One of: FAIL, PASS.
  --report-file  Required. Path to a readable failure-report file.
  --payload      Optional. Accepted for forward-compat; ignored.

Env: SUPERTEAM_DIR, STRICT_EVAL_STREAM, STRICT_EVAL_LOCK
USAGE
}

# ---------------------------------------------------------------------------
# Parse args (explicit long options; no reliance on getopt).
# ---------------------------------------------------------------------------

CYCLE=""
VERDICT=""
REPORT_FILE=""
HAVE_CYCLE=0
HAVE_VERDICT=0
HAVE_REPORT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --cycle)
      [ "$#" -ge 2 ] || { echo "record-strict-evaluation: --cycle requires a value" >&2; exit 1; }
      CYCLE="$2"; HAVE_CYCLE=1; shift 2 ;;
    --verdict)
      [ "$#" -ge 2 ] || { echo "record-strict-evaluation: --verdict requires a value" >&2; exit 1; }
      VERDICT="$2"; HAVE_VERDICT=1; shift 2 ;;
    --report-file)
      [ "$#" -ge 2 ] || { echo "record-strict-evaluation: --report-file requires a value" >&2; exit 1; }
      REPORT_FILE="$2"; HAVE_REPORT=1; shift 2 ;;
    --payload)
      # Accepted for forward-compat; value is discarded.
      [ "$#" -ge 2 ] || { echo "record-strict-evaluation: --payload requires a value" >&2; exit 1; }
      shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "record-strict-evaluation: unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate: required args present, enums, numeric cycle, files readable.
# ---------------------------------------------------------------------------

if [ "$HAVE_CYCLE" -eq 0 ]; then
  echo "record-strict-evaluation: --cycle is required" >&2
  exit 1
fi
if [ "$HAVE_VERDICT" -eq 0 ]; then
  echo "record-strict-evaluation: --verdict is required" >&2
  exit 1
fi
if [ "$HAVE_REPORT" -eq 0 ]; then
  echo "record-strict-evaluation: --report-file is required" >&2
  exit 1
fi

if ! printf '%s' "$CYCLE" | grep -qE '^(0|[1-9][0-9]*)$'; then
  echo "record-strict-evaluation: --cycle must be a non-negative integer (got '$CYCLE')" >&2
  exit 1
fi

if [ "$VERDICT" != "FAIL" ] && [ "$VERDICT" != "PASS" ]; then
  echo "record-strict-evaluation: invalid --verdict '$VERDICT' (expected FAIL or PASS)" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "record-strict-evaluation: jq is required" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "record-strict-evaluation: flock is required" >&2; exit 1; }

if [ ! -f "$REPORT_FILE" ] || [ ! -r "$REPORT_FILE" ]; then
  echo "record-strict-evaluation: --report-file not found or unreadable: $REPORT_FILE" >&2
  exit 1
fi

if [ ! -f "$STRICT_EVAL_STREAM" ]; then
  echo "record-strict-evaluation: stream not found at $STRICT_EVAL_STREAM" >&2
  echo "  hint: run scripts/init-session.sh first (strict-evaluations.jsonl is seeded at init)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Idempotent-by-cycle: reject duplicate cycle without touching the stream.
# Use jq -c to stream the file (one JSON doc per line) and emit the first
# record matching .cycle == $c. Non-empty output = duplicate present.
# ---------------------------------------------------------------------------

if [ -s "$STRICT_EVAL_STREAM" ]; then
  DUP="$(jq -c --argjson c "$CYCLE" 'select(.cycle == $c)' "$STRICT_EVAL_STREAM" 2>/dev/null | head -1 || true)"
  if [ -n "$DUP" ]; then
    echo "record-strict-evaluation: duplicate cycle $CYCLE already recorded (idempotent no-op; stream unchanged)" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Parse YAML frontmatter from the report file.
#
# Frontmatter is recognized only when the file begins with "---" on line 1
# and a closing "---" appears on a later line. Arrays (hard_gates_failed,
# soft_gates_unmet, spec_requirements_unsatisfied, specific_gaps) are
# parsed as JSON array literals (YAML [] = JSON [] for simple values).
# Anything malformed or missing defaults to [].
#
# The body (everything after the closing "---", or the whole file if no
# frontmatter) is inlined verbatim as the 'summary' string.
# ---------------------------------------------------------------------------

extract_frontmatter_and_body() {
  local report="$1"
  FRONTMATTER=""
  BODY=""
  if [ "$(head -1 "$report" 2>/dev/null || true)" = "---" ]; then
    fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$report")"
    if [ -n "$fm_end" ]; then
      FRONTMATTER="$(sed -n "2,$((fm_end - 1))p" "$report")"
      BODY="$(sed -n "$((fm_end + 1)),\$p" "$report")"
      return 0
    fi
  fi
  BODY="$(cat "$report")"
}

extract_array_field() {
  # Echoes a JSON array literal for 'field' from FRONTMATTER; [] on miss.
  local field="$1" line val
  line="$(printf '%s\n' "$FRONTMATTER" | grep -E "^[[:space:]]*${field}:" | head -1 || true)"
  if [ -z "$line" ]; then
    printf '[]'
    return 0
  fi
  val="$(printf '%s' "$line" | sed -E "s/^[[:space:]]*${field}: [[:space:]]*//")"
  if [ -z "$val" ]; then
    printf '[]'
    return 0
  fi
  if printf '%s' "$val" | jq -e 'type == "array"' >/dev/null 2>&1; then
    printf '%s' "$val"
  else
    printf '[]'
  fi
}

extract_frontmatter_and_body "$REPORT_FILE"

HARD_GATES_FAILED_JSON="$(extract_array_field hard_gates_failed)"
SOFT_GATES_UNMET_JSON="$(extract_array_field soft_gates_unmet)"
SPEC_REQ_UNSAT_JSON="$(extract_array_field spec_requirements_unsatisfied)"
SPECIFIC_GAPS_JSON="$(extract_array_field specific_gaps)"

# ---------------------------------------------------------------------------
# Build the record and append under exclusive flock.
# ---------------------------------------------------------------------------

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RECORD="$(
  jq -cn \
    --arg ts "$TS" \
    --argjson cycle "$CYCLE" \
    --arg verdict "$VERDICT" \
    --argjson hard "$HARD_GATES_FAILED_JSON" \
    --argjson soft "$SOFT_GATES_UNMET_JSON" \
    --argjson specreq "$SPEC_REQ_UNSAT_JSON" \
    --argjson gaps "$SPECIFIC_GAPS_JSON" \
    --arg summary "$BODY" \
    '{
      ts: $ts,
      cycle: $cycle,
      verdict: $verdict,
      hard_gates_failed: $hard,
      soft_gates_unmet: $soft,
      spec_requirements_unsatisfied: $specreq,
      specific_gaps: $gaps,
      summary: $summary
    }'
)"

# Ensure the lock file exists (flock opens it via fd 9).
: > "$STRICT_EVAL_LOCK" 2>/dev/null || true

(
  flock -x 9
  # Re-check idempotency under the lock to close the append race:
  # a parallel writer may have landed $CYCLE between our pre-check and
  # the open-for-append below.
  if [ -s "$STRICT_EVAL_STREAM" ]; then
    DUP_LOCKED="$(jq -c --argjson c "$CYCLE" 'select(.cycle == $c)' "$STRICT_EVAL_STREAM" 2>/dev/null | head -1 || true)"
    if [ -n "$DUP_LOCKED" ]; then
      echo "record-strict-evaluation: duplicate cycle $CYCLE (race, stream unchanged)" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$RECORD" >> "$STRICT_EVAL_STREAM"
) 9>"$STRICT_EVAL_LOCK"

exit 0
