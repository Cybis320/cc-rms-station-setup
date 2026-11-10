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

1. List the station IDs in `~/source/CC_Utils/station_setup/stations.csv`,
   one per line under the `station_id` header (`#` comments allowed).
   This file is local to the machine and ignored by git, so updates never
   touch it.
2. Run `~/source/CC_Utils/station_setup/add_GStation.sh [RMS_data_dir]`
   (default `~/RMS_data`). Stations that already exist are skipped. If the
   CSV lists no stations, the script asks for them instead.

For each new station it creates `~/source/Stations/<ID>/.config`, the data
directory, a StartCap autostart entry (linked to the Desktop) and a
LiveStream desktop launcher.

## Why the launcher (`term_launch.sh`)

At login every autostart entry fires in the same second, and each one asks
D-Bus to start `gnome-terminal-server`. The server takes about 25 s to come
up while the session is still settling, so every client hits the 25 s D-Bus
activation timeout and no capture terminal opens:

    Error calling StartServiceByName for org.gnome.Terminal: Timeout was reached

`term_launch.sh` wraps `gnome-terminal`:

1. sleeps `-d N` seconds, staggered per station (30 s, 40 s, 50 s, ...),
   but only while uptime is under 10 minutes, so clicking the Desktop icon
   later opens the terminal at once;
2. starts `gnome-terminal-server` through systemd, which has no 25 s limit;
3. retries `gnome-terminal` up to 5 times, 10 s apart.

Check a boot with `journalctl --user -b | grep -E "StartCap|term_launch"`.

`fix_autostart_delay.sh [BASE] [STEP]` re-runs the conversion by hand.
Entries that don't call `gnome-terminal` (such as `lxterminal` entries from
the stock RMS script) are left unchanged.

## Not for Raspberry Pi

`add_GStation.sh` refuses to run on a Pi; use RMS's `add_Pi_Station.sh`.

## Licence

GPL-3.0. `add_GStation.sh` is based on RMS `Scripts/MultiCamLinux/add_GStation.sh`
(Copyright (C) 2023 Ed Harman).
