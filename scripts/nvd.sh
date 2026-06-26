#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
START_YEAR="${START_YEAR:-2002}"
END_YEAR="${END_YEAR:-2026}"
FEED_DIR="feeds"
OUTPUT_FILE="nvd_feeds.json.gz"
TEMP_DIR=$(mktemp -d)
VULNS_FILE="$TEMP_DIR/all_vulns.jsonl"

log() {
  echo "[update-nvd-feeds] $*"
}

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

download_feed() {
  local year="$1"
  local file="nvdcve-2.0-${year}.json.gz"
  local url="${BASE_URL}/${file}"
  local out="${FEED_DIR}/${file}"
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

merge_nvd_feeds() {
  local file_count
  file_count=$(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | wc -l | tr -d ' ')
  log "FILE_COUNT=$file_count"

  if [ "$file_count" -eq 0 ]; then
    log "No NVD feed files found. Nothing to merge."
    exit 1
  fi

  log "Extracting vulnerabilities"
  local counter=0
  while IFS= read -r file; do
    counter=$((counter + 1))
    local file_name year
    file_name=$(basename "$file")
    year=$(echo "$file_name" | sed -E 's/.*-([0-9]{4})\.json\.gz/\1/')
    log "PROCESSING_FILE index=$counter total=$file_count year=$year file=$file_name"
    gzip -cd "$file" | jq -c '.vulnerabilities[]' >> "$VULNS_FILE"
    local current_total
    current_total=$(wc -l < "$VULNS_FILE" | tr -d ' ')
    log "PROGRESS files_processed=$counter vulnerabilities=$current_total"
  done < <(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | sort -V)

  log "Building merged JSON"
  local first_file format version timestamp
  first_file=$(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | sort -V | head -1)
  local meta
  meta=$(gzip -cd "$first_file")
  format=$(echo "$meta" | jq -r '.format')
  version=$(echo "$meta" | jq -r '.version')
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3N")
  local total_vulns
  total_vulns=$(wc -l < "$VULNS_FILE" | tr -d ' ')
  log "TOTAL_VULNERABILITIES=$total_vulns"

  {
    echo "{"
    echo "  \"resultsPerPage\": $total_vulns,"
    echo "  \"startIndex\": 0,"
    echo "  \"totalResults\": $total_vulns,"
    echo "  \"format\": \"$format\","
    echo "  \"version\": \"$version\","
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"vulnerabilities\": ["
    awk '{
      if (NR > 1) print ","
      printf "%s", $0
    }' "$VULNS_FILE"
    echo ""
    echo "  ]"
    echo "}"
  } | gzip > "$OUTPUT_FILE"
}

clean_up() {
  rm -rf "$FEED_DIR" "$TEMP_DIR"
}

trap clean_up EXIT

log "Starting NVD feeds update"
log "START_YEAR=$START_YEAR"
log "END_YEAR=$END_YEAR"
log "FEED_DIR=$FEED_DIR"
log "OUTPUT_FILE=$OUTPUT_FILE"

mkdir -p "$FEED_DIR"

for year in $(seq "$START_YEAR" "$END_YEAR"); do
  download_feed "$year"
done

merge_nvd_feeds

TOTAL_VULNS=$(gzip -cd "$OUTPUT_FILE" | jq '.totalResults')
OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')

write_output "output_file" "$OUTPUT_FILE"
write_output "total_vulnerabilities" "$TOTAL_VULNS"
write_output "output_size" "$OUTPUT_SIZE"
log "OUTPUT_FILE=$OUTPUT_FILE"
log "OUTPUT_SIZE=$OUTPUT_SIZE"
log "Update complete"