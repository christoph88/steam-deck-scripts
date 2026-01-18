#!/usr/bin/env bash
# rom_shortcut.sh
# RetroArch Flatpak launcher for Steam Deck + EmuDeck with:
# - optional args: <system> <rom_path> OR <rom_path> OR <system>
# - interactive system chooser if missing
# - fuzzy ROM search -> dropdown list picker (uses fzf if installed)
# - Flatpak filesystem override for external drive mounts
# - Prints the exact working Terminal + Steam shortcut command before launching
#
# Examples:
#   ./rom_shortcut.sh snes "/run/media/deck/Christoph/Emulation/roms/snes/15. Tetris Attack (USA) (En,Ja).sfc"
#   ./rom_shortcut.sh n64  "/run/media/deck/Christoph/Emulation/roms/n64/08. Perfect Dark (USA) (Rev 1).z64"
#   ./rom_shortcut.sh snes   # interactive ROM picker
#   ./rom_shortcut.sh        # interactive system + ROM picker
#
set -euo pipefail

APP_ID="org.libretro.RetroArch"
CORES_DIR="/home/deck/.var/app/${APP_ID}/config/retroarch/cores"

# Where to search for ROMs (covers external mounts + internal EmuDeck folder)
SEARCH_ROOTS=(
  "/run/media/deck"
  "/home/deck/Emulation/roms"
)

die() { echo "ERROR: $*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

SYSTEM=""
ROM=""

# -------------------------
# Parse args
# -------------------------
if [[ $# -ge 2 ]]; then
  SYSTEM="$1"
  ROM="$2"
elif [[ $# -eq 1 ]]; then
  if [[ -f "$1" ]]; then
    ROM="$1"
  else
    SYSTEM="$1"
  fi
fi

# -------------------------
# System selection
# -------------------------
if [[ -z "$SYSTEM" ]]; then
  echo "Select system:" >&2
  select opt in "SNES" "N64"; do
    case "$REPLY" in
      1) SYSTEM="snes"; break ;;
      2) SYSTEM="n64"; break ;;
      *) echo "Invalid selection" >&2 ;;
    esac
  done
fi

CORE_FILE=""
EXT_GLOB=()
case "$SYSTEM" in
  snes)
    CORE_FILE="snes9x_libretro.so"
    EXT_GLOB=( "*.sfc" "*.smc" )
    ;;
  n64)
    CORE_FILE="mupen64plus_next_libretro.so"
    EXT_GLOB=( "*.z64" "*.n64" "*.v64" )
    ;;
  *)
    die "Unsupported system: $SYSTEM (supported: snes, n64)"
    ;;
esac

CORE="${CORES_DIR}/${CORE_FILE}"
[[ -f "$CORE" ]] || die "Core not found: $CORE
Install it via RetroArch → Online Updater → Core Downloader."

# -------------------------
# Build ROM list
# -------------------------
build_rom_list() {
  local roots=("$@")
  local find_args=()
  local first=1

  for ext in "${EXT_GLOB[@]}"; do
    if [[ $first -eq 1 ]]; then
      find_args+=( -name "$ext" )
      first=0
    else
      find_args+=( -o -name "$ext" )
    fi
  done

  local tmp
  tmp="$(mktemp)"
  : > "$tmp"
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    find "$r" -type f \( "${find_args[@]}" \) -print 2>/dev/null >> "$tmp" || true
  done
  sort -u "$tmp"
  rm -f "$tmp"
}

# -------------------------
# Fuzzy search + dropdown chooser
# (UI to stderr; chosen ROM path to stdout)
# -------------------------
pick_rom_fuzzy_dropdown() {
  local roms=("$@")
  [[ ${#roms[@]} -gt 0 ]] || die "No ROMs found in: ${SEARCH_ROOTS[*]}"

  if have_cmd fzf; then
    echo "Using fzf for fuzzy selection." >&2
    local chosen
    chosen="$(printf "%s\n" "${roms[@]}" | fzf --prompt="Search ROM: " --height=40% --layout=reverse --border)"
    [[ -n "${chosen:-}" ]] || die "No ROM selected."
    printf "%s" "$chosen"
    return 0
  fi

  while true; do
    echo "" >&2
    read -r -p "Search ROM (fuzzy; blank = show all): " query >&2 || true

    local matches=()
    local qlower="${query,,}"

    if [[ -z "$qlower" ]]; then
      matches=("${roms[@]}")
    else
      IFS=' ' read -r -a qwords <<< "$qlower"
      for p in "${roms[@]}"; do
        local plower="${p,,}"
        local ok=1
        for w in "${qwords[@]}"; do
          [[ -z "$w" ]] && continue
          if [[ "$plower" != *"$w"* ]]; then
            ok=0
            break
          fi
        done
        [[ $ok -eq 1 ]] && matches+=("$p")
      done
    fi

    if [[ ${#matches[@]} -eq 0 ]]; then
      echo "No matches. Try another query." >&2
      continue
    fi

    local cap=30
    if [[ ${#matches[@]} -gt $cap ]]; then
      echo "Found ${#matches[@]} matches. Showing first $cap (refine search to narrow)." >&2
      matches=("${matches[@]:0:$cap}")
    else
      echo "Found ${#matches[@]} match(es)." >&2
    fi

    echo "" >&2
    echo "Pick a ROM:" >&2
    select rom in "${matches[@]}" "Search again"; do
      if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#matches[@]}" ]]; then
        printf "%s" "${matches[$((REPLY-1))]}"
        return 0
      elif [[ "$rom" == "Search again" ]]; then
        break
      else
        echo "Invalid selection." >&2
      fi
    done
  done
}

# -------------------------
# Pick ROM if missing
# -------------------------
if [[ -z "$ROM" ]]; then
  mapfile -t ALL_ROMS < <(build_rom_list "${SEARCH_ROOTS[@]}")
  ROM="$(pick_rom_fuzzy_dropdown "${ALL_ROMS[@]}")"
fi

[[ -f "$ROM" ]] || die "ROM not found: $ROM"

# -------------------------
# Flatpak permission fix (idempotent)
# - if ROM under /run/media/deck/<LABEL>/..., allow that mount root
# - otherwise allow ROM's parent dir
# -------------------------
if [[ "$ROM" == /run/media/deck/*/* ]]; then
  DRIVE_ROOT="$(echo "$ROM" | awk -F/ '{print "/"$2"/"$3"/"$4"/"$5}')"
  flatpak override --user --filesystem="$DRIVE_ROOT" "$APP_ID" >/dev/null 2>&1 || true
else
  flatpak override --user --filesystem="$(dirname "$ROM")" "$APP_ID" >/dev/null 2>&1 || true
fi

# -------------------------
# Print working commands (for copy/paste)
# -------------------------
STEAM_TARGET="/usr/bin/flatpak"
STEAM_LAUNCH_OPTS="run ${APP_ID} -L \"${CORE}\" \"${ROM}\""
TERMINAL_CMD="flatpak run ${APP_ID} -L \"${CORE}\" \"${ROM}\""

{
  echo ""
  echo "==================== COPY/PASTE ===================="
  echo "Terminal test command:"
  echo "${TERMINAL_CMD}"
  echo ""
  echo "Steam shortcut:"
  echo "  Target: ${STEAM_TARGET}"
  echo "  Start In: /"
  echo "  Launch Options: ${STEAM_LAUNCH_OPTS}"
  echo "===================================================="
  echo ""
} >&2

# -------------------------
# Launch
# -------------------------
exec flatpak run "$APP_ID" -L "$CORE" "$ROM"
