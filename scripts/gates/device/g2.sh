# Gate 2: what hidden Android apps cost, on the home grid and screen off.
# G_APPS        Android packages to open and hide (the launchable ones)
# G_EXTRA       F-Droid apps installed for the run when fewer than 8 are
#               launchable (org.wikipedia de.danoeh.antennapod org.videolan.vlc
#               org.mozilla.fennec_fdroid)
# G_ON_SECONDS  screen-on window per phase (600)
# G_OFF_SECONDS screen-off window (3600)
# G_INTERVAL    seconds between counter samples (5)

G_EXTRA=${G_EXTRA:-org.wikipedia de.danoeh.antennapod org.videolan.vlc org.mozilla.fennec_fdroid}
G_ON_SECONDS=${G_ON_SECONDS:-600}
G_OFF_SECONDS=${G_OFF_SECONDS:-3600}
G_INTERVAL=${G_INTERVAL:-5}

kills() {
    {
        echo "T $(now) $1"
        grep -H '' /sys/fs/cgroup/lxc.payload.*/memory.events
        dmesg | grep -c -E 'Out of memory|oom-kill' | sed 's/^/host_oom /'
        android 'logcat -d -b events' | grep -c -E 'am_kill|lmk' | sed 's/^/android_kills /'
    } >> "$G_TMP/kills.txt"
}

window() {
    snapshot "$1-begin"
    inventory "$1-begin"
    kills "$1-begin"
    mark "$1 begin"
    sample "$2" "$1"
    mark "$1 end"
    kills "$1-end"
    inventory "$1-end"
    snapshot "$1-end"
}

need_android || exit 0
snapshot_state
android 'dumpsys activity settings' | sed -n 's/^ *use_freezer=//p' > "$G_TMP/use-freezer.txt"
apps=${G_APPS:-$(android_apps)}
for pkg in $G_EXTRA; do
    [ "$(echo $apps | wc -w)" -ge 8 ] && break
    echo " $apps " | grep -q " $pkg " && continue
    fdroid_add "$pkg" && apps="$apps $pkg"
done
n=$(echo $apps | wc -w)
if [ "$n" -ge 8 ]; then step apps ok "$n"; else step apps skip "only $n Android apps, the gate asks for 8"; fi
echo "$apps" > "$G_TMP/apps.txt"
G_SCHED=0 trace_start

keel shell.home
sleep 5
window idle-baseline "$G_ON_SECONDS"

for pkg in $apps; do
    launch_android "$pkg"
    sleep 8
done
keel shell.home
sleep 15
window hidden-screen-on "$G_ON_SECONDS"

if [ "$G_OFF_SECONDS" -gt 0 ] && screen_off; then
    sleep 5
    window hidden-screen-off "$G_OFF_SECONDS"
elif [ "$G_OFF_SECONDS" = 0 ]; then
    step screen-off skip "G_OFF_SECONDS=0"
fi
trace_stop
step gate2 ok
