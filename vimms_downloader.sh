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

# Cookie file to persist session
COOKIE_FILE="cookies.txt"
# Clear cookies from previous runs
rm -f "$COOKIE_FILE"

USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

echo "Moving to: $ABS_OUTPUT_DIR"
cd "$ABS_OUTPUT_DIR" || exit 1

echo "Reading URLs from: $URL_LIST_FILE"
while IFS= read -r url || [ -n "$url" ]; do
  # skip empty lines or comments
  [[ -z "$url" || "$url" =~ ^# ]] && continue
  
  echo "---"
  echo "Processing: $url"

  # 1. Fetch the vault page to get MediaId, Title, and Download Server
  # -c saves cookies received from the server
  page_content=$(curl -s -L -c "$COOKIE_FILE" -H "User-Agent: $USER_AGENT" "$url")
  
  # 2. Extract MediaId
  media_id=$(echo "$page_content" | grep -oE 'name="mediaId" value="[0-9]+"' | head -1 | cut -d'"' -f4)
  
  # 3. Extract Title
  title=$(echo "$page_content" | grep -oE '<title>[^<]+' | sed 's/<title>//' | sed 's/The Vault: //' | head -1)

  # 4. Extract Download Server from the form action
  form_tag=$(echo "$page_content" | grep -oE '<form[^>]+id="dl_form"[^>]+>' | head -1)
  dl_server_path=$(echo "$form_tag" | grep -oE 'action="[^"]+"' | cut -d'"' -f2)
  
  # Handle empty extraction or missing host
  if [[ -z "$dl_server_path" ]]; then
    dl_url="https://dl3.vimm.net/?mediaId=${media_id}"
  else
    # Handle relative or protocol-relative URLs
    if [[ "$dl_server_path" == //* ]]; then
      dl_url="https:${dl_server_path}"
    elif [[ "$dl_server_path" == /* ]]; then
      dl_url="https://vimm.net${dl_server_path}"
    else
      dl_url="$dl_server_path"
    fi

    # Append mediaId if not present
    if [[ "$dl_url" != *"mediaId="* ]]; then
      if [[ "$dl_url" == *"?"* ]]; then
        dl_url="${dl_url}&mediaId=${media_id}"
      else
        dl_url="${dl_url}?mediaId=${media_id}"
      fi
    fi
  fi

  # Clean title from HTML entities
  clean_title=$(echo "$title" | sed 's/&#039;/'\''/g' | sed 's/&amp;/\&/g' | sed 's/&quot;/\"/g')

  if [[ -z "$media_id" ]]; then
    echo "Error: Could not find mediaId for $url. Skipping..."
    continue
  fi

  echo "Found: $clean_title (MediaID: $media_id)"
  
  # 4. Mimic human "wait time" on page before clicking download
  echo "Preparing download..."
  sleep 3

  echo "Downloading from: $dl_url"
  
  # 5. Perform the actual download
  # Simplified headers based on successful HAR, but removing potentially flagged ones
  echo "Downloading..."
  
  # Use a temporary file to check for success before naming it
  temp_file="temp_download.zip"
  
  http_status=$(curl -L -w "%{http_code}" -o "$temp_file" \
    -b "$COOKIE_FILE" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Referer: $url" \
    -H "User-Agent: $USER_AGENT" \
    "$dl_url")

  if [[ "$http_status" -eq 200 ]]; then
    # Try to extract filename from the headers of the actual download
    # We'll use curl -I to get just the headers of the final URL
    remote_filename=$(curl -s -I -b "$COOKIE_FILE" -H "Referer: $url" -H "User-Agent: $USER_AGENT" "$dl_url" | grep -ie "content-disposition" | sed -n 's/.*filename="\(.*\)".*/\1/p' | head -1)
    
    # Fallback to a safe name if extraction fails
    final_filename="${remote_filename:-$clean_title.zip}"
    # Remove any characters that might be bad for filenames
    final_filename=$(echo "$final_filename" | tr -d '\r' | sed 's/[^a-zA-Z0-9._() -]//g')
    
    mv "$temp_file" "$final_filename"
    echo "Success: Saved as $final_filename"
  elif [[ "$http_status" -eq 429 ]]; then
    rm -f "$temp_file"
    echo "Error: HTTP 429 (Too Many Requests). Vimm's Lair anti-bot protection is active."
    echo "Try again in 30-60 minutes, or use a VPN/different network."
  else
    rm -f "$temp_file"
    echo "Error: Download failed for $clean_title (HTTP Status: $http_status)"
  fi

  # 6. Polite delay - Vimm's is VERY sensitive
  echo "---"
  sleep 10
done < "$URL_LIST_FILE"

echo "---"
echo "All downloads complete."
