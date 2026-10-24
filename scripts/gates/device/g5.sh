# Gate 5: the bridge's footprint and wakeups, idle and with media sessions
# and Keel providers active. The release-gate record for the Rust bridge.
# G_VIDEO    a second media session, if installed (is.xyz.mpv)
# G_SECONDS  wakeup window per phase (60)

G_VIDEO=${G_VIDEO:-is.xyz.mpv}
G_SECONDS=${G_SECONDS:-60}
TEST=org.marathonos.deckard.notifytest

threads() {
    for t in /proc/"$1"/task/*; do
        printf '%s %s %s\n' "${t##*/}" "$(cut -d' ' -f3 "$t"/schedstat)" "$(cat "$t"/comm)"
    done
}

footprint() {
    pid=$(pidof deckard-bridge | awk '{print $1}')
    [ -n "$pid" ] || { step "footprint-$1" fail "deckard-bridge not running"; return; }
    threads "$pid" > "$G_TMP/threads-$1-begin.txt"
    sleep "$G_SECONDS"
    threads "$pid" > "$G_TMP/threads-$1-end.txt"
    {
        echo "label $1"
        echo "seconds $G_SECONDS"
        echo "threads $(ls /proc/"$pid"/task | wc -l)"
        awk '/^(Pss|Private_Dirty|Rss):/ {print tolower($1) " " $2}' /proc/"$pid"/smaps_rollup | tr -d :
        echo "bus_names $(as_user 'busctl --user list --no-legend' | awk -v p="$pid" '$1 ~ /^:/ && $2 == p' | wc -l)"
        echo "zbus_threads $(cat /proc/"$pid"/task/*/comm | grep -c '^zbus::')"
        echo "qt_libraries $(grep -c 'libQt6' /proc/"$pid"/maps)"
        echo "mpris $(as_user 'busctl --user list --no-legend' | grep -c '^org.mpris.MediaPlayer2')"
        echo "packages $(wc -l < "$G_ANDROID_DATA/system/packages.list")"
    } >> "$G_TMP/footprint.txt"
    step "footprint-$1" ok
}

need_android || exit 0
snapshot_state
footprint idle
android "am broadcast -a $TEST.POST --es kind media -n $TEST/.TestReceiver" > /dev/null
undo "android 'am broadcast -a $TEST.POST --es kind media_stop -n $TEST/.TestReceiver' > /dev/null"
sleep 3
footprint media-1
if installed "$G_VIDEO"; then
    launch_android "$G_VIDEO"
    sleep 6
    footprint media-2
else
    step media-2 skip "$G_VIDEO not installed"
fi
step gate5 ok
