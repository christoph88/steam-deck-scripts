#!/bin/bash

# Usage: ./download_roms.sh [url_list_file] [outputdir]
# If url_list_file is omitted or blank, defaults to vimms_urls.txt

URL_LIST_FILE="${1:-}"
OUTPUT_DIR="${2:-}"

# Default URL list filename
DEFAULT_LIST="vimms_urls.txt"

# Ask/assign if not given
if [[ -z "$URL_LIST_FILE" ]]; then
  read -rp "Enter the path to your list of URLs [${DEFAULT_LIST}]: " URL_LIST_FILE
  # If user just presses enter, use default
  URL_LIST_FILE="${URL_LIST_FILE:-$DEFAULT_LIST}"
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  read -rp "Enter the output directory: " OUTPUT_DIR
fi

if [[ ! -f "$URL_LIST_FILE" ]]; then
  echo "The file '$URL_LIST_FILE' does not exist."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"

COUNTER=1

while IFS= read -r url || [ -n "$url" ]; do
  # skip empty lines
  if [[ -z "$url" ]]; then continue; fi
  output_file="${OUTPUT_DIR}/download_${COUNTER}"
  echo "Downloading: $url -> $output_file"
  curl -L -o "$output_file" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" \
    -H "Accept-Encoding: gzip, deflate, br" \
    -H "Connection: keep-alive" \
    -H "User-Agent: $USER_AGENT" \
    "$url"
  ((COUNTER++))
done < "$URL_LIST_FILE"

echo "All downloads complete."
