#!/bin/bash

# PSX CHD Cleanup Script for Steam Deck/EmuDeck
# Moves CHD files to main PSX directory and cleans up old BIN/CUE files

# Configuration - Edit these paths for your setup
EMULATION_BASE="${EMULATION_BASE:-/run/media/deck/Christoph/Emulation}"
TOOLS_DIR="${TOOLS_DIR:-$EMULATION_BASE/tools}"
PSX_DIR="${PSX_DIR:-$EMULATION_BASE/roms/psx}"
CHD_DIR="${CHD_DIR:-$EMULATION_BASE/roms/psx_chd}"
BACKUP_DIR="${BACKUP_DIR:-$EMULATION_BASE/roms/psx_backup}"
LOG_DIR="${LOG_DIR:-$TOOLS_DIR/chdconv}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
LOGFILE="$LOG_DIR/psx_cleanup_$TIMESTAMP.log"
mkdir -p "$LOG_DIR"

# Function to log messages
log() {
    echo -e "$1" | tee -a "$LOGFILE"
}

echo "========================================"
log "${BLUE}PSX CHD Cleanup Script${NC}"
echo "========================================"
log "Started: $(date)"
log ""

# Verify directories exist
if [[ ! -d "$PSX_DIR" ]]; then
    log "${RED}Error: PSX directory not found: $PSX_DIR${NC}"
    exit 1
fi

if [[ ! -d "$CHD_DIR" ]]; then
    log "${RED}Error: CHD directory not found: $CHD_DIR${NC}"
    log "Nothing to clean up - no CHD files converted yet."
    exit 1
fi

# Count CHD files
chd_count=$(find "$CHD_DIR" -maxdepth 1 -type f -name "*.chd" | wc -l)
if [[ $chd_count -eq 0 ]]; then
    log "${YELLOW}No CHD files found in $CHD_DIR${NC}"
    log "Nothing to do."
    exit 0
fi

log "Found ${CYAN}$chd_count${NC} CHD files in $CHD_DIR"
log ""

# Ask for confirmation
log "${YELLOW}This script will:${NC}"
log "1. Move CHD files from $CHD_DIR to $PSX_DIR"
log "2. Create backup of original files to $BACKUP_DIR (optional)"
log "3. Delete subdirectories containing BIN/CUE files"
log "4. Clean up leftover files"
log ""
log "${RED}WARNING: This will delete original BIN/CUE files!${NC}"
log ""

read -p "Do you want to create a backup first? (y/n): " backup_choice
log "Backup choice: $backup_choice"
log ""

if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
    log "${CYAN}Creating backup...${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        log "${YELLOW}Backup directory already exists. Skipping backup to avoid overwriting.${NC}"
        read -p "Continue without backup? (y/n): " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            log "Cancelled by user."
            exit 0
        fi
    else
        log "Backing up $PSX_DIR to $BACKUP_DIR..."
        if rsync -av --info=progress2 "$PSX_DIR/" "$BACKUP_DIR/" 2>&1 | tee -a "$LOGFILE"; then
            log "${GREEN}✓ Backup complete${NC}"
        else
            log "${RED}✗ Backup failed!${NC}"
            exit 1
        fi
    fi
    log ""
fi

read -p "Continue with cleanup? (y/n): " continue_choice
log "Continue choice: $continue_choice"
if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
    log "Cancelled by user."
    exit 0
fi
log ""

# Step 1: Move CHD files
log "${CYAN}Step 1: Moving CHD files to $PSX_DIR${NC}"
moved=0
failed_moves=0

while IFS= read -r -d '' chd_file; do
    filename=$(basename "$chd_file")
    destination="$PSX_DIR/$filename"
    
    if [[ -f "$destination" ]]; then
        log "${YELLOW}Skipped (already exists): $filename${NC}"
    else
        if mv "$chd_file" "$destination"; then
            log "${GREEN}✓ Moved: $filename${NC}"
            ((moved++))
        else
            log "${RED}✗ Failed to move: $filename${NC}"
            ((failed_moves++))
        fi
    fi
done < <(find "$CHD_DIR" -maxdepth 1 -type f -name "*.chd" -print0)

log ""
log "Moved: $moved files"
log "Failed: $failed_moves files"
log ""

# Step 2: Remove old subdirectories with BIN/CUE files
log "${CYAN}Step 2: Removing subdirectories with BIN/CUE files${NC}"
removed_dirs=0

while IFS= read -r dir; do
    if [[ -d "$dir" ]]; then
        dir_name=$(basename "$dir")
        log "Removing directory: $dir_name"
        if rm -rf "$dir"; then
            log "${GREEN}✓ Deleted: $dir_name${NC}"
            ((removed_dirs++))
        else
            log "${RED}✗ Failed to delete: $dir_name${NC}"
        fi
    fi
done < <(find "$PSX_DIR" -mindepth 1 -maxdepth 1 -type d)

log ""
log "Removed: $removed_dirs directories"
log ""

# Step 3: Clean up leftover files (m3u, txt, etc.)
log "${CYAN}Step 3: Cleaning up leftover files${NC}"
cleaned=0

# Remove .m3u files if they reference .cue files
while IFS= read -r -d '' m3u_file; do
    if grep -q "\.cue" "$m3u_file" 2>/dev/null; then
        filename=$(basename "$m3u_file")
        log "Removing obsolete m3u: $filename"
        rm -f "$m3u_file"
        ((cleaned++))
    fi
done < <(find "$PSX_DIR" -maxdepth 1 -type f -name "*.m3u" -print0)

# Remove any remaining .cue files in root
while IFS= read -r -d '' cue_file; do
    filename=$(basename "$cue_file")
    log "Removing leftover cue: $filename"
    rm -f "$cue_file"
    ((cleaned++))
done < <(find "$PSX_DIR" -maxdepth 1 -type f -name "*.cue" -print0)

log ""
log "Cleaned: $cleaned files"
log ""

# Step 4: Remove empty CHD directory if empty
if [[ -d "$CHD_DIR" ]]; then
    remaining=$(find "$CHD_DIR" -mindepth 1 | wc -l)
    if [[ $remaining -eq 0 ]]; then
        log "${CYAN}Removing empty CHD directory${NC}"
        rmdir "$CHD_DIR"
        log "${GREEN}✓ Removed empty directory: $CHD_DIR${NC}"
    else
        log "${YELLOW}CHD directory not empty, keeping it${NC}"
    fi
fi
log ""

# Summary
log "========================================"
log "${BLUE}Cleanup Complete!${NC}"
log "========================================"
log "CHD files moved: $moved"
log "Directories removed: $removed_dirs"
log "Files cleaned up: $cleaned"
log ""
log "PSX directory: $PSX_DIR"
log "Log file: $LOGFILE"
log ""

if [[ "$backup_choice" =~ ^[Yy]$ ]] && [[ -d "$BACKUP_DIR" ]]; then
    log "${GREEN}✓ Backup available at: $BACKUP_DIR${NC}"
    log ""
fi

log "${GREEN}Your PSX library is now ready with CHD files!${NC}"
log "You can now play games in DuckStation/RetroArch."
log ""
log "Completed: $(date)"
log "========================================"
