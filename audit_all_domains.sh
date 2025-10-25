#!/bin/bash

# Thunderline Domain Audit Script
# ================================
# Systematically audits all domains for resource counts, saga infrastructure,
# cross-domain integration, and test coverage.
#
# Usage: ./audit_all_domains.sh > audit_report_$(date +%Y%m%d).txt

echo "THUNDERLINE DOMAIN AUDIT REPORT"
echo "================================"
echo "Date: $(date)"
echo "Method: File-by-file systematic count"
echo ""
echo "Baseline: THUNDERLINE_DOMAIN_CATALOG.md"
echo ""

# Check if we're in the right directory
if [ ! -d "lib/thunderline" ]; then
    echo "ERROR: Must be run from Thunderline project root"
    exit 1
fi

# Summary counters
total_domains=0
total_resources=0
total_sagas=0
total_tests=0

echo "DOMAIN INVENTORY"
echo "================"
echo ""

for domain in lib/thunderline/*/; do
    domain_name=$(basename "$domain")
    
    # Skip if it's a file, not a directory
    [ -d "$domain" ] || continue
    
    total_domains=$((total_domains + 1))
    
    echo "### $domain_name"
    
    # Count resources (Ash resources in resources/ directory)
    resource_count=$(find "$domain/resources" -name "*.ex" -type f 2>/dev/null | wc -l)
    echo "  Resources: $resource_count"
    total_resources=$((total_resources + resource_count))
    
    # Count sagas (ThunderBolt specific, but check all)
    saga_count=$(find "$domain" -path "*/sagas/*.ex" -type f 2>/dev/null | wc -l)
    if [ $saga_count -gt 0 ]; then
        echo "  Sagas: $saga_count"
        total_sagas=$((total_sagas + saga_count))
        
        # Show saga complexity
        echo "  Saga files:"
        for saga in $(find "$domain" -path "*/sagas/*.ex" -type f 2>/dev/null); do
            lines=$(wc -l < "$saga")
            echo "    - $(basename "$saga"): $lines lines"
        done
    fi
    
    # Count total .ex files (for utility domains)
    total_files=$(find "$domain" -name "*.ex" -type f 2>/dev/null | wc -l)
    if [ $resource_count -eq 0 ] && [ $total_files -gt 0 ]; then
        echo "  Type: Utility domain ($total_files .ex files)"
    fi
    
    # Cross-domain references (production integration indicator)
    refs=$(grep -r "alias Thunderline\.$domain_name\." lib/thunderline/ --include="*.ex" 2>/dev/null | \
           grep -v "lib/thunderline/$domain_name/" | wc -l)
    echo "  Cross-domain refs: $refs"
    
    # Test files
    tests=$(find test -path "*$domain_name*" -name "*.exs" -type f 2>/dev/null | wc -l)
    echo "  Test files: $tests"
    total_tests=$((total_tests + tests))
    
    # Telemetry (production indicator)
    telemetry=$(grep -r "telemetry" "$domain" --include="*.ex" 2>/dev/null | wc -l)
    if [ $telemetry -gt 0 ]; then
        echo "  Telemetry calls: $telemetry"
    fi
    
    # Production classification hints
    if [ $refs -ge 5 ] && [ $tests -gt 0 ] && [ $telemetry -gt 0 ]; then
        echo "  Classification: ✅ Likely PRODUCTION (high integration)"
    elif [ $resource_count -eq 0 ] && [ $total_files -gt 0 ]; then
        echo "  Classification: 🛠️ UTILITY DOMAIN"
    elif [ $refs -lt 2 ] && [ $tests -eq 0 ]; then
        echo "  Classification: ⚠️ Possibly EXPERIMENTAL (low integration)"
    fi
    
    echo ""
done

echo "SUMMARY STATISTICS"
echo "=================="
echo ""
echo "Total Domains: $total_domains"
echo "Total Ash Resources: $total_resources"
echo "Total Saga Files: $total_sagas"
echo "Total Test Files: $total_tests"
echo ""

echo "NEXT STEPS"
echo "=========="
echo ""
echo "1. Compare resource counts with THUNDERLINE_DOMAIN_CATALOG.md"
echo "2. Read code for domains marked 'Possibly EXPERIMENTAL'"
echo "3. Verify saga infrastructure in ThunderBolt"
echo "4. Check cross-domain references for integration proof"
echo "5. Document findings in CODEBASE_AUDIT_YYYY_MM.md"
echo ""
echo "⚠️  Remember: This is discovery only. Read actual code before"
echo "    classifying production status. See HOW_TO_AUDIT.md for full process."
