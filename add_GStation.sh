#!/bin/bash
# Refactored add_GStation.sh - uses gnome-terminal (or Ptyxis on Ubuntu 25.10+) instead of lxterminal
# Based on RMS/Scripts/MultiCamLinux/add_GStation.sh
#
# This software is part of the Linux port of RMS
# Copyright (C) 2023  Ed Harman
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Refactored version - uses gnome-terminal with profiles instead of lxterminal

# Prevent running this script on a Raspberry Pi
file=/sys/firmware/devicetree/base/model
if [[ -f "$file" ]]; then
    contents=$(tr -d '\0' < $file)
    if [[ $contents == 'Raspberry'* ]]; then
        echo "The add_GStation.sh script should not be used on Raspberry Pi."
        echo "Please use add_Pi_Station.sh to add cameras on a Pi5."
        exit 1
    fi
fi

# Get user's desktop directory
Desktop=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")

# Pick the terminal the shortcuts launch: gnome-terminal (Ubuntu <= 25.04),
# Ptyxis (Ubuntu 25.10+ default), else lxterminal. Override with
# RMS_TERMINAL=<name>. A .desktop whose Exec program isn't installed is not
# recognised as a launcher, so the choice must match what's on this machine.
TERM_APP="${RMS_TERMINAL:-}"
if [[ -z "$TERM_APP" ]]; then
    for t in gnome-terminal ptyxis lxterminal; do
        if command -v "$t" >/dev/null 2>&1; then
            TERM_APP="$t"
            break
        fi
    done
fi
if [[ -z "$TERM_APP" ]] || ! command -v "$TERM_APP" >/dev/null 2>&1; then
    echo "Error: no supported terminal found (gnome-terminal, ptyxis or lxterminal)."
    echo "Install one, e.g.: sudo apt install gnome-terminal"
    exit 1
fi
echo "Shortcuts will use terminal: ${TERM_APP}"

# Print the Exec= command that runs $2 in a new $TERM_APP window titled $1
term_exec() {
    local title=$1 command=$2
    case "$TERM_APP" in
        gnome-terminal)
            echo "gnome-terminal --profile=StartCapture --title=${title} -- bash -c \"${command}\"" ;;
        ptyxis)
            echo "ptyxis --new-window --title=${title} -- bash -c \"${command}\"" ;;
        lxterminal)
            echo "lxterminal --title=${title} -e \"${command}\"" ;;
        *)
            echo "Error: unsupported terminal '${TERM_APP}'" >&2
            exit 1 ;;
    esac
}

# Icon name for the shortcuts
case "$TERM_APP" in
    ptyxis) TERM_ICON=org.gnome.Ptyxis ;;
    *)      TERM_ICON="$TERM_APP" ;;
esac

# Write the StartCapture (autostart + desktop link) and LiveStream shortcuts for
# station $1. Safe to re-run: it overwrites them, so re-running this script
# repairs shortcuts for existing stations (e.g. after a terminal change).
write_shortcuts() {
    local item=$1

    cat <<- EOF > ~/.config/autostart/${item}_StartCap.desktop
	[Desktop Entry]
	Name=${item}_StartCap
	Type=Application
	Exec=$(term_exec "${item}" "~/source/RMS/Scripts/MultiCamLinux/StartCapture.sh ${item}")
	Hidden=false
	NoDisplay=false
	Icon=${TERM_ICON}
	EOF

    chmod +x ~/.config/autostart/${item}_StartCap.desktop

    # Desktop symlink for StartCapture
    ln -sf ~/.config/autostart/${item}_StartCap.desktop "${Desktop}/${item}_StartCap.desktop"
    gio set "${Desktop}/${item}_StartCap.desktop" metadata::trusted true 2>/dev/null
    chmod +x "${Desktop}/${item}_StartCap.desktop"

    cat <<- EOF > "${Desktop}/Show_LiveStream-${item}.desktop"
	[Desktop Entry]
	Name=${item}-ShowLiveStream
	Type=Application
	Exec=$(term_exec "Stream-${item}" "~/source/RMS/Scripts/MultiCamLinux/LiveStream.sh ${item}")
	Hidden=false
	NoDisplay=false
	Icon=${TERM_ICON}
	EOF

    gio set "${Desktop}/Show_LiveStream-${item}.desktop" metadata::trusted true 2>/dev/null
    chmod +x "${Desktop}/Show_LiveStream-${item}.desktop"
}

# Parse arguments: [RMS_data_path] [stations.csv]
# Smart detection: if single arg ends in .csv, treat as CSV file
RMS_data=~/RMS_data
CSV_FILE=""

if [[ "$#" -eq 0 ]]; then
    # No args: use defaults
    if [[ -f ~/source/CC_Utils/stations.csv ]]; then
        CSV_FILE=~/source/CC_Utils/stations.csv
    fi
elif [[ "$#" -eq 1 ]]; then
    # Single arg: check if it's a CSV file or a directory
    if [[ "${1}" == *.csv ]]; then
        CSV_FILE="${1}"
    else
        RMS_data="${1}"
        if [[ -f ~/source/CC_Utils/stations.csv ]]; then
            CSV_FILE=~/source/CC_Utils/stations.csv
        fi
    fi
else
    # Two args: first is RMS_data, second is CSV
    RMS_data="${1}"
    CSV_FILE="${2}"
fi

if [[ -z "${CSV_FILE}" || ! -f "${CSV_FILE}" ]]; then
    echo "Error: CSV file not found."
    echo "Usage: $0 [RMS_data_path] <stations.csv>"
    echo "       $0 stations.csv"
    echo "       $0                  (uses ~/source/CC_Utils/stations.csv)"
    exit 1
