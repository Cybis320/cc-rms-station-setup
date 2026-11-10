# CC RMS station setup

Adds RMS stations to a multi-camera Linux (GNOME) machine and makes their
capture terminals open reliably at login.

## Install / update

    curl -fsSL https://raw.githubusercontent.com/Cybis320/cc-rms-station-setup/master/install.sh | bash

The checkout lands in `~/source/CC_Utils/station_setup`. The installer:

- creates `stations.csv` from the blank template, if it isn't there yet;
- converts any existing `~/.config/autostart/*_StartCap.desktop` entries to
  the delayed launcher (originals backed up in `~/.config/autostart/backup_*`);
- registers the checkout with the shared hourly cc-utils updater, which
  re-applies the autostart fix after every pull.

It does not add stations by itself.

## Adding stations

1. List the stations in `~/source/CC_Utils/station_setup/stations.csv`, one
   row each. Columns:
   - `station_id` (required; `stationID` also accepted);
   - `camera_ip` (optional): replaces the IP in the `.config` `device:` RTSP URL;
   - any other column named like a `.config` key (e.g. `fps`) sets that key.

   Empty cells are skipped. The file is local to the machine and ignored by
   git, so updates never touch it.
2. Run `~/source/CC_Utils/station_setup/add_GStation.sh [RMS_data_dir] [stations.csv]`
   (defaults `~/RMS_data` and the checkout's `stations.csv`, then
   `~/source/CC_Utils/stations.csv`).

For each new station it creates `~/source/Stations/<ID>/.config`, the data
directory, a StartCap autostart entry (linked to the Desktop) and a
LiveStream desktop launcher. Stations that already exist only get their
shortcuts rewritten, so re-running it repairs them (e.g. after a terminal
change).

The terminal is detected: gnome-terminal, else Ptyxis (Ubuntu 25.10+
default), else lxterminal; override with `RMS_TERMINAL=<name>`.
Boot delays are 30 s + 10 s per CSV row; override with `BOOT_DELAY_BASE` and
`BOOT_DELAY_STEP`.

## Why the launcher (`term_launch.sh`)

At login every autostart entry fires in the same second, and each one asks
D-Bus to start the terminal server (`gnome-terminal-server`, or Ptyxis). The server takes about 25 s to come
up while the session is still settling, so every client hits the 25 s D-Bus
activation timeout and no capture terminal opens:

    Error calling StartServiceByName for org.gnome.Terminal: Timeout was reached

`term_launch.sh -d N -t <terminal>` wraps the terminal:

1. sleeps `-d N` seconds, staggered per station (30 s, 40 s, 50 s, ...),
   but only while uptime is under 10 minutes, so clicking the Desktop icon
   later opens the terminal at once;
2. starts the terminal server without the 25 s limit (gnome-terminal via
   systemd, Ptyxis via a D-Bus activation call with a long timeout);
3. retries the terminal up to 5 times, 10 s apart.

Check a boot with `journalctl --user -b | grep -E "StartCap|term_launch"`.

`fix_autostart_delay.sh [BASE] [STEP]` re-runs the conversion by hand.
It handles gnome-terminal, Ptyxis and lxterminal entries; others are left
unchanged.

## Not for Raspberry Pi

`add_GStation.sh` refuses to run on a Pi; use RMS's `add_Pi_Station.sh`.

## Licence

GPL-3.0. `add_GStation.sh` is based on RMS `Scripts/MultiCamLinux/add_GStation.sh`
(Copyright (C) 2023 Ed Harman).
