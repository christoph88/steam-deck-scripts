#!/bin/bash

# Usage: ./download_roms.sh [url_list_file] [outputdir]
# If url_list_file is omitted or blank, defaults to vimms_urls.txt

URL_LIST_FILE="${1:-}"
OUTPUT_DIR="${2:-}"

# Default URL list filename
DEFAULT_LIST="vimms_urls.txt"

# Function to get absolute path
get_abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    echo "$(cd "$path" && pwd)"
  elif [[ -f "$path" ]]; then
    echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
  else
    # For paths that don't exist yet
    echo "$(pwd)/$path"
  fi
}

# Ask/assign if not given
if [[ -z "$URL_LIST_FILE" ]]; then
  # -e enables readline (Tab completion)
  read -e -p "Enter the path to your list of URLs [${DEFAULT_LIST}]: " URL_LIST_FILE
  URL_LIST_FILE="${URL_LIST_FILE:-$DEFAULT_LIST}"
fi

# Resolve URL list to absolute path BEFORE we cd
URL_LIST_FILE=$(get_abs_path "$URL_LIST_FILE")

if [[ ! -f "$URL_LIST_FILE" ]]; then
  echo "Error: The file '$URL_LIST_FILE' does not exist."
  exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  read -e -p "Enter the output directory [./downloads]: " OUTPUT_DIR
  OUTPUT_DIR="${OUTPUT_DIR:-./downloads}"
fi

# Create directory and resolve to absolute path
mkdir -p "$OUTPUT_DIR"
ABS_OUTPUT_DIR=$(get_abs_path "$OUTPUT_DIR")

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"

echo "Moving to: $ABS_OUTPUT_DIR"
cd "$ABS_OUTPUT_DIR" || exit 1

echo "Reading URLs from: $URL_LIST_FILE"
while IFS= read -r url || [ -n "$url" ]; do
  # skip empty lines or comments
  [[ -z "$url" || "$url" =~ ^# ]] && continue
  
  echo "---"
  echo "Processing: $url"

  # 1. Fetch the vault page to get MediaId and Title
  page_content=$(curl -s -L -H "User-Agent: $USER_AGENT" "$url")
  
  # 2. Extract MediaId
  media_id=$(echo "$page_content" | grep -oE 'name="mediaId" value="[0-9]+"' | head -1 | cut -d'"' -f4)
  
  # 3. Extract Title (optional, for logging)
  title=$(echo "$page_content" | grep -oE '<title>[^<]+' | sed 's/<title>//' | sed 's/The Vault: //' | head -1)

  if [[ -z "$media_id" ]]; then
    echo "Error: Could not find mediaId for $url. Skipping..."
    continue
  fi

  echo "Downloading from: https://download2.vimm.net/download/?mediaId=$media_id"
  
  # 4. Perform the actual download
  # --write-out "%{http_code}": captures the status code
  # --silent: hides the progress bar for a cleaner output, but we keep it for now for user feedback
  # We use a temporary variable to capture the HTTP status code
  http_status=$(curl -L -J -O -w "%{http_code}" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -H "Connection: keep-alive" \
    -H "Referer: $url" \
    -H "User-Agent: $USER_AGENT" \
    "https://download2.vimm.net/download/?mediaId=$media_id")

  if [[ "$http_status" -eq 200 ]]; then
    echo "Success: Download complete for $title"
  else
    echo "Error: Download failed for $title (HTTP Status: $http_status)"
    echo "Possible reasons: Session timeout, rate limiting, or file unavailable."
  fi

  # 5. Small delay to be polite and ensure sequential ordering
  echo "---"
  sleep 2
done < "$URL_LIST_FILE"

echo "---"
echo "All downloads complete."
