#!/bin/bash
# Robust gnome-terminal launcher for autostart entries.
#
# Usage: term_launch.sh [-d BOOT_DELAY_S] <gnome-terminal args...>
#
# At login every autostart entry fires in the same second and each one asks
# D-Bus to activate gnome-terminal-server.  The server takes ~25 s to come up
# while the session is still settling, so every client hits the 25 s D-Bus
# activation timeout and no terminal opens.  This wrapper:
#   1. sleeps BOOT_DELAY_S, but only shortly after boot (uptime < 10 min),
#      so the same .desktop file still opens instantly from the desktop icon;
#   2. starts gnome-terminal-server through systemd, which waits for it
#      without the 25 s limit;
#   3. retries the gnome-terminal call a few times if it still fails.
# Output goes to the user journal (journalctl --user -t <entry name>).

delay=0
if [[ $1 == -d ]]; then
    delay=$2
    shift 2
fi

uptime_s=$(cut -d. -f1 /proc/uptime)
if (( uptime_s < 600 && delay > 0 )); then
    echo "uptime ${uptime_s}s: waiting ${delay}s before opening terminal"
    sleep "$delay"
fi

if ! timeout 120 systemctl --user start gnome-terminal-server.service; then
    echo "gnome-terminal-server did not start via systemd, trying anyway"
fi

for attempt in 1 2 3 4 5; do
    if gnome-terminal "$@"; then
        exit 0
    fi
    echo "gnome-terminal attempt $attempt failed, retrying in 10s"
    sleep 10
done

echo "giving up after 5 attempts: gnome-terminal $*"
exit 1
