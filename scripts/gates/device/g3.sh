# Gate 3: whether Android tasks keep rendering and committing while they are
# only covers in the task switcher, or hidden behind the home grid.
# G_APPS      5 static Android packages to open (installed launchables)
# G_VIDEO     F-Droid video player installed for the run if absent (is.xyz.mpv)
# G_SECONDS   window per phase (60)

G_VIDEO=${G_VIDEO:-is.xyz.mpv}
G_SECONDS=${G_SECONDS:-60}
MOVIES=$G_ANDROID_DATA/media/0/Movies

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

fdroid_add "$G_VIDEO" || exit 0
mkdir -p "$MOVIES"
ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=s=480x360:r=30 -t 300 -c:v libx264 -preset ultrafast \
    -pix_fmt yuv420p -y "$MOVIES/gates.mp4" && chown 1023:1023 "$MOVIES/gates.mp4" &&
    undo "rm -f $MOVIES/gates.mp4" && step video-file ok || { step video-file fail ffmpeg; exit 0; }
android "pm grant $G_VIDEO android.permission.READ_MEDIA_VIDEO; pm grant $G_VIDEO android.permission.READ_EXTERNAL_STORAGE" > /dev/null 2>&1

trace_start
for pkg in $apps; do
    launch_android "$pkg"
    sleep 6
done
keel shell.switcher
sleep 5
window static-switcher

launch_android "$G_VIDEO"
sleep 4
android "am start -a android.intent.action.VIEW -d file:///sdcard/Movies/gates.mp4 -t video/mp4 -p $G_VIDEO" > /dev/null
sleep 6
if android 'dumpsys media_session' | grep -q 'state=PlaybackState {state=3'; then
    step video-playing ok
else
    step video-playing fail "no playing media session: the video may not be running"
fi
keel shell.switcher
sleep 5
window video-switcher
keel shell.home
sleep 5
window video-home
trace_stop
step gate3 ok
