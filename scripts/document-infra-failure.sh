#!/bin/bash
# document-infra-failure.sh - Create/validate infrastructure failure documentation
# Ensures agents document at least 3 substantive remediation attempts before
# concluding an infrastructure failure investigation.
#
# Usage: bash scripts/document-infra-failure.sh <increment_number>
#
# Behavior:
# If the file does not exist: creates a template and exits 1.
# If the file exists but < 3 substantive attempts: prints guidance and exits 1.
# If the file exists with >= 3 substantive attempts: validates and exits 0.
#
# Exit codes:
# 0 = documentation validated (>= 3 substantive attempts)
# 1 = template created or documentation incomplete
# 2 = usage error

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/document-infra-failure.sh <increment_number>"
  exit 2
fi

INCREMENT="$1"
SUPERTEAM_DIR=".superteam"
ATTEMPTS_DIR="$SUPERTEAM_DIR/attempts"
FILE="$ATTEMPTS_DIR/infra-failure-${INCREMENT}.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$ATTEMPTS_DIR"

# ---------------------------------------------------------------------------
# If file does NOT exist: create template
# ---------------------------------------------------------------------------

if [ ! -f "$FILE" ]; then
  cat > "$FILE" <<TEMPLATE
---
increment: ${INCREMENT}
failure_type: infrastructure
created: ${TIMESTAMP}
remediation_attempts: 0
status: investigating
---

## Failure Description

[Describe the infrastructure failure: what happened, when it started, what error
messages or symptoms were observed.]

## Knowledge Base Search

[Document what you searched for in the knowledge base, global wiki, or external
sources. Include search queries used and what was found (or not found).]

## Remediation Attempts

### Attempt 1
- **What was tried:** [description]
- **Expected outcome:** [what you hoped would happen]
- **Actual outcome:** [what actually happened]
- **Evidence:** [logs, error messages, screenshots]

### Attempt 2
- **What was tried:** [description]
- **Expected outcome:** [what you hoped would happen]
- **Actual outcome:** [what actually happened]
- **Evidence:** [logs, error messages, screenshots]

### Attempt 3
- **What was tried:** [description]
- **Expected outcome:** [what you hoped would happen]
- **Actual outcome:** [what actually happened]
- **Evidence:** [logs, error messages, screenshots]

## Conclusion

[Summary of findings. Was the issue resolved? If not, what is the recommended
escalation path?]
TEMPLATE
  echo "Template created."
  exit 1
fi

# ---------------------------------------------------------------------------
# File EXISTS: validate content
# ---------------------------------------------------------------------------

# Count attempt headings
ATTEMPT_COUNT=$(grep -c '^### Attempt' "$FILE" || true)

# Count substantive attempts (have real content after "What was tried:")
SUBSTANTIVE=0
while IFS= read -r line; do
  # Extract the content after "What was tried:"
  content=$(echo "$line" | sed 's/.*What was tried:\*\*//' | xargs)
  # Check it is not empty, not a placeholder
  if [ -n "$content" ] && [ "$content" != "[description]" ]; then
    SUBSTANTIVE=$((SUBSTANTIVE + 1))
  fi
done < <(grep "What was tried:" "$FILE" || true)

# Validate Failure Description section has real content
FAILURE_DESC_OK=false
if sed -n '/^## Failure Description/,/^## /p' "$FILE" | grep -qvE '^\s*$|^## |\['; then
  FAILURE_DESC_OK=true
fi

# Validate Knowledge Base Search section has real content
KB_SEARCH_OK=false
if sed -n '/^## Knowledge Base Search/,/^## /p' "$FILE" | grep -qvE '^\s*$|^## |\['; then
  KB_SEARCH_OK=true
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

if [ "$SUBSTANTIVE" -lt 3 ]; then
  echo "INCOMPLETE: ${SUBSTANTIVE}/3 required substantive remediation attempts."
  [ "$FAILURE_DESC_OK" = false ] && echo "  - Failure Description section needs real content (not just placeholder)."
  [ "$KB_SEARCH_OK" = false ] && echo "  - Knowledge Base Search section needs real content (not just placeholder)."
  [ "$SUBSTANTIVE" -lt 3 ] && echo "  - Fill in 'What was tried:' with actual descriptions (not '[description]')."
  exit 1
fi

# All checks passed - update frontmatter
sed -i "s/^remediation_attempts:.*/remediation_attempts: ${SUBSTANTIVE}/" "$FILE"
sed -i "s/^status:.*/status: concluded/" "$FILE"

echo "Validated."
exit 0
