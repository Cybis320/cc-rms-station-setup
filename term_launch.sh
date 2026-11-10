#!/bin/bash
# Robust terminal launcher for autostart entries.
#
# Usage: term_launch.sh [-d BOOT_DELAY_S] [-t TERMINAL] <terminal args...>
#        TERMINAL: gnome-terminal (default), ptyxis or lxterminal
#
# At login every autostart entry fires in the same second and each one asks
# D-Bus to activate the terminal server (gnome-terminal-server, or Ptyxis).
# The server takes ~25 s to come up while the session is still settling, so
# every client hits the 25 s D-Bus activation timeout and no terminal opens.
# This wrapper:
#   1. sleeps BOOT_DELAY_S, but only shortly after boot (uptime < 10 min),
#      so the same .desktop file still opens instantly from the desktop icon;
#   2. starts the terminal server without the 25 s limit (gnome-terminal via
#      systemd, Ptyxis via a D-Bus activation call with a long timeout);
#   3. retries the terminal call a few times if it still fails.
# Output goes to the user journal (journalctl --user -t <entry name>).

delay=0
term=gnome-terminal
while [[ $1 == -d || $1 == -t ]]; do
    case $1 in
        -d) delay=$2 ;;
        -t) term=$2 ;;
    esac
    shift 2
done

uptime_s=$(cut -d. -f1 /proc/uptime)
if (( uptime_s < 600 && delay > 0 )); then
    echo "uptime ${uptime_s}s: waiting ${delay}s before opening $term"
    sleep "$delay"
fi

case $term in
    gnome-terminal)
        timeout 120 systemctl --user start gnome-terminal-server.service \
            || echo "gnome-terminal-server did not start via systemd, trying anyway" ;;
    ptyxis)
        timeout 130 gdbus call --session --timeout 120 \
            --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.StartServiceByName org.gnome.Ptyxis 0 >/dev/null \
            || echo "Ptyxis did not start via D-Bus, trying anyway" ;;
esac

for attempt in 1 2 3 4 5; do
    if "$term" "$@"; then
        exit 0
    fi
    echo "$term attempt $attempt failed, retrying in 10s"
    sleep 10
done

echo "giving up after 5 attempts: $term $*"
exit 1
