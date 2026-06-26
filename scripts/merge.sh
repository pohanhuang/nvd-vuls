#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
START_YEAR="${START_YEAR:-2002}"
END_YEAR="${END_YEAR:-2026}"
WORKSPACE="stage"
OUTPUT_FILE="${OUTPUT_FILE:-merged_nvd_feeds.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  echo "[update-nvd-feeds] $*"
}

download_feed() {
  local year="$1"
  local file="nvdcve-2.0-${year}.json.gz"
  local url="${BASE_URL}/${file}"
  local out="${WORKSPACE}/${file}"
  local wget_args=(-O "$out" "$url")
  if [ -n "${NVD_KEY:-}" ]; then
    wget_args=(--header="apiKey: ${NVD_KEY}" "${wget_args[@]}")
  fi
  log "Downloading file=$file year=$year"
  if wget "${wget_args[@]}"; then
    if [ -s "$out" ]; then
      local size
      size=$(du -h "$out" | awk '{print $1}')
      log "DOWNLOAD_OK file=$file size=$size"
      return 0
    fi
  fi
  log "DOWNLOAD_FAILED file=$file"
  rm -f "$out"
  return 1
}

log "Starting NVD feeds update"
log "START_YEAR=$START_YEAR"
log "END_YEAR=$END_YEAR"
log "WORKSPACE=$WORKSPACE"
log "OUTPUT_FILE=$OUTPUT_FILE"
mkdir -p "$WORKSPACE"
for year in $(seq "$START_YEAR" "$END_YEAR"); do
  download_feed "$year"
done
log "Running post-process pack step"
WORKSPACE="$WORKSPACE" OUTPUT_FILE="$OUTPUT_FILE" "$SCRIPT_DIR/pack"
log "Update complete"


#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="${WORKSPACE:-nvd-feeds}"
OUTPUT_FILE="${OUTPUT_FILE:-merged_nvd_feeds.json}"
TEMP_DIR="${TEMP_DIR:-workspace}"
VULNS_FILE="$TEMP_DIR/all_vulns.jsonl"
log() {
    echo "[pack] $*"
}
write_output() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "$1=$2" >> "$GITHUB_OUTPUT"
    fi
}
log "Starting NVD feeds merge"
log "WORKSPACE=$WORKSPACE"
log "OUTPUT_FILE=$OUTPUT_FILE"
log "TEMP_DIR=$TEMP_DIR"
mkdir -p "$TEMP_DIR" "$(dirname "$OUTPUT_FILE")"
: > "$VULNS_FILE"
FILE_COUNT=$(find "$WORKSPACE" -name "nvdcve-2.0-*.json.gz" | wc -l | tr -d ' ')
log "FILE_COUNT=$FILE_COUNT"
if [ "$FILE_COUNT" -eq 0 ]; then
    log "No NVD feed files found. Nothing to merge."
    exit 1
fi
log "Extracting vulnerabilities"
COUNTER=0
for file in $(ls "$WORKSPACE"/nvdcve-2.0-*.json.gz | sort -V); do
    COUNTER=$((COUNTER + 1))
    FILE_NAME=$(basename "$file")
    YEAR=$(echo "$FILE_NAME" | sed -E 's/.*-([0-9]{4})\.json\.gz/\1/')
    log "PROCESSING_FILE index=$COUNTER total=$FILE_COUNT year=$YEAR file=$FILE_NAME"
    gzip -cd "$file" | jq -c '.vulnerabilities[]' >> "$VULNS_FILE"
    CURRENT_TOTAL=$(wc -l < "$VULNS_FILE" | tr -d ' ')
    log "PROGRESS files_processed=$COUNTER vulnerabilities=$CURRENT_TOTAL"
done
log "Building merged JSON"
FIRST_FILE=$(ls "$WORKSPACE"/nvdcve-2.0-*.json.gz | sort -V | head -1)
FORMAT=$(gzip -cd "$FIRST_FILE" | jq -r '.format')
VERSION=$(gzip -cd "$FIRST_FILE" | jq -r '.version')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3N")
TOTAL_VULNS=$(wc -l < "$VULNS_FILE" | tr -d ' ')
log "TOTAL_VULNERABILITIES=$TOTAL_VULNS"
{
    echo "{"
    echo "  \"resultsPerPage\": $TOTAL_VULNS,"
    echo "  \"startIndex\": 0,"
    echo "  \"totalResults\": $TOTAL_VULNS,"
    echo "  \"format\": \"$FORMAT\","
    echo "  \"version\": \"$VERSION\","
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"vulnerabilities\": ["
    awk '{
        if (NR > 1) print ","
        printf "%s", $0
    }' "$VULNS_FILE"
    echo ""
    echo "  ]"
    echo "}"
} > "$OUTPUT_FILE"
rm -rf "$TEMP_DIR"
OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')
write_output "output_file" "$OUTPUT_FILE"
write_output "total_vulnerabilities" "$TOTAL_VULNS"
write_output "output_size" "$OUTPUT_SIZE"
log "OUTPUT_FILE=$OUTPUT_FILE"
log "OUTPUT_SIZE=$OUTPUT_SIZE"
log "Merge complete"


merge 起來是可以的嗎