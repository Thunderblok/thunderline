#!/bin/bash
# Migration script to move ML runtime files to proper location under thunderbolt/
# This fixes the namespace/location mismatch for Phase 3.5 ML components

set -e  # Exit on error

echo "🔄 Migrating ML files to thunderbolt/ml/ directory..."

# Create target directory if it doesn't exist
mkdir -p lib/thunderline/thunderbolt/ml

# Move ML files to proper location
echo "  📦 Moving controller.ex..."
mv lib/thunderline/ml/controller.ex lib/thunderline/thunderbolt/ml/controller.ex

echo "  📦 Moving parzen.ex..."
mv lib/thunderline/ml/parzen.ex lib/thunderline/thunderbolt/ml/parzen.ex

echo "  📦 Moving sla_selector.ex..."
mv lib/thunderline/ml/sla_selector.ex lib/thunderline/thunderbolt/ml/sla_selector.ex

# Remove empty ml/ directory
echo "  🗑️  Removing empty ml/ directory..."
rmdir lib/thunderline/ml

echo "✅ Migration complete!"
echo ""
echo "Files moved:"
echo "  lib/thunderline/ml/controller.ex    → lib/thunderline/thunderbolt/ml/controller.ex"
echo "  lib/thunderline/ml/parzen.ex        → lib/thunderline/thunderbolt/ml/parzen.ex"
echo "  lib/thunderline/ml/sla_selector.ex  → lib/thunderline/thunderbolt/ml/sla_selector.ex"
echo ""
echo "⚠️  Next steps:"
echo "  1. Run: mix compile"
echo "  2. Run: mix test"
echo "  3. Git commit the changes"
