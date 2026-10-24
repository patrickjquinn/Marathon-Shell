# Gate 4: frame pacing and GUI-thread stalls of a Hub edge peek, alone and
# while an Android app cold-launches.
# G_LAUNCH  Android package cold-launched under the peek (com.android.settings)
# G_REPS    peeks per phase (10)
# G_PEEK    "x1 y1 x2 y2" edge swipe, short and slow enough that the Hub
#           springs back closed (0 360 150 360)
# G_DELAY   ms between launch request and peek (150)

G_LAUNCH=${G_LAUNCH:-com.android.settings}
G_REPS=${G_REPS:-10}
G_PEEK=${G_PEEK:-0 360 150 360}
G_DELAY=${G_DELAY:-150}

peek() {
    mark "$1 begin"
    touch_send "swipe $G_PEEK 120"
    sleep 0.5
    mark "$1 end"
}

need_android || exit 0
[ -n "$G_SHELL_PID" ] || { step shell skip "marathon-shell-bin not running"; exit 0; }
snapshot_state
touch_open || exit 0
trace_start
keel shell.home
sleep 3

i=0
while [ "$i" -lt "$G_REPS" ]; do
    i=$((i + 1))
    peek "peek-baseline-$i"
    sleep 2
done

i=0
while [ "$i" -lt "$G_REPS" ]; do
    i=$((i + 1))
    android "am force-stop $G_LAUNCH"
    sleep 1
    mark "launch-$i begin"
    launch_android "$G_LAUNCH" &
    L=$!
    usleep $((G_DELAY * 1000))
    peek "peek-launch-$i"
    wait "$L"
    sleep 4
    mark "launch-$i end"
    keel shell.home
    sleep 2
done
trace_stop
step gate4 ok