fi

# Ensure required directories exist
mkdir -p ~/source/Stations
mkdir -p "${RMS_data}"
mkdir -p ~/.config/autostart

echo "Reading stations from: ${CSV_FILE}"

# Load the CSV without CRs (Windows line endings); the here-strings below
# end it with a newline, so a last row without one is still read
csv_text=$(tr -d '\r' < "${CSV_FILE}")

# Read CSV header to get column names
IFS=',' read -r -a HEADERS <<< "${csv_text}"

# Trim whitespace from headers
for i in "${!HEADERS[@]}"; do
    HEADERS[$i]=$(echo "${HEADERS[$i]}" | xargs)
done

# Find required column indices
station_id_col=-1
camera_ip_col=-1
for i in "${!HEADERS[@]}"; do
    case "${HEADERS[$i]}" in
        station_id|stationID) station_id_col=$i ;;
        camera_ip) camera_ip_col=$i ;;
    esac
done

if [[ $station_id_col -eq -1 ]]; then
    echo "Error: CSV must have a 'station_id' or 'stationID' column"
    exit 1
fi

# Count stations for extra_space_gb calculation
No_Stations=$(tail -n +2 <<< "${csv_text}" | grep -c -v '^[[:space:]]*$')

echo -e "\nStations to add from CSV: ${No_Stations}"

# Process each data row
tail -n +2 <<< "${csv_text}" | while IFS=',' read -r -a VALUES; do
    # Skip empty lines
    [[ ${#VALUES[@]} -eq 0 ]] && continue

    # Trim whitespace from values
    for i in "${!VALUES[@]}"; do
        VALUES[$i]=$(echo "${VALUES[$i]}" | xargs)
    done

    item="${VALUES[$station_id_col]}"
    [[ -z "$item" ]] && continue

    if [[ -d ~/source/Stations/${item} ]]; then
        echo -e "\nNot creating station ${item} - it already exists (refreshing its shortcuts)"
        write_shortcuts "${item}"
        continue
    fi

    echo "Creating station ${item}..."
    mkdir -p ~/source/Stations/${item}
    mkdir -p ${RMS_data}/${item}

    # Copy config template
    cp ~/source/RMS/.config ~/source/Stations/${item}

    # Create the autostart entry and desktop shortcuts
    write_shortcuts "${item}"

    # Copy mask file
    cp ~/source/RMS/mask.bmp ~/source/Stations/${item} 2>/dev/null

    # Apply default config customizations
    config_file=~/source/Stations/${item}/.config
    sed -i "s/stationID:.*$/stationID: $item/g" "${config_file}"
    sed -i "s,data_dir:.*$,data_dir: ${RMS_data}/${item},g" "${config_file}"
    sed -i "s/extra_space_gb:.*$/extra_space_gb: $(( ${No_Stations} * 20 ))/g" "${config_file}"
    sed -i "s/\(reboot_after_processing:\).*/\1 false/g" "${config_file}"

    # Apply camera_ip to device URL if column exists
    if [[ $camera_ip_col -ne -1 && -n "${VALUES[$camera_ip_col]}" ]]; then
        camera_ip="${VALUES[$camera_ip_col]}"
        # Replace IP address in the device URL (matches IP pattern in rtsp:// URL)
        sed -i -E "s|(device:.*rtsp://)[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|\1${camera_ip}|g" "${config_file}"
        echo "  Set camera IP: ${camera_ip}"
    fi

    # Apply any additional CSV columns that match .config keys
    for i in "${!HEADERS[@]}"; do
        header="${HEADERS[$i]}"
        value="${VALUES[$i]}"

        # Skip station_id, camera_ip (already handled), and empty values
        [[ "$header" == "station_id" || "$header" == "stationID" || "$header" == "camera_ip" ]] && continue
        [[ -z "$value" ]] && continue

        # Check if this header exists as a key in .config
        if grep -q "^${header}:" "${config_file}"; then
            sed -i "s|^${header}:.*$|${header}: ${value}|g" "${config_file}"
            echo "  Set ${header}: ${value}"
        fi
    done

    echo "Added station ${item}"
done

# Generate SSH keys if not present
if [[ ! -f ~/.ssh/id_rsa ]]; then
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -P ""
    echo "SSH keys generated in ~/.ssh"
fi

# Set timezone to UTC
timedatectl set-timezone UTC 2>/dev/null

# Configure GNOME power settings to prevent sleep during capture
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null
gsettings set org.gnome.desktop.session idle-delay 600 2>/dev/null
gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null

# Add RMS activation to .bashrc if not present
if ! grep -q "source ~/vRMS/bin/activate" ~/.bashrc; then
    cat <<EOF >> ~/.bashrc

# Activate RMS
cd ~/source/RMS
source ~/vRMS/bin/activate
EOF
fi

# Create CMNbinViewer desktop shortcut
user=$(id -u -n)
cat <<- EOF > "${Desktop}/CMNbinViewer.desktop"
[Desktop Entry]
Name=CMNbinViewer
Type=Application
Exec=/home/${user}/source/RMS/Scripts/CMNbinViewer_env.sh
Hidden=false
NoDisplay=false
Icon=/home/${user}/source/cmn_binviewer/icon.png
EOF

gio set "${Desktop}/CMNbinViewer.desktop" metadata::trusted true 2>/dev/null
chmod +x "${Desktop}/CMNbinViewer.desktop"

# Ensure timezone is UTC
if ! grep -Fq "UTC" /etc/timezone 2>/dev/null; then
    sudo timedatectl set-timezone UTC 2>/dev/null
fi

echo -e "\nStation configuration complete"
