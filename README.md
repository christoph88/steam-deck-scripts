# Steam Deck/EmuDeck Utility Scripts

A collection of bash scripts for managing ROM files and game conversions on Steam Deck with EmuDeck.

## Scripts Overview

### 1. psx_batch_convert.sh
**PSX to CHD Batch Converter**

Converts PlayStation (PSX) ROM files from BIN/CUE format to compressed CHD (MAME Compressed Hunks of Data) format using the chdman5 tool. CHD files significantly reduce storage space while maintaining compatibility with emulators like DuckStation and RetroArch.

#### Features
- Batch conversion of all .cue files in a directory (recursive search)
- Real-time progress tracking with percentage completion
- Skips already converted files
- Creates detailed conversion logs
- Validates chdman5 tool availability
- Tracks success/failure/skipped conversions

#### Usage
```bash
./psx_batch_convert.sh
```

#### Configuration
Edit these variables at the top of the script:
- `EMULATION_BASE`: Base emulation directory (default: `/run/media/deck/Christoph/Emulation`)
- `SOURCE_DIR`: Directory containing PSX BIN/CUE files
- `OUTPUT_DIR`: Destination for converted CHD files
- `BACKUP_DIR`: Location for backup files
- `CHDMAN`: Path to chdman5 executable

#### Output
- CHD files are created in the output directory
- Detailed logs saved to `$LOG_DIR/psx_conversion_TIMESTAMP.log`
- Summary showing total, successful, skipped, and failed conversions

---

### 2. psx_cleanup.sh
**PSX CHD Cleanup Script**

Manages the cleanup process after CHD conversion by moving converted CHD files to the main PSX directory and removing old BIN/CUE files and subdirectories.

#### Features
- Moves CHD files from conversion directory to main PSX directory
- Optional backup creation before cleanup
- Removes subdirectories containing original BIN/CUE files
- Cleans up leftover files (.m3u, .cue)
- Removes empty directories
- Interactive confirmation prompts for safety
- Detailed logging of all operations

#### Usage
```bash
./psx_cleanup.sh
```

The script will prompt you to:
1. Create a backup (recommended)
2. Confirm cleanup operation

#### Configuration
Edit these variables at the top of the script:
- `EMULATION_BASE`: Base emulation directory
- `PSX_DIR`: Main PSX ROM directory
- `CHD_DIR`: Directory with converted CHD files
- `BACKUP_DIR`: Backup destination

#### Safety Features
- Confirms before destructive operations
- Prevents overwriting existing backups
- Skips files that already exist
- Provides detailed summary of all operations

---

### 3. rom_shortcut.sh
**RetroArch Flatpak ROM Launcher**

An interactive launcher for RetroArch that simplifies running ROMs on Steam Deck. Supports SNES and N64 systems with fuzzy ROM search and automatic Flatpak permission management.

#### Features
- Interactive system selection (SNES, N64)
- Fuzzy ROM search with dropdown picker (uses fzf if available)
- Automatic Flatpak filesystem permissions for external drives
- Generates Steam shortcut commands
- Supports external drive mounts and internal storage
- Multiple invocation modes: full auto, partial auto, or fully interactive

#### Usage

**Full automation (system + ROM specified):**
```bash
./rom_shortcut.sh snes "/run/media/deck/Christoph/Emulation/roms/snes/Game.sfc"
```

**Provide system, pick ROM interactively:**
```bash
./rom_shortcut.sh snes
```

**Provide ROM path, auto-detect system:**
```bash
./rom_shortcut.sh "/path/to/rom.z64"
```

**Fully interactive:**
```bash
./rom_shortcut.sh
```

#### Supported Systems
- **SNES**: Uses `snes9x_libretro.so` core, supports .sfc, .smc files
- **N64**: Uses `mupen64plus_next_libretro.so` core, supports .z64, .n64, .v64 files

#### Requirements
- RetroArch installed as Flatpak (`org.libretro.RetroArch`)
- Required cores installed via RetroArch → Online Updater → Core Downloader
- Optional: `fzf` for enhanced fuzzy search UI

#### Configuration
Edit these variables at the top of the script:
- `APP_ID`: Flatpak app ID (default: `org.libretro.RetroArch`)
- `CORES_DIR`: RetroArch cores directory
- `SEARCH_ROOTS`: Array of directories to search for ROMs

#### Output
The script prints commands for:
- Testing in terminal
- Creating Steam shortcuts (Target + Launch Options)

---

### 4. vimms_downloader.sh
**Vimm's Lair Batch Downloader**

