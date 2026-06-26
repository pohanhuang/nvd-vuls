#!/usr/bin/env bash
set -euo pipefail

echo "=== Testing NVD Pipeline Locally ==="

# Clean up previous test
rm -rf feeds merged_nvd_feeds.json.gz* nvd-feeds.oci-ref

# Step 1: Download and merge (only 2002 for fast test)
echo ""
echo "Step 1: Running scripts/nvd..."
START_YEAR=2002 END_YEAR=2002 OUTPUT_FILE=merged_nvd_feeds.json.gz bash scripts/nvd

# Check output
echo ""
echo "Step 2: Verifying output..."
if [ -f "merged_nvd_feeds.json.gz" ]; then
    SIZE=$(du -h merged_nvd_feeds.json.gz | awk '{print $1}')
    VULNS=$(gzip -cd merged_nvd_feeds.json.gz | jq '.totalResults')
    echo "✓ Output file: merged_nvd_feeds.json.gz ($SIZE)"
    echo "✓ Total vulnerabilities: $VULNS"
else
    echo "✗ Output file not found!"
    exit 1
fi

if [ -d "feeds" ]; then
    FEED_COUNT=$(find feeds -name "*.json.gz" | wc -l)
    echo "✓ Feed directory exists with $FEED_COUNT files"
else
    echo "✗ Feed directory not found!"
    exit 1
fi

echo ""
echo "=== All checks passed! ==="
echo ""
echo "Generated files:"
ls -lh feeds/ merged_nvd_feeds.json.gz 2>/dev/null || true
