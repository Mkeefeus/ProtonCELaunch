#!/bin/bash
: '
    Copyright (C) 2025 Malcolm Keefe

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
'

verify_steam_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo "Invalid directory: $dir"
        return 1
    fi
    if [ ! -f "$dir/steamapps/libraryfolder.vdf" ]; then
        echo "Invalid Steam directory: $dir"
        return 1
    fi
    return 0
}

prompt_steam_root() {
    local input_path=""
    read -e -p "Enter your Steam root directory path: " input_path
    if [[ "$input_path" == "~/"* ]]; then
        input_path="${HOME}/${input_path:2}"
    fi
    
    if ! verify_steam_dir "$input_path"; then
        prompt_steam_root
    else
        echo "$input_path"
    fi
}

verify_cheat_exe() {
    local exe_path=$1
    if [ ! -f "$exe_path" ]; then
        echo "Cheat Engine executable not found at: $exe_path"
        return 1
    fi
    return 0
}

prompt_cheat_exe() {
    local input_path=""
    read -e -p "Enter the full path to Cheat Engine executable: " input_path
    if [[ "$input_path" == "~/"* ]]; then
        input_path="${HOME}/${input_path:2}"
    fi
    
    if ! verify_cheat_exe "$input_path"; then
        prompt_cheat_exe
    else
        echo "$input_path"
    fi
}

DATA_FILE="$HOME/.config/ProtonCELauncher"

if [[ ! -e "$DATA_FILE" ]]; then
    echo "Creating data file at $DATA_FILE"
    cat <<'EOL' > "$DATA_FILE"
# Proton Cheat Engine Launcher Configuration File
# Don't touch unless you know what you're doing!
EOL
fi

SCRIPT_DATA=$( cat "$DATA_FILE" 2>/dev/null )
STEAM_ROOT=$(echo "$SCRIPT_DATA" | grep "^STEAM_ROOT=" | cut -d'=' -f2-)

if [ -d "$STEAM_ROOT" ]; then
    echo "Using configured Steam root: $STEAM_ROOT"
else
    echo "Checking for default Steam installation path..."
    if [ -d "$HOME/.steam/steam" ]; then
        STEAM_ROOT="$HOME/.steam/steam"
        echo "STEAM_ROOT=$STEAM_ROOT" >> "$DATA_FILE"
        echo "Found Steam root at $STEAM_ROOT"
    else
        echo "Steam installation not found in default location. Please provide the path to your default Steam directory. This directory should contain the steamapps folder."
        STEAM_ROOT=$(prompt_steam_root)
    fi
fi

CHEAT_EXE=$(echo "$SCRIPT_DATA" | grep "^CHEAT_EXE=" | cut -d'=' -f2-)

if [ -f "$CHEAT_EXE" ]; then
    echo -e "Using configured Cheat Engine executable: $CHEAT_EXE\n"
else
    CHEAT_EXE=$(prompt_cheat_exe)
    echo "CHEAT_EXE=$CHEAT_EXE" >> "$DATA_FILE"
fi

# Find all games with Proton prefixes
echo -e "Scanning for installed games...\n"
declare -a library_folders=()
declare -a app_ids=()
declare -a game_names=()

# Read library folders from libraryfolders.vdf
library_vdf="$STEAM_ROOT/steamapps/libraryfolders.vdf"
if [ -f "$library_vdf" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
            path="${BASH_REMATCH[1]}"
            library_folders+=("$path")
        fi
    done < "$library_vdf"
else
    echo "Warning: libraryfolders.vdf not found, using only main Steam directory"
    library_folders+=("$STEAM_ROOT")
fi

# Scan all library folders for games with Proton prefixes
for library in "${library_folders[@]}"; do
    for compat_dir in "$library/steamapps/compatdata"/*; do
        if [ ! -d "$compat_dir" ] || [ ! -f "$compat_dir/version" ]; then
            continue
        fi
        app_id=$(basename "$compat_dir")
        # Skip appid 0 (common prefix)
        if [ "$app_id" == "0" ]; then
            continue
        fi
        # Function to get game name from app manifest
        manifest="$library/steamapps/appmanifest_${app_id}.acf"
        if [ ! -f "$manifest" ]; then
            echo "Failed to find manifest for AppID $app_id, skipping..."
            continue
        fi
        game_name=$(grep '"name"' "$manifest" | head -1 | sed 's/.*"name"[[:space:]]*"\([^"]*\)".*/\1/')
        install_dir=$STEAM_ROOT/steamapps/common/$(grep '"installdir"' "$manifest" | head -1 | sed 's/.*"installdir"[[:space:]]*"\([^"]*\)".*/\1/')
        if [ -f "$install_dir/proton" ] && [ -f "$install_dir/toolmanifest.vdf" ]; then
            # This is a Proton installation, skip it
            continue
        fi            
        app_ids+=("$app_id")
        game_names+=("$game_name")
    done
done

# Display selection menu
if [ ${#app_ids[@]} -eq 0 ]; then
    echo "No games with Proton prefixes found!"
    exit 1
fi

echo -e "Cheat Engine will run in the selected games prefix. If a game is missing, make sure you have run it at least once.\n"
echo "Select a game:"
for i in "${!app_ids[@]}"; do
    printf "%2d) %-50s (AppID: %s)\n" $((i+1)) "${game_names[$i]}" "${app_ids[$i]}"
done
echo ""
read -p "Enter number (1-${#app_ids[@]}): " selection

# Validate selection
if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#app_ids[@]} ]; then
    echo "Invalid selection!"
    exit 1
fi

APP_ID="${app_ids[$((selection-1))]}"
GAME_NAME="${game_names[$((selection-1))]}"

echo ""
echo "Selected: $GAME_NAME (AppID: $APP_ID)"
echo ""

COMPAT_DIR="$STEAM_ROOT/steamapps/compatdata/$APP_ID"
PROTON_VERSION=$(cat "$COMPAT_DIR/version")

# Find the matching Proton installation by searching for CURRENT_PREFIX_VERSION
PROTON_ROOT=""

if [[ "$PROTON_VERSION" == GE-Proton* ]]; then
    # GE-Proton is installed in compatibilitytools.d
    PROTON_ROOT="$STEAM_ROOT/compatibilitytools.d/$PROTON_VERSION"
else
    # Search through Steam's Proton installations
    for proton_dir in "$STEAM_ROOT/steamapps/common"/Proton*; do
        if [ ! -f "$proton_dir/proton" ]; then
            continue
        fi
        if ! grep -q "CURRENT_PREFIX_VERSION=\"$PROTON_VERSION\"" "$proton_dir/proton"; then
            continue
        fi
        PROTON_ROOT="$proton_dir"
        break
    done
fi

if [ -z "$PROTON_ROOT" ] || [ ! -f "$PROTON_ROOT/proton" ]; then
    echo "Error: Could not find Proton installation for version $PROTON_VERSION"
    exit 1
fi

echo "Launching Cheat Engine with Proton version $PROTON_VERSION and prefix for $GAME_NAME..."
echo "Using Proton root at: $PROTON_ROOT"
STEAM_COMPAT_DATA_PATH="$COMPAT_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_ROOT" \
"$PROTON_ROOT/proton" run "$CHEAT_EXE"