A utility script to batch download files from Vimm's Lair using a list of URLs. It handles the download process automatically and includes necessary headers to mimic a browser request.

#### Features
- Batch download from a text file of URLs
- Customizable output directory
- **Automatic naming**: Uses the actual ROM filename provided by the server (e.g., `Game Name (USA).zip`)
- Browser-mimicking headers to ensure successful downloads

#### Usage
```bash
./vimms_downloader.sh [url_list_file] [output_dir]
```
If arguments are omitted, the script will prompt you for them. The default URL list file is `vimms_urls.txt`.

#### Configuration
- `DEFAULT_LIST`: Default text file containing URLs (default: `vimms_urls.txt`)
- `USER_AGENT`: Custom User-Agent string for requests

#### Output
- Downloaded files are saved to the specified directory with their original filenames as provided by the server.

---

## Prerequisites

### General Requirements
- Steam Deck with EmuDeck installed
- Bash shell
- Basic file system permissions

### Script-Specific Requirements

**psx_batch_convert.sh:**
- chdman5 tool installed in `$TOOLS_DIR/chdconv/`
- Source PSX ROMs in BIN/CUE format

**psx_cleanup.sh:**
- rsync (for backup functionality)

**rom_shortcut.sh:**
- RetroArch Flatpak installed
- RetroArch cores installed for desired systems
- fzf (optional, for enhanced UI)

**vimms_downloader.sh:**
- `curl` installed
- A text file containing direct download URLs (one per line)

---

## Installation

1. Clone or download these scripts to your Steam Deck
2. Make scripts executable:
```bash
chmod +x psx_batch_convert.sh psx_cleanup.sh rom_shortcut.sh vimms_downloader.sh
```
3. Edit configuration variables in each script to match your directory structure
4. Ensure prerequisites are installed

---

## Typical PSX Conversion Workflow

1. **Convert ROMs to CHD format:**
   ```bash
   ./psx_batch_convert.sh
   ```

2. **Test the converted CHD files** in DuckStation or RetroArch to verify they work

3. **Run cleanup script to organize files:**
   ```bash
   ./psx_cleanup.sh
   ```
   - Choose to create backup (recommended!)
   - Confirm cleanup operation

4. **Result:** Clean PSX directory with only CHD files, originals safely backed up

---

## Directory Structure Example

```
/run/media/deck/Christoph/Emulation/
├── roms/
│   ├── psx/              # Main PSX directory (final CHD location)
│   ├── psx_chd/          # Temporary conversion output
│   ├── psx_backup/       # Backup of original files
│   ├── snes/             # SNES ROMs
│   └── n64/              # N64 ROMs
└── tools/
    └── chdconv/
        ├── chdman5       # Conversion tool
        └── *.log         # Conversion logs
```

---

## Logging

All scripts generate timestamped log files in `$LOG_DIR`:
- `psx_conversion_YYYYMMDD_HHMMSS.log`
- `psx_cleanup_YYYYMMDD_HHMMSS.log`

Logs include:
- Detailed operation steps
- File paths processed
- Success/failure status
- Summary statistics
- Timestamps

---

## Safety Tips

1. **Always create backups** before running cleanup operations
2. **Test CHD files** before deleting originals
3. **Review logs** after batch operations to check for errors
4. **Keep backups** on a separate drive or location
5. **Verify free space** before large conversions

---

## Troubleshooting

### psx_batch_convert.sh
- **"chdman5 not found"**: Install chdman5 or update `CHDMAN` path in script
- **Conversion fails**: Check source .cue file paths and referenced .bin files
- **Out of space**: Check available disk space in output directory

### psx_cleanup.sh
- **Permission denied**: Run with appropriate permissions
- **Backup fails**: Ensure rsync is installed and destination has space
- **Files not found**: Verify CHD_DIR and PSX_DIR paths are correct

### rom_shortcut.sh
- **Core not found**: Install core via RetroArch → Online Updater → Core Downloader
- **ROM not found**: Check SEARCH_ROOTS paths in script configuration
- **Permission errors**: Script automatically handles Flatpak permissions

---

## Contributing

Feel free to modify these scripts for your specific setup. Common customizations:
- Add support for additional emulator systems in `rom_shortcut.sh`
- Adjust logging verbosity
- Add new ROM format support
- Create additional cleanup/organization scripts

---

## License

These scripts are provided as-is for personal use with EmuDeck on Steam Deck.

---

## Author Notes

Created for streamlining ROM management and conversion workflows on Steam Deck. Scripts include extensive error checking, logging, and user feedback to ensure safe operation with large ROM collections.
