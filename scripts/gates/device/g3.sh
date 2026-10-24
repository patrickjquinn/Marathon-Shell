# Gate 3: whether Android tasks keep rendering and committing while they are
# only covers in the task switcher, or hidden behind the home grid.
# G_APPS      5 static Android packages to open (installed launchables)
# G_VIDEO     F-Droid video player installed for the run if absent (is.xyz.mpv)
# G_SECONDS   window per phase (60)

G_VIDEO=${G_VIDEO:-is.xyz.mpv}
G_SECONDS=${G_SECONDS:-60}

layers() {
    android 'dumpsys SurfaceFlinger --list' > "$G_TMP/sf-layers-$1.txt"
    for pkg in $apps $G_VIDEO; do
        grep -F "$pkg" "$G_TMP/sf-layers-$1.txt" | grep -v -E '^(Surface\(|Bounds for)' | while read -r layer; do
            echo "L $layer"
            android "dumpsys SurfaceFlinger --latency '$layer'"
        done
    done > "$G_TMP/sf-latency-$1.txt"
}

window() {
    inventory "$1-begin"
    mark "$1 begin"
    sample "$G_SECONDS" "$1"
    mark "$1 end"
    layers "$1"
    inventory "$1-end"
}

need_android || exit 0
snapshot_state
apps=${G_APPS:-$(android_apps | head -n 5)}
echo "$apps $G_VIDEO" > "$G_TMP/apps.txt"

video_ready || exit 0

trace_start
for pkg in $apps; do
    launch_android "$pkg"
    sleep 6
done
keel shell.switcher
sleep 5
window static-switcher

video_play
keel shell.switcher
sleep 5
window video-switcher
keel shell.home
sleep 5
window video-home
trace_stop
step gate3 ok
