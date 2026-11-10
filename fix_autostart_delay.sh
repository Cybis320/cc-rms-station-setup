#!/bin/bash
# Switch existing *_StartCap.desktop autostart entries to term_launch.sh
# (boot delay + wait for gnome-terminal-server + retries).
#
# - Entries calling gnome-terminal, ptyxis or lxterminal directly get the launcher with a staggered
#   boot delay: BASE + STEP * position (alphabetical order).
# - Entries already using a term_launch.sh elsewhere are repointed to this
#   checkout's copy, keeping their delay.
# - Anything else is left unchanged.
# Safe to run any number of times; run by install.sh and the hourly updater.
#
# Usage: fix_autostart_delay.sh [BASE_DELAY_S] [STEP_S]     (defaults 30 10)

base=${1:-30}
step=${2:-10}
here=$(cd "$(dirname "$0")" && pwd)
wrapper="$here/term_launch.sh"
autostart=~/.config/autostart

if [[ ! -f $wrapper ]]; then
    echo "Missing $wrapper"
    exit 1
fi
chmod +x "$wrapper"

backup="$autostart/backup_$(date -u +%Y%m%d-%H%M%S)"
saved=0
save() { mkdir -p "$backup"; cp -p "$1" "$backup/"; saved=1; }

i=0
for f in $(ls "$autostart"/*_StartCap.desktop 2>/dev/null | sort); do
    name=$(basename "$f")
    if grep -q "^Exec=$wrapper " "$f"; then
        echo "ok    $name"
        i=$((i + 1))
    elif grep -q "^Exec=[^ ]*/term_launch.sh " "$f"; then
        save "$f"
        sed -i "s|^Exec=[^ ]*/term_launch.sh |Exec=$wrapper |" "$f"
        echo "moved $name (now uses $wrapper)"
        i=$((i + 1))
    elif term=$(sed -n 's/^Exec=\(gnome-terminal\|ptyxis\|lxterminal\) .*/\1/p' "$f" | head -n1) \
            && [[ -n $term ]]; then
        save "$f"
        delay=$((base + step * i))
        sed -i "s|^Exec=$term |Exec=$wrapper -d $delay -t $term |" "$f"
        echo "fixed $name ($term, boot delay ${delay}s)"
        i=$((i + 1))
    else
        echo "skip  $name (Exec is not gnome-terminal/ptyxis/lxterminal, left unchanged)"
    fi
done

(( saved )) && echo "Originals backed up in $backup"
exit 0
