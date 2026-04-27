#!/usr/bin/env bash
set -euo pipefail

# verdict-validation.sh - Stop hook (nudge pattern, always exit 0)
# Fires on agent exit. Checks recent verdict files for valid verdicts.

# 1. If superteam directory doesn't exist, nothing to validate.
if [ ! -d ".superteam" ]; then
  exit 0
fi

# Helper: shared library
_VV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_VV_DIR/../scripts/lib.sh"

# 2. Find verdict files modified in the last 10 minutes.
verdict_files=$(find .superteam/verdicts/ -name "*.md" -mmin -10 2>/dev/null || true)

if [ -z "$verdict_files" ]; then
  exit 0
fi

# 3. Valid verdict values.
VALID_VERDICTS="APPROVED REVISE GATE-CHALLENGE PASS FAIL"

is_valid_verdict() {
  local v="$1"
  for valid in $VALID_VERDICTS; do
    if [ "$v" = "$valid" ]; then
      return 0
    fi
  done
  return 1
}

# 4. Check each verdict file.
while IFS= read -r vfile; do
  [ -z "$vfile" ] && continue

  verdict=$(parse_yaml_field "$vfile" "verdict")

  if [ -z "$verdict" ]; then
    continue
  fi

  if ! is_valid_verdict "$verdict"; then
    filename=$(basename "$vfile")
    cat <<EOF

WARNING: Invalid verdict detected in $filename
The verdict "${verdict}" is not valid.
Valid: APPROVED, REVISE, GATE-CHALLENGE.
If hard gates fail, use REVISE or GATE-CHALLENGE.
There is NO conditional/partial pass.
EOF
  fi
done <<< "$verdict_files"

# 5. Always exit 0 (nudge pattern).
exit 0
