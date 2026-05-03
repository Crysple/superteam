#!/bin/bash
# state-mutate.sh - CAS-protected mutator for the unified state.json.
#
# Owns the read/write path for `.superteam/state.json`, guaranteeing
# read-check-write atomicity via `flock -x` on a sibling lock file and
# atomic write via tmp+rename. Callers race safely by retrying on the
# CAS_CONFLICT_EXIT (9) return code; the primitive itself performs one
# compare-and-swap per invocation (retries are a caller responsibility -
# CAS_RETRY_BOUND controls an internal loop here when >0, default 5).
#
# Usage:
# scripts/state-mutate.sh --init
# Create .superteam/state.json with the frozen schema
# (revision=0). Idempotent: if a valid state.json already exists,
# exit 0 without mutating.
#
# scripts/state-mutate.sh --set FIELD=VALUE
# CAS write of a top-level FIELD. VALUE is parsed as JSON when it
# is a valid JSON literal (number, true/false/null, array, object),
# otherwise as a string. Bumps .revision by 1 on success. On CAS
# conflict (another writer bumped .revision since we read it),
# exits CAS_CONFLICT_EXIT (9) after CAS_RETRY_BOUND retries.
#
# scripts/state-mutate.sh get <jq-path>
# Read a field. Prints the JSON value to stdout. Lock-free (writes
# use atomic rename; readers see either the pre- or post-state,
# never torn).
#
# Env overrides:
# SUPERTEAM_DIR  default: .superteam
# STATE_FILE     default: $SUPERTEAM_DIR/state.json
# STATE_LOCK     default: $SUPERTEAM_DIR/state.json.lock
# CAS_CONFLICT_EXIT  default: 9
# CAS_RETRY_BOUND    default: 5 (set to 0 to surface first conflict)
#
# Exit codes:
# 0 = success
# 1 = generic failure (usage error, I/O)
# 2 = usage error (missing args, bad form)
# 9 = CAS conflict (default CAS_CONFLICT_EXIT; configurable)

set -euo pipefail

SUPERTEAM_DIR="${SUPERTEAM_DIR:-.superteam}"
STATE_FILE="${STATE_FILE:-$SUPERTEAM_DIR/state.json}"
STATE_LOCK="${STATE_LOCK:-$SUPERTEAM_DIR/state.json.lock}"
CAS_CONFLICT_EXIT="${CAS_CONFLICT_EXIT:-9}"
CAS_RETRY_BOUND="${CAS_RETRY_BOUND:-5}"

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/state-mutate.sh --init
  scripts/state-mutate.sh --set FIELD=VALUE
  scripts/state-mutate.sh get <jq-path>

Env: SUPERTEAM_DIR, STATE_FILE, STATE_LOCK, CAS_CONFLICT_EXIT, CAS_RETRY_BOUND
USAGE
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 || { echo "state-mutate: jq is required" >&2; exit 1; }
}

ensure_flock() {
  command -v flock >/dev/null 2>&1 || { echo "state-mutate: flock is required" >&2; exit 1; }
}

ensure_state_exists() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "state-mutate: state file not found at $STATE_FILE (run --init first)" >&2
    exit 1
  fi
}

atomic_write() {
  # $1 = content producer (function name or heredoccaptured content)
  # Caller provides JSON on stdin; we write to staging file and rename.
  local staging="${STATE_FILE}.new.$$"
  cat > "$staging"
  # jq validation: ensure content is valid JSON before swap.
  if ! jq empty "$staging" >/dev/null 2>&1; then
    rm -f "$staging"
    echo "state-mutate: refused to write malformed JSON" >&2
    return 1
  fi
  mv "$staging" "$STATE_FILE"
}

