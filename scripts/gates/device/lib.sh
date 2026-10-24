# Device side of the proof-gate harness, for busybox ash as root. The host
# streams this file followed by one gate script over ssh; results are written
# under a private directory and leave as a tar on the original stdout.
# Everything the run changes is undone at exit, newest first.

set -u
exec 3>&1 1>&2 0< /dev/null

G_TMP=$(mktemp -d /tmp/marathon-gates.XXXXXX)
G_TRACE=/sys/kernel/tracing/instances/marathon-gates
G_UNDO=$G_TMP/.undo
G_JOBS=$G_TMP/.jobs
: > "$G_UNDO"
: > "$G_JOBS"
: > "$G_TMP/steps.tsv"
: > "$G_TMP/marks.txt"
mkdir "$G_TMP/u" && chown user "$G_TMP/u" && chmod 711 "$G_TMP"
G_BUS="XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
G_LXC="-P /var/lib/waydroid/lxc -n waydroid"
G_ANDROID_DATA=/home/user/.local/share/waydroid/data
G_V3D_STATS=$(ls /sys/devices/platform/*/*.v3d/gpu_stats 2>/dev/null | head -n 1)
G_SHELL_PID=$(pidof marathon-shell-bin | awk '{print $1}')
G_RENDER_TID=""
[ -n "$G_SHELL_PID" ] && G_RENDER_TID=$(grep -l '^QSGRenderThread$' /proc/"$G_SHELL_PID"/task/*/comm 2>/dev/null |
    head -n 1 | cut -d/ -f5)

# step NAME ok|skip|fail DETAIL: every step is counted; nothing passes silently.
step() {
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$G_TMP/steps.tsv"
    echo "gates: $1 $2 ${3:-}"
}

undo() {
    printf '%s\n' "$*" | cat - "$G_UNDO" > "$G_UNDO.new" && mv "$G_UNDO.new" "$G_UNDO"
}

job() {
    echo "$1" >> "$G_JOBS"
}

now() {
    date +%s.%N
}

# mark LABEL: a phase boundary, in the trace (monotonic) and in wall time.
mark() {
    [ -w "$G_TRACE/trace_marker" ] && echo "GATE $*" > "$G_TRACE/trace_marker"
    echo "$(now) $*" >> "$G_TMP/marks.txt"
}

as_user() {
    su user -s /bin/sh -c "env $G_BUS $1" < /dev/null
}

shell_call() {
    as_user "busctl --user call org.marathonos.Shell /org/marathonos/Shell/$1 org.marathonos.Shell.${1}1 $2"
}

keel() {
    as_user "busctl --user call org.marathonos.Shell /org/shipwright/Keel/Actions org.shipwright.Keel.Actions Invoke ssa{sv} $1 '{}' 0" > /dev/null
}

# shell_state KEY: true or false, from the shell.state Keel action.
shell_state() {
    as_user "busctl --user call org.marathonos.Shell /org/shipwright/Keel/Actions org.shipwright.Keel.Actions Invoke ssa{sv} shell.state '{}' 0" |
        grep -o "$1[^,}]*" | grep -o -E 'true|false'
}

