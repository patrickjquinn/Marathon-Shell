# Gate 1: keyboard round trips and frame pacing, idle and under load: an
# F-Droid install, Android notification bursts with 1024 px pictures, and a
# session client's notifications carrying 1024 px image-data.
# G_IME_APP  Android package with a text field (net.gsantner.markor)
# G_FOCUS    "x y" tap that focuses its text field (optional)
# G_KEY      "x y" of a letter key on Marathon's keyboard (required)
# G_BKSP     "x y" of its backspace key (required)
# G_KEYS     keystrokes per phase (300: 30 s at 10 Hz)
# G_DRAG     "x1 y1 x2 y2" home-screen drag, reversed on alternate swipes
#            (600 360 120 360)
# G_SWIPES   drags per frame phase (40)
# G_NOTIFY   Android notifications per burst (20)
# G_IMAGES   image-data notifications per image phase (5)
# G_SIDE     their width and height (1024)
# G_INSTALL  F-Droid package, absent from the phone, installed during each
#            pressure phase and removed after (org.fdroid.fdroid)

G_IME_APP=${G_IME_APP:-net.gsantner.markor}
G_KEYS=${G_KEYS:-300}
G_DRAG=${G_DRAG:-600 360 120 360}
G_SWIPES=${G_SWIPES:-40}
G_NOTIFY=${G_NOTIFY:-20}
G_IMAGES=${G_IMAGES:-5}
G_SIDE=${G_SIDE:-1024}
G_INSTALL=${G_INSTALL:-org.fdroid.fdroid}
PNG=$G_ANDROID_DATA/local/tmp/gates-1024.png

keystrokes() {
    i=0
    while [ "$i" -lt "$1" ]; do
        echo "tap $G_KEY"
        echo "sleep 20"
        echo "tap $G_BKSP"
        echo "sleep 20"
        i=$((i + 2))
    done | marathon-touchctl -
}

drags() {
    set -- $G_DRAG
    i=0
    while [ "$i" -lt "$G_SWIPES" ]; do
        if [ $((i % 2)) = 0 ]; then echo "swipe $1 $2 $3 $4 120"; else echo "swipe $3 $4 $1 $2 120"; fi
        echo "sleep 150"
        i=$((i + 1))
    done | marathon-touchctl -
}

shell_notes() {
    android 'dumpsys notification --noredact' | grep -c 'pkg=com.android.shell'
}

burst() {
    mark "burst-$1 begin"
    android "i=0; while [ \$i -lt $G_NOTIFY ]; do i=\$((i+1)); cmd notification post -t \"Gate \$i\" -I file:///data/local/tmp/gates-1024.png -S bigpicture --picture file:///data/local/tmp/gates-1024.png gates\$i \"Gate burst \$i\" > /dev/null; done"
    mark "burst-$1 end"
    n=$(shell_notes)
    if [ "$n" -gt 0 ]; then step "burst-$1" ok "$n posted"; else step "burst-$1" fail "nothing posted"; fi
}

cancel_bursts() {
    android 'service call notification 1 s16 com.android.shell i32 0 > /dev/null'
    sleep 2
    left=$(shell_notes)
    [ "$left" = 0 ] || step cleanup-notifications fail "$left left in Android"
}

