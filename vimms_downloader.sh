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
  echo "Fetching file information..."
  
  # Get total size in bytes using a HEAD request
  total_bytes=$(curl -sI -L -b "$COOKIE_FILE" -H "User-Agent: $USER_AGENT" -H "Referer: $url" "$dl_url" | grep -i "Content-Length" | head -1 | awk '{print $2}' | tr -d '\r')
  total_bytes=${total_bytes:-0}

  # Use a temporary file to check for success before naming it
  temp_file="temp_download.zip"
  rm -f "$temp_file"

  # Start download in background
  # We use --silent to hide curl's own progress meter
  # We use --write-out to capture the status code at the end
  curl -L --silent -o "$temp_file" -w "%{http_code}" \
    -b "$COOKIE_FILE" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7" \
    -H "Accept-Encoding: gzip, deflate, br, zstd" \
    -H "Accept-Language: en-US,en;q=0.9" \
    -H "Connection: keep-alive" \
    -H "Referer: $url" \
    -H "Sec-Fetch-Dest: document" \
    -H "Sec-Fetch-Mode: navigate" \
    -H "Sec-Fetch-Site: same-site" \
    -H "Sec-Fetch-User: ?1" \
    -H "Upgrade-Insecure-Requests: 1" \
    -H "User-Agent: $USER_AGENT" \
    "$dl_url" > .status_code &
  
  curl_pid=$!
  start_time=$(date +%s)
  last_bytes=0
  
  # Monitoring loop
  while kill -0 "$curl_pid" 2>/dev/null; do
    sleep 1
    
    if [[ -f "$temp_file" ]]; then
      # Get current size
      current_bytes=$(stat -f %z "$temp_file" 2>/dev/null || stat -c %s "$temp_file" 2>/dev/null || echo 0)
      
      # Calculate speed
      now=$(date +%s)
      elapsed=$((now - start_time))
      [[ $elapsed -eq 0 ]] && elapsed=1
      
      speed_bytes=$(( (current_bytes - last_bytes) ))
      speed_fmt=$(numfmt --to=iec-i --suffix=B/s "$speed_bytes" 2>/dev/null || echo "$((speed_bytes/1024)) KiB/s")
      last_bytes=$current_bytes
      
      # Progress calculation
      if [[ "$total_bytes" -gt 0 ]]; then
        percent=$(( current_bytes * 100 / total_bytes ))
        bar_len=20
        filled=$(( percent * bar_len / 100 ))
        empty=$(( bar_len - filled ))
        bar=$(printf "%${filled}s" | tr ' ' '#')$(printf "%${empty}s" | tr ' ' '-')
        
        current_fmt=$(numfmt --to=iec-i --suffix=B "$current_bytes" 2>/dev/null || echo "$((current_bytes/1024/1024)) MiB")
        total_fmt=$(numfmt --to=iec-i --suffix=B "$total_bytes" 2>/dev/null || echo "$((total_bytes/1024/1024)) MiB")
        
        printf "\r[%s] %3d%% | %s / %s | %s    " "$bar" "$percent" "$current_fmt" "$total_fmt" "$speed_fmt"
      else
        current_fmt=$(numfmt --to=iec-i --suffix=B "$current_bytes" 2>/dev/null || echo "$((current_bytes/1024/1024)) MiB")
        printf "\rDownloading: %s | %s    " "$current_fmt" "$speed_fmt"
      fi
    fi
  done
  echo "" # New line after progress finishes

  http_status=$(cat .status_code)
  rm -f .status_code

  if [[ "$http_status" -eq 200 ]]; then
    # Try to extract filename from the headers
    remote_filename=$(curl -s -I -b "$COOKIE_FILE" -H "Referer: $url" -H "User-Agent: $USER_AGENT" "$dl_url" | grep -ie "content-disposition" | sed -n 's/.*filename="\(.*\)".*/\1/p' | head -1)
    
    final_filename="${remote_filename:-$clean_title.zip}"
    final_filename=$(echo "$final_filename" | tr -d '\r' | sed 's/[^a-zA-Z0-9._() -]//g')
    
    mv "$temp_file" "$final_filename"
    echo "Success: Saved as $final_filename"

    # Log to history
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $clean_title | $url" >> "../download_history.log"

    # Comment out from source file
    # We use sed to add a # in front of the specific URL line
    # ESCAPED_URL handles special characters in the URL for sed
    ESCAPED_URL=$(echo "$url" | sed 's/[\/&]/\\&/g')
    sed -i.bak "s/^${ESCAPED_URL}/#&/" "$URL_LIST_FILE" && rm "${URL_LIST_FILE}.bak"

  elif [[ "$http_status" -eq 429 ]]; then
    rm -f "$temp_file"
    echo "Error: HTTP 429 (Too Many Requests). Anti-bot protection is active."
    echo "Wait 30-60 minutes for your IP to cool down."
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