# power_key: a short press written into the phone's power-key device, which
# the shell reads (logind ignores the key on these images).
power_key() {
    dev=$(awk -v n="${G_POWER_NAME:-pwr_button}" '$0 == "N: Name=\"" n "\"" {f = 1}
        f && /^H:/ {for (i = 1; i <= NF; i++) if ($i ~ /^event/) print $i; exit}' /proc/bus/input/devices)
    [ -n "$dev" ] || return 1
    zero='\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0'
    syn="$zero\0\0\0\0\0\0\0\0"
    printf "$zero\001\0\164\0\001\0\0\0$syn" > /dev/input/"$dev" || return 1
    sleep 0.15
    printf "$zero\001\0\164\0\0\0\0\0$syn" > /dev/input/"$dev"
}

# screen_off: the shell's own screen-off (power key: lock and blank); undone
# by waking it and, if it was unlocked before, unlocking with G_PIN.
screen_off() {
    [ "$(shell_state screenOn)" = true ] || { step screen-off fail "screen already off"; return 1; }
    locked=$(shell_state locked)
    power_key || { step screen-off fail "no ${G_POWER_NAME:-pwr_button} input device"; return 1; }
    undo "screen_on $locked"
    sleep 2
    if [ "$(shell_state screenOn)" = false ]; then step screen-off ok; else step screen-off fail "screen still on"; return 1; fi
}

screen_on() {
    [ "$(shell_state screenOn)" = true ] || power_key
    sleep 2
    [ "$1" = false ] && as_user "busctl --user call org.marathonos.Shell /org/marathonos/Shell/Security org.marathonos.Shell.Security1 AuthenticateQuickPIN s ${G_PIN:-027602}" > /dev/null
    sleep 1
    [ "$(shell_state screenOn)" = true ] || step screen-on fail "screen still off"
    [ "$(shell_state locked)" = "$1" ] || step screen-on fail "lock state not restored"
}

android_up() {
    lxc-info $G_LXC -s 2>/dev/null | grep -q RUNNING
}

android() {
    lxc-attach $G_LXC --clear-env -- /system/bin/sh -c "export PATH=/system/bin:/system/xbin; $1" < /dev/null
}

# need_android: Android running, starting its session for the run if it was
# stopped (and stopping it again at exit).
need_android() {
    android_up && return 0
    as_user 'systemctl --user start deckard-session.service' ||
        { step android fail "deckard-session.service would not start"; return 1; }
    undo "as_user 'systemctl --user stop deckard-session.service'"
    t=0
    until android_up && [ "$(android 'getprop sys.boot_completed' 2>/dev/null)" = 1 ]; do
        [ "$t" -ge 180 ] && { step android fail "not booted after ${t}s"; return 1; }
        sleep 2
        t=$((t + 2))
    done
    sleep 10
    step android ok "session started for the run, booted in ${t}s"
}

installed() {
    grep -q "^$1 " "$G_ANDROID_DATA/system/packages.list"
}

# fdroid_add PKG: installs an F-Droid app the phone lacks through the Store's
# handler, removed again at exit; an app already there is left alone.
fdroid_add() {
    installed "$1" && return 0
    as_user "marathon-store-handler marathon-store://install/android:$1" ||
        { step "install-$1" fail "store handler refused"; return 1; }
    undo "fdroid_remove $1"
    t=0
    until installed "$1"; do
        [ "$t" -ge 300 ] && { step "install-$1" fail "not installed after ${t}s"; return 1; }
        sleep 1
        t=$((t + 1))
    done
    step "install-$1" ok "${t}s"
}

fdroid_remove() {
    installed "$1" || return 0
    as_user "marathon-store-handler marathon-store://uninstall/android:$1"
    t=0
    while installed "$1" && [ "$t" -lt 120 ]; do sleep 1; t=$((t + 1)); done
    installed "$1" && step "uninstall-$1" fail "still installed after ${t}s"
}

# Launchable Android packages, Deckard's own and microG left out.
android_apps() {
    ls /home/user/.local/share/applications/ | sed -n 's/^waydroid\.\(.*\)\.desktop$/\1/p' |
        grep -v -E '^(com\.google\.android\.gms|org\.marathonos\.deckard\..*)$'
}

touch_cmds() {
    printf '%s\n' "$@" | marathon-touchctl -
}

# touch_open: one touch device for the run, fed by touch_send through a FIFO,
# so no input hotplug lands inside a measured window.
touch_open() {
    mkfifo "$G_TMP/touch.fifo" || { step touch fail "mkfifo"; return 1; }
    marathon-touchctl - < "$G_TMP/touch.fifo" &
    job $!
    exec 5> "$G_TMP/touch.fifo"
    undo "exec 5>&-"
    sleep 1
}

touch_send() {
    printf '%s\n' "$@" >&5
}

foreground() {
    shell_call Navigation GetForegroundApp 2>/dev/null | sed 's/^s "//; s/"$//'
}

# Android packages with a running process, from the container's cgroups.
android_running() {
    grep -ah '' /proc/[0-9]*/cmdline 2>/dev/null | tr '\0' '\n' | grep -E '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$' | sort -u
}

# launch_android PKG [cold]: brings waydroid.PKG in front; with cold, after a force-stop.
launch_android() {
    [ "${2:-}" = cold ] && android "am force-stop $1"
    echo "$1" >> "$G_TMP/.launched"
    shell_call Navigation "LaunchApp s waydroid.$1" > /dev/null
}

# Stops what the run started, so the phone ends as it began.
stop_launched() {
    for pkg in $(cat "$G_TMP/.launched" 2>/dev/null); do
        grep -qx "$pkg" "$G_TMP/running-before.txt" || android "am force-stop $pkg"
    done
}

snapshot_state() {
    foreground > "$G_TMP/foreground-before.txt"
    android_running > "$G_TMP/running-before.txt"
    : > "$G_TMP/.launched"
    undo stop_launched
    undo restore_foreground
}

restore_foreground() {
    fg=$(cat "$G_TMP/foreground-before.txt")
    if [ -n "$fg" ]; then
        shell_call Navigation "LaunchApp s $fg" > /dev/null
    else
        keel shell.home
    fi
}

# video_ready: G_VIDEO installed and a 5 min 30 fps test video in Movies,
# both removed at exit.
video_ready() {
    fdroid_add "$G_VIDEO" || return 1
    movies=$G_ANDROID_DATA/media/0/Movies
    mkdir -p "$movies"
    ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=s=480x360:r=30 -t 300 -c:v libx264 -preset ultrafast \
        -pix_fmt yuv420p -y "$movies/gates.mp4" && chown 1023:1023 "$movies/gates.mp4" &&
        undo "rm -f $movies/gates.mp4" || { step video-file fail ffmpeg; return 1; }
    android "pm grant $G_VIDEO android.permission.READ_MEDIA_VIDEO; pm grant $G_VIDEO android.permission.READ_EXTERNAL_STORAGE" > /dev/null 2>&1
    step video-file ok
}

# video_play: G_VIDEO in front, playing the test video.
video_play() {
    launch_android "$G_VIDEO"
    sleep 4
    android "am start -a android.intent.action.VIEW -d file:///sdcard/Movies/gates.mp4 -t video/mp4 -p $G_VIDEO" > /dev/null
    sleep 6
    if android 'dumpsys media_session' | grep -q 'state=PlaybackState {state=3'; then
        step video-playing ok
    else
        step video-playing fail "no playing media session: the video may not be running"
        return 1
    fi
}

# trace_start: a private tracefs instance (the global tracer is left alone)
# with vblanks, GPU job submissions (the ioctl, so in the submitting
# process; v3d_submit_cl fires in the scheduler's kthread) and, when the shell runs, its GUI and render
# threads' context switches.
trace_start() {
    [ -d /sys/kernel/tracing/instances ] || { step tracefs skip "no tracefs"; return 1; }
    mkdir "$G_TRACE" 2> /dev/null || { step tracefs fail "instance $G_TRACE exists or mkdir failed"; return 1; }
    undo trace_stop
    echo mono > "$G_TRACE/trace_clock"
    echo "${G_TRACE_KB:-16384}" > "$G_TRACE/buffer_size_kb"
    ev=$G_TRACE/events
    echo 'crtc == 0' > "$ev/drm/drm_vblank_event_delivered/filter"
    echo 1 > "$ev/drm/drm_vblank_event_delivered/enable"
    [ -d "$ev/v3d/v3d_submit_cl_ioctl" ] && echo 1 > "$ev/v3d/v3d_submit_cl_ioctl/enable"
    echo 1 > "$G_TRACE/options/record-tgid"
    if [ -n "$G_SHELL_PID" ] && [ "${G_SCHED:-1}" = 1 ]; then
        f="prev_pid == $G_SHELL_PID || next_pid == $G_SHELL_PID"
        [ -n "$G_RENDER_TID" ] && f="$f || prev_pid == $G_RENDER_TID || next_pid == $G_RENDER_TID"
        echo "$f" > "$ev/sched/sched_switch/filter"
        echo 1 > "$ev/sched/sched_switch/enable"
    fi
    echo "gui=$G_SHELL_PID render=$G_RENDER_TID" > "$G_TMP/threads.txt"
    echo 1 > "$G_TRACE/tracing_on"
    cat "$G_TRACE/trace_pipe" > "$G_TMP/trace.txt" &
    job $!
    step tracefs ok "gui=$G_SHELL_PID render=$G_RENDER_TID"
}

trace_stop() {
    [ -d "$G_TRACE" ] || return 0
    echo 0 > "$G_TRACE/tracing_on"
    echo 0 > "$G_TRACE/events/enable"
    grep -H overrun "$G_TRACE"/per_cpu/cpu*/stats > "$G_TMP/trace-overrun.txt" 2>/dev/null
    for j in $(cat "$G_JOBS"); do
        grep -q trace_pipe /proc/"$j"/cmdline 2>/dev/null && kill "$j" 2>/dev/null
    done
    sleep 0.2
    rmdir "$G_TRACE" || step tracefs fail "cannot remove $G_TRACE"
}

# sample SECONDS LABEL: CPU, PSI, GPU and container cgroup counters every
# G_INTERVAL seconds. Per-process totals come from snapshot at each end.
sample() {
    out=$G_TMP/samples-$2.txt
    end=$(($(date +%s) + $1))
    while [ "$(date +%s)" -lt "$end" ]; do
        echo "T $(now)" >> "$out"
        grep -H '' /proc/stat /proc/pressure/cpu /proc/pressure/memory /proc/interrupts $G_V3D_STATS \
            /sys/fs/cgroup/lxc.payload.*/cpu.stat /sys/fs/cgroup/lxc.payload.*/*/cpu.stat \
            /sys/fs/cgroup/lxc.payload.*/memory.events 2> /dev/null |
            grep -vE '^/proc/stat:(intr|softirq)' >> "$out"
        sleep "${G_INTERVAL:-1}"
    done
}

# snapshot LABEL: every process's CPU time and run count, for per-process
# use between two snapshots.
snapshot() {
    {
        echo "T $(now)"
        grep -H '' /proc/[0-9]*/stat /proc/[0-9]*/schedstat 2> /dev/null
    } > "$G_TMP/snapshot-$1.txt"
}

# Process names and cgroups, and each GPU client's engine time (fdinfo).
inventory() {
    out=$G_TMP/inventory-$1.txt
    {
        echo "T $(now)"
        grep -H '' /proc/[0-9]*/comm /proc/[0-9]*/cgroup 2> /dev/null
        grep -Ha '' /proc/[0-9]*/cmdline 2> /dev/null | tr '\0' ' '
        echo
        ls -l /proc/[0-9]*/fd 2> /dev/null | awk '/^\/proc/ {d=$1} /-> \/dev\/dri\/renderD/ {sub(":","",d); sub("/fd","",d); print d "/fdinfo/" $(NF-2)}' |
            xargs -r grep -H -E 'drm-(engine|client-id)' 2> /dev/null
    } > "$out"
}

# dbus_watch RULE...: dbus-monitor on the session bus, as the session's user.
dbus_watch() {
    {
        echo 'echo $$ > "$(dirname "$0")/dbus.pid"'
        printf 'exec env %s dbus-monitor --session' "$G_BUS"
        for rule in "$@"; do printf " \"%s\"" "$rule"; done
        echo
    } > "$G_TMP/u/dbus.sh"
    su user -s /bin/sh "$G_TMP/u/dbus.sh" > "$G_TMP/dbus.txt" 2>&1 &
    sleep 1
    pid=$(cat "$G_TMP/u/dbus.pid" 2>/dev/null)
    [ -n "$pid" ] || { step dbus-monitor fail "did not start"; return 1; }
    undo "kill $pid"
    step dbus-monitor ok "pid $pid"
}

finish() {
    while read -r cmd <&4; do eval "$cmd" < /dev/null || step undo fail "$cmd"; done 4< "$G_UNDO"
    for j in $(cat "$G_JOBS"); do kill "$j" 2>/dev/null; done
    uname -a > "$G_TMP/uname.txt"
    tar -C "$G_TMP" -cf - . >&3
    rm -rf "$G_TMP"
}
trap finish EXIT
trap 'exit 130' INT TERM HUP
