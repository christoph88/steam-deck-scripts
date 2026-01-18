#!/usr/bin/env bash
# emudeck-flatpak-launch.sh
# RetroArch Flatpak launcher for Steam Deck + EmuDeck with:
# - optional args: <system> <rom_path>
# - interactive system chooser if missing
# - fuzzy ROM search: type a query -> shows a numbered dropdown list to pick from
# - (optional) uses fzf if installed for a nicer fuzzy picker
#
# Examples:
#   ./emudeck-flatpak-launch.sh snes "/run/media/deck/Christoph/Emulation/roms/snes/15. Tetris Attack (USA) (En,Ja).sfc"
#   ./emudeck-flatpak-launch.sh n64  "/run/media/deck/Christoph/Emulation/roms/n64/08. Perfect Dark (USA) (Rev 1).z64"
#   ./emudeck-flatpak-launch.sh   # interactive: pick system -> search -> pick ROM
#
set -euo pipefail

APP_ID="org.libretro.RetroArch"
CORES_DIR="/home/deck/.var/app/${APP_ID}/config/retroarch/cores"

# Where to search for ROMs (covers internal + SD/external mounts)
SEARCH_ROOTS=(
  "/run/media/deck"
  "/home/deck/Emulation/roms"
)

die() { echo "ERROR: $*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# -------------------------
# 0) Parse args (supports:
#    - system rom
#    - rom only (will prompt system)
# -------------------------
SYSTEM=""
ROM=""

if [[ $# -ge 2 ]]; then
  SYSTEM="$1"
  ROM="$2"
elif [[ $# -eq 1 ]]; then
  # If first arg looks like an existing file, treat it as ROM
  if [[ -f "$1" ]]; then
    ROM="$1"
  else
    SYSTEM="$1"
  fi
fi

# -------------------------
# 1) Choose system (if missing)
# -------------------------
if [[ -z "$SYSTEM" ]]; then
  echo "Select system:"
  select opt in "SNES" "N64"; do
    case "$REPLY" in
      1) SYSTEM="snes"; break ;;
      2) SYSTEM="n64"; break ;;
      *) echo "Invalid selection" ;;
    esac
  done
fi

# System -> core + extensions + default ROM folder (used for permission)
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
# 2) Build ROM list
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

  # Use -print0 safe handling; filter unreadable errors quietly
  local tmp
  tmp="$(mktemp)"
  : > "$tmp"
  for r in "${roots[@]}"; do
    [[ -d "$r" ]] || continue
    # shellcheck disable=SC2068
    find "$r" -type f \( "${find_args[@]}" \) -print 2>/dev/null >> "$tmp" || true
  done
  sort -u "$tmp"
  rm -f "$tmp"
}

# -------------------------
# 3) Interactive fuzzy search + dropdown chooser (if ROM missing)
# -------------------------
pick_rom_fuzzy_dropdown() {
  local roms=("$@")

  if [[ ${#roms[@]} -eq 0 ]]; then
    die "No ROMs found in: ${SEARCH_ROOTS[*]}"
  fi

  # If fzf exists, offer best UX.
  if have_cmd fzf; then
    echo "Tip: Using fzf for fuzzy selection (installed)."
    local chosen
    chosen="$(printf "%s\n" "${roms[@]}" | fzf --prompt="Search ROM: " --height=40% --layout=reverse --border)"
    [[ -n "${chosen:-}" ]] || die "No ROM selected."
    echo "$chosen"
    return 0
  fi

  # Pure bash fallback: query -> show top matches -> numbered dropdown (select)
  while true; do
    echo
    read -r -p "Search ROM (fuzzy, e.g. 'tetris' or 'perfect dark'; blank = show all): " query || true

    # Score matches: prefer substring hits; also allow multi-word queries.
    # We'll filter + keep first N for usability.
    local matches=()
    local qlower="${query,,}"

    if [[ -z "$qlower" ]]; then
      matches=("${roms[@]}")
    else
      # split query into words
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
      echo "No matches. Try another query."
      continue
    fi

    # Cap list (avoid massive select menus)
    local cap=30
    if [[ ${#matches[@]} -gt $cap ]]; then
      echo "Found ${#matches[@]} matches. Showing first $cap (refine your search to narrow)."
      matches=("${matches[@]:0:$cap}")
    else
      echo "Found ${#matches[@]} match(es)."
    fi

    echo
    echo "Pick a ROM:"
    select rom in "${matches[@]}" "Search again"; do
      if [[ "$REPLY" -ge 1 && "$REPLY" -le "${#matches[@]}" ]]; then
        echo "${matches[$((REPLY-1))]}"
        return 0
      elif [[ "$rom" == "Search again" ]]; then
        break
      else
        echo "Invalid selection."
      fi
    done
  done
}

if [[ -z "$ROM" ]]; then
  mapfile -t ALL_ROMS < <(build_rom_list "${SEARCH_ROOTS[@]}")
  ROM="$(pick_rom_fuzzy_dropdown "${ALL_ROMS[@]}")"
fi

[[ -f "$ROM" ]] || die "ROM not found: $ROM"

# -------------------------
# 4) Flatpak permission fix (idempotent)
#    If ROM is on /run/media/deck/<LABEL>/..., allow that mount root.
# -------------------------
if [[ "$ROM" == /run/media/deck/*/* ]]; then
  DRIVE_ROOT="$(echo "$ROM" | awk -F/ '{print "/"$2"/"$3"/"$4"/"$5}')"
  flatpak override --user --filesystem="$DRIVE_ROOT" "$APP_ID" >/dev/null 2>&1 || true
else
  # Otherwise allow the ROM's parent dir (safe, minimal)
  flatpak override --user --filesystem="$(dirname "$ROM")" "$APP_ID" >/dev/null 2>&1 || true
fi

# -------------------------
# 5) Launch
# -------------------------
exec flatpak run "$APP_ID" -L "$CORE" "$ROM"
