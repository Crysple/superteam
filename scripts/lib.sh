#!/bin/bash
# lib.sh - Shared shell library for superteam scripts
# Source this file from any script that needs parse_yaml_field.
#
# Usage:
# LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source "$LIB_DIR/../scripts/lib.sh" # from hooks/
# source "$LIB_DIR/lib.sh" # from scripts/

# Parse a YAML frontmatter field from a file (simple line-based parser).
# Usage: parse_yaml_field <file> <field_name>
# Returns: the field value (unquoted), or empty string if not found.
parse_yaml_field() {
  local file="$1"
  local field="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return
  fi
  sed -n '/^---$/,/^---$/p' "$file" \
    | grep "^${field}:" \
    | head -1 \
    | sed "s/^${field}: [[:space:]]*//" \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"\(.*\)"$/\1/' \
    || true
}
