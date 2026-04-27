#!/bin/bash
# test-parse-yaml-field.sh - Tests for the shared parse_yaml_field function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-parse-yaml-field ==="

# Test 1: Basic field extraction
cat > "$TMPDIR/basic.md" <<'EOF'
---
name: "test-increment"
status: frozen
count: 5
---

# Body content
EOF

assert_eq "basic string field" "test-increment" "$(parse_yaml_field "$TMPDIR/basic.md" "name")"
assert_eq "basic unquoted field" "frozen" "$(parse_yaml_field "$TMPDIR/basic.md" "status")"
assert_eq "nonexistent field returns empty" "" "$(parse_yaml_field "$TMPDIR/basic.md" "nonexistent")"

# Test 3: Missing file returns empty
assert_eq "missing file returns empty" "" "$(parse_yaml_field "$TMPDIR/no-such-file.md" "name")"

# Test 4: Field with spaces in value
cat > "$TMPDIR/spaces.md" <<'EOF'
---
name: "Priority 0 Bug Fixes"
description: some description here
---
EOF

assert_eq "quoted field with spaces" "Priority 0 Bug Fixes" "$(parse_yaml_field "$TMPDIR/spaces.md" "name")"
assert_eq "unquoted field with spaces" "some description here" "$(parse_yaml_field "$TMPDIR/spaces.md" "description")"

# Test 5: YAML list field (comma-separated scalar)
cat > "$TMPDIR/list.md" <<'EOF'
---
spec_items: [1, 2, 3, 5, 6]
validation_commands: ""
---
EOF

assert_eq "list field" "[1, 2, 3, 5, 6]" "$(parse_yaml_field "$TMPDIR/list.md" "spec_items")"
assert_eq "empty quoted field" "" "$(parse_yaml_field "$TMPDIR/list.md" "validation_commands")"

# Test 6: Field after body content is NOT extracted (only frontmatter)
cat > "$TMPDIR/body.md" <<'EOF'
---
status: frozen
---

# Body
status: not-frozen
EOF

assert_eq "only extracts from frontmatter" "frozen" "$(parse_yaml_field "$TMPDIR/body.md" "status")"

# Test 7: First occurrence wins when field is duplicated
cat > "$TMPDIR/dup.md" <<'EOF'
---
status: first
status: second
---
EOF

assert_eq "first occurrence wins" "first" "$(parse_yaml_field "$TMPDIR/dup.md" "status")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