cmd_init() {
  ensure_jq
  mkdir -p "$SUPERTEAM_DIR"

  # Idempotent: if the file exists and parses as JSON with a numeric
  # .revision, treat as already initialized (exit 0, no mutation).
  if [ -f "$STATE_FILE" ] \
    && jq -e 'type == "object" and (.revision | type) == "number"' \
      "$STATE_FILE" >/dev/null 2>&1; then
    return 0
  fi

  local started="${SUPERTEAM_SESSION_STARTED:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
  local task_form="${SUPERTEAM_TASK_FORM:-}"
  local form_dir="${SUPERTEAM_FORM_DIR:-}"
  local max_parallel="${SUPERTEAM_MAX_PARALLEL:-2}"

  jq -n \
    --arg started "$started" \
    --arg form "$task_form" \
    --arg formdir "$form_dir" \
    --argjson max_parallel "$max_parallel" \
    '{
      revision: 0,
      schema_version: 1,
      phase: "pm",
      phase_step: "init",
      session: {
        started: $started,
        last_checkpoint: $started,
        task_form: (if $form == "" then null else $form end),
        form_dir: (if $formdir == "" then null else $formdir end)
      },
      loop: {
        current_increment: 0,
        total_increments: 0,
        completed_increments: 0,
        active_pairs: 0,
        max_parallel_pairs: $max_parallel,
        global_iteration_count: 0,
        max_iterations: 100,
        manager_cycle_count: 0
      },
      agents: {
        active_agents: [],
        spawn_history: [],
        architect_status: "not_spawned",
        architect_restarts: 0,
        explorer_status: "not_spawned"
      },
      watchdog_stall_count: 0
    }' | atomic_write
}

# Parse FIELD=VALUE into globals _FIELD and _VALUE. Returns 2 on bad form.
parse_kv() {
  local spec="${1:-}"
  if [ -z "$spec" ] || [ "${spec#*=}" = "$spec" ]; then
    return 2
  fi
  _FIELD="${spec%%=*}"
  _VALUE="${spec#*=}"
  [ -n "$_FIELD" ] || return 2
  return 0
}

# Normalize VALUE into a JSON literal. If VALUE parses as JSON, pass
# through; otherwise quote as a JSON string.
value_to_json() {
  local v="$1"
  if printf '%s' "$v" | jq -e '.' >/dev/null 2>&1; then
    printf '%s' "$v"
  else
    jq -n --arg s "$v" '$s'
  fi
}

cmd_set_kv() {
  ensure_jq
  ensure_flock
  ensure_state_exists

  if ! parse_kv "${1:-}"; then
    echo "state-mutate: --set requires FIELD=VALUE" >&2
    exit 2
  fi

  local field="$_FIELD"
  local value_json
  value_json="$(value_to_json "$_VALUE")"

  # Ensure the lock file exists (flock opens it via fd 9). Pre-reading .revision
  : > "$STATE_LOCK" 2>/dev/null || true

  local attempt=0
  while :; do
    # outside the lock is a speculative snapshot; a concurrent writer
    # that acquires the lock before us will bump .revision; we detect the
    # bump on re-read inside the critical section and surface a
    # CAS conflict.
    local expected_rev
    expected_rev="$(jq -r '.revision' "$STATE_FILE")"

    local rc=0
    (
      flock -x 9

      local actual_rev
      actual_rev="$(jq -r '.revision' "$STATE_FILE")"
      if [ "$actual_rev" != "$expected_rev" ]; then
        exit "$CAS_CONFLICT_EXIT"
      fi

      jq --arg f "$field" --argjson v "$value_json" \
        '.[$f] = $v | .revision = (.revision + 1)' \
        "$STATE_FILE" | atomic_write
    ) 9>"$STATE_LOCK" || rc=$?

    if [ "$rc" -eq 0 ]; then
      return 0
    fi
    if [ "$rc" -ne "$CAS_CONFLICT_EXIT" ]; then
      return "$rc"
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$CAS_RETRY_BOUND" ]; then
      return "$CAS_CONFLICT_EXIT"
    fi
    sleep 0.01 2>/dev/null || true
  done
}

cmd_get() {
  ensure_jq
  ensure_state_exists
  local path="${1:-}"
  if [ -z "$path" ]; then
    echo "state-mutate: get requires <jq-path>" >&2
    exit 2
  fi
  case "$path" in
    -*)  jq -r "$path" "$STATE_FILE" ;;        # jq flag-style, pass as-is
    .*)  jq -r "$path" "$STATE_FILE" ;;        # already a complete jq path
    *)   jq -r ".${path}" "$STATE_FILE" ;;     # bare name, prepend dot
  esac
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

case "$1" in
  --init)
    shift
    cmd_init "$@"
    ;;
  --set)
    shift
    cmd_set_kv "${1:-}"
    ;;
  get)
    shift
    cmd_get "${1:-}"
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
