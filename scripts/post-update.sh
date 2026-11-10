#!/usr/bin/env bash
# Run by the cc-utils hourly updater after it pulls new code: as the user,
# unattended, possibly with no display. Re-applies the autostart fix so a
# change to the launcher or the fixer reaches every station.
set -euo pipefail

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chmod +x "$DEST"/*.sh "$DEST"/scripts/*.sh
[ -f "$DEST/stations.csv" ] || cp "$DEST/stations.example.csv" "$DEST/stations.csv"
"$DEST/fix_autostart_delay.sh"