# images LABEL: G_IMAGES Notify calls with G_SIDE px image-data from a session
# client, each reply's wall time and latency logged, the notifications
# closed after.
images() {
    command -v python3 > /dev/null && python3 -c 'import gi' 2> /dev/null ||
        { step "images-$1" skip "no python3 with PyGObject to send image-data"; return 0; }
    cat > "$G_TMP/u/notify.py" <<'EOF'
import sys, time
from gi.repository import Gio, GLib
side, count = int(sys.argv[1]), int(sys.argv[2])
V = GLib.Variant
pixels = GLib.Bytes.new(bytes(range(256)) * (side * side * 4 // 256))
image = V.new_tuple(V("i", side), V("i", side), V("i", side * 4), V("b", True), V("i", 8), V("i", 4),
                    V.new_from_bytes(GLib.VariantType("ay"), pixels, True))
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
for i in range(count):
    body = V.new_tuple(V("s", "gates"), V("u", 0), V("s", ""), V("s", f"Gate image {i}"), V("s", "image-data"),
                       V("as", []), V("a{sv}", {"image-data": image}), V("i", -1))
    t = time.monotonic()
    reply = bus.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                          "org.freedesktop.Notifications", "Notify", body, GLib.VariantType("(u)"),
                          Gio.DBusCallFlags.NONE, 60000, None)
    print(f"{time.time():.6f} {reply.unpack()[0]} {(time.monotonic() - t) * 1000:.1f}", flush=True)
    time.sleep(1)
EOF
    chmod 644 "$G_TMP/u/notify.py"
    while :; do
        while read -r k v _; do [ "$k" = VmRSS: ] && echo "$v"; done < /proc/"$G_SHELL_PID"/status
        usleep 50000
    done > "$G_TMP/images-$1-rss.txt" &
    R=$!
    job $R
    sleep 1
    mark "images-$1 begin"
    as_user "python3 $G_TMP/u/notify.py $G_SIDE $G_IMAGES" >> "$G_TMP/images-$1.txt" ||
        step "images-$1" fail "Notify failed"
    mark "images-$1 end"
    kill "$R"
    for id in $(awk '{print $2}' "$G_TMP/images-$1.txt"); do
        as_user "busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications CloseNotification u $id" > /dev/null
    done
    n=$(wc -l < "$G_TMP/images-$1.txt")
    if [ "$n" = "$G_IMAGES" ]; then step "images-$1" ok "$n sent"; else step "images-$1" fail "$n of $G_IMAGES sent"; fi
}

install_start() {
    [ "$INSTALL" = yes ] || return 0
    mark "install begin"
    as_user "marathon-store-handler marathon-store://install/android:$G_INSTALL" || step install fail "store handler refused"
}

install_wait() {
    [ "$INSTALL" = yes ] || return 0
    t=0
    until installed "$G_INSTALL"; do
        [ "$t" -ge 300 ] && { step install fail "not installed after ${t}s"; return 1; }
        sleep 1
        t=$((t + 1))
    done
    mark "install end"
    step install ok "${t}s"
}

need_android || exit 0
[ -n "${G_KEY:-}" ] && [ -n "${G_BKSP:-}" ] || { step keys skip "G_KEY and G_BKSP not set (calibrate from a screenshot)"; exit 0; }
snapshot_state
INSTALL=yes
installed "$G_INSTALL" && { INSTALL=no; step install skip "$G_INSTALL already installed: set G_INSTALL to an absent F-Droid app"; }

ffmpeg -nostdin -loglevel error -f lavfi \
    -i "nullsrc=s=1024x1024,format=rgb24,geq=r='random(1)*255':g='random(2)*255':b='random(3)*255'" \
    -frames:v 1 -y "$PNG" && chmod 644 "$PNG" && undo "rm -f $PNG" || { step png fail "ffmpeg"; exit 0; }
step png ok "$(stat -c %s "$PNG") bytes"
undo cancel_bursts
[ "$INSTALL" = yes ] && undo "fdroid_remove $G_INSTALL"

OWNER=$(as_user 'busctl --user status org.freedesktop.Notifications' | sed -n 's/^UniqueName=//p')
dbus_watch "type='signal',interface='org.marathonos.Shell.TextInput1'" \
    "type='method_call',interface='org.marathonos.Shell.TextInput1'" \
    "type='method_call',interface='org.freedesktop.Notifications',member='Notify'" \
    "type='method_return',sender='$OWNER'" || exit 0
trace_start

launch_android "$G_IME_APP"
sleep 6
[ -n "${G_FOCUS:-}" ] && touch_cmds "tap $G_FOCUS" && sleep 2
mark "preflight begin"
keystrokes 4
sleep 2
mark "preflight end"
if [ "$(grep -c 'member=CommitString' "$G_TMP/dbus.txt")" -gt 0 ] &&
    [ "$(grep -c 'member=SetSurroundingText' "$G_TMP/dbus.txt")" -gt 0 ]; then
    step preflight ok "keyboard reaches $G_IME_APP and it reports back"
else
    step preflight fail "no CommitString/SetSurroundingText pair: keyboard not up in an Android editor"
    exit 0
fi

snapshot keys-baseline-begin
mark "keys-baseline begin"
keystrokes "$G_KEYS"
mark "keys-baseline end"
snapshot keys-baseline-end
sleep 3

snapshot keys-pressure-begin
mark "keys-pressure begin"
install_start
keystrokes "$G_KEYS" &
K=$!
sleep 2
burst 1
sleep 8
burst 2
wait "$K"
mark "keys-pressure end"
snapshot keys-pressure-end
install_wait
cancel_bursts
sleep 3

mark "keys-images begin"
keystrokes "$G_KEYS" &
K=$!
sleep 2
images keys
wait "$K"
mark "keys-images end"
sleep 3

keel shell.home
sleep 2
mark "drag-baseline begin"
drags
mark "drag-baseline end"
sleep 3

[ "$INSTALL" = yes ] && fdroid_remove "$G_INSTALL"
sleep 2
mark "drag-pressure begin"
install_start
drags &
D=$!
sleep 1
burst 3
sleep 4
burst 4
wait "$D"
mark "drag-pressure end"
install_wait
cancel_bursts
sleep 3

mark "drag-images begin"
drags &
D=$!
sleep 1
images drag
wait "$D"
mark "drag-images end"
trace_stop
step gate1 ok
