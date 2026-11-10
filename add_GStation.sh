#!/bin/bash
# Refactored add_GStation.sh - uses gnome-terminal instead of lxterminal
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

# Usage: add_GStation.sh [RMS_data_dir]
# Station IDs come from stations.csv next to this script (one station_id per
# line, header and # comments ignored); if it lists none, they are asked for.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATIONS_CSV="$HERE/stations.csv"

# Get user's desktop directory
Desktop=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")

# Parse RMS_data directory argument
if [[ "$#" -eq 0 ]]; then
    RMS_data=~/RMS_data
else
    RMS_data=${1}
fi

# Ensure required directories exist
mkdir -p ~/source/Stations
mkdir -p "${RMS_data}"
mkdir -p ~/.config/autostart

# Collect station IDs: from stations.csv if it lists any, else from the user
declare -a Station
if [[ -f $STATIONS_CSV ]]; then
    while IFS=, read -r this_Station _ || [[ -n $this_Station ]]; do
        this_Station=$(echo "$this_Station" | tr -d '[:space:]"')
        [[ -z $this_Station || $this_Station == \#* || $this_Station == station_id ]] && continue
        Station+=("$this_Station")
    done < "$STATIONS_CSV"
fi
if [[ ${#Station[@]} -gt 0 ]]; then
    echo "Read ${#Station[@]} station(s) from $STATIONS_CSV"
else
    while :; do
        read -p "Enter station ID, <cr> to end: " this_Station
        if [[ -z $this_Station ]]; then
            break
        fi
        Station+=("$this_Station")
    done
fi

if [[ ${#Station[@]} -eq 0 ]]; then
    echo "No stations specified. Exiting."
    exit 0
fi

echo -e "\nNew stations to add:"
printf '%s\n' "${Station[@]}"

No_Stations=${#Station[@]}

for item in "${Station[@]}"; do
    if [[ -d ~/source/Stations/${item} ]]; then
        echo -e "\nNot creating station ${item} - it already exists"
        continue
    fi

    echo "Creating station ${item}..."
    mkdir -p ~/source/Stations/${item}
    mkdir -p ${RMS_data}/${item}

    # Copy config template
    cp ~/source/RMS/.config ~/source/Stations/${item}

    # Stagger boot launches: 30 s base + 10 s per station already present
    # (term_launch.sh only applies the delay shortly after boot)
    station_index=$(( $(ls -1 ~/source/Stations | wc -l) - 1 ))
    boot_delay=$(( 30 + 10 * station_index ))

    # Create autostart .desktop entry using gnome-terminal
    cat <<- EOF > ~/.config/autostart/${item}_StartCap.desktop
	[Desktop Entry]
	Name=${item}_StartCap
	Type=Application
	Exec=${HERE}/term_launch.sh -d ${boot_delay} --profile=StartCapture --title=${item} -- bash -c "~/source/RMS/Scripts/MultiCamLinux/StartCapture.sh ${item}"
	Hidden=false
	NoDisplay=false
	Icon=gnome-terminal
	EOF

    chmod +x ~/.config/autostart/${item}_StartCap.desktop

    # Create Desktop symlink for StartCapture
    ln -sf ~/.config/autostart/${item}_StartCap.desktop "${Desktop}/${item}_StartCap.desktop"
    gio set "${Desktop}/${item}_StartCap.desktop" metadata::trusted true 2>/dev/null
    chmod +x "${Desktop}/${item}_StartCap.desktop"

    # Copy mask file
    cp ~/source/RMS/mask.bmp ~/source/Stations/${item} 2>/dev/null

    # Create ShowLiveStream desktop shortcut using gnome-terminal
    cat <<- EOF > "${Desktop}/Show_LiveStream-${item}.desktop"
	[Desktop Entry]
	Name=${item}-ShowLiveStream
	Type=Application
	Exec=gnome-terminal --profile=StartCapture --title=Stream-${item} -- bash -c "~/source/RMS/Scripts/MultiCamLinux/LiveStream.sh ${item}"
	Hidden=false
	NoDisplay=false
	Icon=gnome-terminal
	EOF

    gio set "${Desktop}/Show_LiveStream-${item}.desktop" metadata::trusted true 2>/dev/null
    chmod +x "${Desktop}/Show_LiveStream-${item}.desktop"

    # Customize station .config
    sed -i "s/D:.*$/D: $item/g" ~/source/Stations/${item}/.config
    sed -i "s,data_dir.*$,data_dir: ${RMS_data}/${item},g" ~/source/Stations/${item}/.config
    sed -i "s/extra_space_gb: .*$/extra_space_gb: $(( ${No_Stations} * 20 ))/g" ~/source/Stations/${item}/.config
    sed -i "s/\(reboot_after_processing:\).*/\1 false/g" ~/source/Stations/${item}/.config

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
