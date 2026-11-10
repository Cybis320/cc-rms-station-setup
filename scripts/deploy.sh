#!/usr/bin/env bash
#
# Setup step run by install.sh. Idempotent:
#   - creates stations.csv from the blank template if missing
#   - converts existing StartCap autostart entries to term_launch.sh
#   - registers the checkout with the shared hourly cc-utils updater
# Adding stations is a separate, explicit step: fill stations.csv, then run
# add_GStation.sh.
#
set -euo pipefail

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC_TOOL=station_setup
# shellcheck source=../cc-utils/lib.sh
. "$DEST/cc-utils/lib.sh"

chmod +x "$DEST"/*.sh "$DEST"/scripts/*.sh

if [ ! -f "$DEST/stations.csv" ]; then
    cp "$DEST/stations.example.csv" "$DEST/stations.csv"
    cc_info "Created $DEST/stations.csv (blank; one station_id per line)"
fi

cc_info "Checking StartCap autostart entries"
"$DEST/fix_autostart_delay.sh"

cc_install_updater "$DEST/cc-utils"
cc_mark_applied "$DEST"

echo
cc_info "Done. To add stations on this machine:"
cc_info "    nano $DEST/stations.csv"
cc_info "    $DEST/add_GStation.sh [RMS_data_dir]"
