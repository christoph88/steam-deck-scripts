#!/bin/bash

# PSX to CHD Batch Converter for Steam Deck/EmuDeck
# Uses local chdman5 tool from chdconv directory

# Configuration - Edit these paths for your setup
EMULATION_BASE="${EMULATION_BASE:-/run/media/deck/Christoph/Emulation}"
TOOLS_DIR="${TOOLS_DIR:-$EMULATION_BASE/tools}"
CHDMAN="${CHDMAN:-$TOOLS_DIR/chdconv/chdman5}"
SOURCE_DIR="${SOURCE_DIR:-$EMULATION_BASE/roms/psx}"
OUTPUT_DIR="${OUTPUT_DIR:-$EMULATION_BASE/roms/psx_chd}"
BACKUP_DIR="${BACKUP_DIR:-$EMULATION_BASE/roms/psx_backup}"
LOG_DIR="${LOG_DIR:-$TOOLS_DIR/chdconv}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
LOGFILE="$LOG_DIR/psx_conversion_$TIMESTAMP.log"

# Function to log messages
log() {
    echo -e "$1" | tee -a "$LOGFILE"
}

echo "========================================"
log "${BLUE}PSX to CHD Batch Converter${NC}"
echo "========================================"
log "Started: $(date)"
log ""

# Check if chdman5 exists and make it executable
if [[ ! -f "$CHDMAN" ]]; then
    log "${RED}Error: chdman5 not found at $CHDMAN${NC}"
    exit 1
fi
chmod +x "$CHDMAN"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    log "${RED}Error: Source directory not found: $SOURCE_DIR${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
log "Output directory: $OUTPUT_DIR"
log "Log file: $LOGFILE"
log ""

# Counter variables
total=0
success=0
failed=0
skipped=0

# Array to store failed conversions
declare -a failed_files
declare -a cue_files_array

# Find all .cue files recursively and count them first
log "${YELLOW}Scanning for .cue files in $SOURCE_DIR...${NC}"
while IFS= read -r -d '' cue_file; do
    cue_files_array+=("$cue_file")
done < <(find "$SOURCE_DIR" -type f -name "*.cue" -print0 | sort -z)

total_files="${#cue_files_array[@]}"
log "Found $total_files .cue files to process"
log ""

# Process each file
current=0
while [[ $current -lt $total_files ]]; do
    cue_file="${cue_files_array[$current]}"
    ((current++))
    ((total++)
    
    # Calculate percentage
    percentage=$((current * 100 / total_files)))
    
    # Get the filename without extension
    filename=$(basename "$cue_file" .cue)
    
    # Output CHD filename (flat structure in output dir)
    chd_file="$OUTPUT_DIR/${filename}.chd"
    
    # Skip if CHD already exists
    if [[ -f "$chd_file" ]]; then
        log "${BLUE}[$current/$total_files - ${percentage}%] Skipped (already exists): ${filename}.chd${NC}"
        ((skipped++))
        continue
    fi
    
    log "${YELLOW}[$current/$total_files - ${percentage}%] Converting: $filename${NC}"
    log "   Source: $cue_file"
    
    # Convert to CHD using createcd flag (show progress in real-time)
    if "$CHDMAN" createcd -i "$cue_file" -o "$chd_file" 2>&1 | tee -a "$LOGFILE"; then
        log "${GREEN}   ✓ Success: ${filename}.chd${NC}"
        ((success++))
    else
        log "${RED}   ✗ Failed: $filename${NC}"
        failed_files+=("$cue_file")
        ((failed++))
        # Remove incomplete CHD file
        rm -f "$chd_file"
    fi
    log ""
    
done

# Summary
log ""
log "========================================"
log "${BLUE}Conversion Complete!${NC}"
log "========================================"
log "Total files found: $total"
log "${GREEN}Successful conversions: $success${NC}"
log "${BLUE}Skipped (already converted): $skipped${NC}"
log "${RED}Failed conversions: $failed${NC}"
log ""
log "CHD files location: $OUTPUT_DIR"
log "Log file: $LOGFILE"
log ""

# List failed files if any
if [[ $failed -gt 0 ]]; then
    log "${RED}Failed files:${NC}"
    for failed_file in "${failed_files[@]}"; do
        log "  - $failed_file"
    done
    log ""
fi

# Show next steps if successful conversions
if [[ $success -gt 0 ]]; then
    log "${GREEN}Next steps:${NC}"
    log "1. Test CHD files in DuckStation/RetroArch"
    log "2. Backup originals (IMPORTANT!):"
    log "   mkdir -p '$BACKUP_DIR'"
    log "   rsync -av '$SOURCE_DIR/' '$BACKUP_DIR/'"
    log ""
    log "3. Move CHD files to main PSX directory:"
    log "   mv '$OUTPUT_DIR'/*.chd '$SOURCE_DIR/'"
    log ""
    log "4. Clean up old BIN/CUE files after verifying CHDs work:"
    log "   rm -rf '$SOURCE_DIR'/*/  # Remove all subdirectories"
    log ""
fi

log "Completed: $(date)"
log "========================================"
