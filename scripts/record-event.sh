#!/bin/bash
# record-event.sh - Append a single record to .superteam/events.jsonl.
#
# Sole appender for the session event stream (C-4). Validates arguments,
# constructs a one-line JSON record with `jq -c`, and appends under an
# exclusive flock on .superteam/events.jsonl.lock. The stream file
# itself is created by scripts/init-session.sh - this primitive refuses
# to run when it is absent (agents must go through init-session first).
#
# Usage:
#  scripts/record-event.sh --actor <name> --type <enum> --payload '<json>'
#
# --type enum: decision | anomaly | mutation | escalation | transition.
# --payload must parse as valid JSON (validated via `jq -e .`).
#
# Record schema (one JSON object per line, UTF-8, LF-terminated):
# {"ts":"<ISO-8601Z>","actor":"<name>","type":"<enum>","payload":{...}}
#
# Atomicity: O_APPEND makes single-write appends atomic on Linux for
# payloads below PIPE_BUF (4096B), but we take `flock -x` as
# belt-and-suspenders for portability across filesystems and to cover
# records that might approach that threshold in future.
#
# Env overrides:
# SUPERTEAM_DIR  default: .superteam
# EVENT_STREAM   default: $SUPERTEAM_DIR/events.jsonl
# EVENT_LOCK     default: $EVENT_STREAM.lock
#
# Exit codes:
# 0 = record appended
# 1 = validation failure, missing dependency, or stream not initialized

set -euo pipefail

SUPERTEAM_DIR="${SUPERTEAM_DIR:-.superteam}"
EVENT_STREAM="${EVENT_STREAM:-$SUPERTEAM_DIR/events.jsonl}"
EVENT_LOCK="${EVENT_LOCK:-$EVENT_STREAM.lock}"

VALID_TYPES="decision anomaly mutation escalation transition"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/record-event.sh --actor <name> --type <enum> --payload '<json>'

  --actor    Required. Non-empty writer identity (free-form string).
  --type     Required. One of: decision, anomaly, mutation, escalation, transition.
  --payload  Required. A valid JSON value (object recommended).

Env: SUPERTEAM_DIR, EVENT_STREAM, EVENT_LOCK
USAGE
}

# ---------------------------------------------------------------------------
# Parse args (explicit long options; no reliance on getopt)
# ---------------------------------------------------------------------------

ACTOR=""
TYPE=""
PAYLOAD=""
HAVE_PAYLOAD=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --actor)
      [ "$#" -ge 2 ] || { echo "record-event: --actor requires a value" >&2; exit 1; }
      ACTOR="$2"; shift 2 ;;
    --type)
      [ "$#" -ge 2 ] || { echo "record-event: --type requires a value" >&2; exit 1; }
      TYPE="$2"; shift 2 ;;
    --payload)
      [ "$#" -ge 2 ] || { echo "record-event: --payload requires a value" >&2; exit 1; }
      PAYLOAD="$2"; HAVE_PAYLOAD=1; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "record-event: unknown argument: $1" >&2
      usage
      exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate: required args present, type in enum, payload parses, stream exists.
# Order matters - the diagnostics form a linter-as-teacher trail.
# ---------------------------------------------------------------------------

if [ -z "$ACTOR" ]; then
  echo "record-event: --actor is required (non-empty)" >&2
  exit 1
fi
if [ -z "$TYPE" ]; then
  echo "record-event: --type is required" >&2
  exit 1
fi
if [ "$HAVE_PAYLOAD" -eq 0 ]; then
  echo "record-event: --payload is required" >&2
  exit 1
fi

TYPE_OK=0
for t in $VALID_TYPES; do
  if [ "$TYPE" = "$t" ]; then TYPE_OK=1; break; fi
done
if [ "$TYPE_OK" -ne 1 ]; then
  echo "record-event: invalid --type '$TYPE'" >&2
  echo "  expected one of: $VALID_TYPES" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "record-event: jq is required" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "record-event: flock is required" >&2; exit 1; }

if ! printf '%s' "$PAYLOAD" | jq -e . >/dev/null 2>&1; then
  echo "record-event: --payload is not valid JSON" >&2
  echo '  hint: quote carefully, e.g. --payload '"'"'{"k":"v"}'"'" >&2
  exit 1
fi

if [ ! -f "$EVENT_STREAM" ]; then
  echo "record-event: event stream not found at $EVENT_STREAM" >&2
  echo "  hint: run scripts/init-session.sh first (events.jsonl is seeded at init)" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build record and append under exclusive flock.
# ---------------------------------------------------------------------------

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RECORD="$(
  jq -cn \
    --arg ts "$TS" \
    --arg actor "$ACTOR" \
    --arg type "$TYPE" \
    --argjson payload "$PAYLOAD" \
    '{ts: $ts, actor: $actor, type: $type, payload: $payload}'
)"

# Ensure the lock file exists (flock opens it via fd 9). Truncating an
# already-present lock file is harmless - flock locks the open-file
# description, not the file contents.
: > "$EVENT_LOCK" 2>/dev/null || true

(
  flock -x 9
  printf '%s\n' "$RECORD" >> "$EVENT_STREAM"
) 9>"$EVENT_LOCK"

exit 0
