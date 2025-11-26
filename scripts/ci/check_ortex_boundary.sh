#!/usr/bin/env bash
#
# HC-20 Boundary Check: Ortex usage enforcement
# ==============================================
#
# Ensures Ortex is only called from within the allowed namespaces:
# - lib/thunderline/cerebros/
# - lib/thunderline/thunderbolt/ml/
# - lib/thunderline/thunderbolt/cerebros_bridge/
#
# Usage:
#   ./scripts/ci/check_ortex_boundary.sh
#
# Exit codes:
#   0 - All clear, no violations
#   1 - Violations found
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

echo "🔍 HC-20 Boundary Check: Scanning for Ortex usage outside allowed modules..."
echo

# Define allowed paths (regex for grep -v)
ALLOWED_PATTERNS=(
  "lib/thunderline/cerebros/"
  "lib/thunderline/thunderbolt/ml/"
  "lib/thunderline/thunderbolt/cerebros_bridge/"
  "# ortex-boundary-ok"  # Escape hatch for explicit exceptions
)

# Build the grep exclude pattern
EXCLUDE_PATTERN=""
for pattern in "${ALLOWED_PATTERNS[@]}"; do
  if [ -z "$EXCLUDE_PATTERN" ]; then
    EXCLUDE_PATTERN="$pattern"
  else
    EXCLUDE_PATTERN="$EXCLUDE_PATTERN\|$pattern"
  fi
done

# Find Ortex usage
VIOLATIONS=$(grep -rn "Ortex\." lib/ \
  --include="*.ex" \
  | grep -v "$EXCLUDE_PATTERN" \
  || true)

# Also check for Ortex module references (not just function calls)
VIOLATIONS2=$(grep -rn "alias Ortex" lib/ \
  --include="*.ex" \
  | grep -v "$EXCLUDE_PATTERN" \
  || true)

# Combine violations
ALL_VIOLATIONS="$VIOLATIONS"$'\n'"$VIOLATIONS2"
ALL_VIOLATIONS=$(echo "$ALL_VIOLATIONS" | grep -v "^$" || true)

if [ -n "$ALL_VIOLATIONS" ]; then
  echo "❌ HC-20 VIOLATION: Ortex called outside Cerebros boundary"
  echo
  echo "The following files use Ortex outside the allowed namespaces:"
  echo "───────────────────────────────────────────────────────────────"
  echo "$ALL_VIOLATIONS"
  echo "───────────────────────────────────────────────────────────────"
  echo
  echo "Allowed namespaces:"
  for pattern in "${ALLOWED_PATTERNS[@]}"; do
    echo "  ✅ $pattern"
  done
  echo
  echo "To fix:"
  echo "  1. Move Ortex calls to Thunderline.Cerebros.Bridge"
  echo "  2. Or add '# ortex-boundary-ok' comment if exception is justified"
  echo
  echo "See: documentation/architecture/CEREBROS_BRIDGE_BOUNDARY.md"
  exit 1
fi

echo "✅ Ortex boundary check passed"
echo "   All Ortex usage is within allowed namespaces."
exit 0
