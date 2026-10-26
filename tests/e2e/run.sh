#!/usr/bin/env bash
# End-to-end flows against the real shell binary under Xvfb. See README.md.
#   tests/e2e/run.sh [flow...]     (default: all flows, in order)
set -u
. "$(dirname "$0")/lib.sh"

E2E_PIN6=135724
E2E_PIN4=2580
NOTIFY_HINTS="{'desktop-entry': <'messages'>}"

rm -rf "$E2E_OUT/shots"
mkdir -p "$E2E_OUT"
e2e_snapshot_bins || { e2e_log "cannot copy the shell binaries from $E2E_BUILD"; exit 1; }

# --- helpers -------------------------------------------------------------
pill_back() { e2e_swipe 195 822 40 822 300; }
pill_up() { e2e_swipe 195 822 195 450 300; }
hub_peek() { e2e_swipe 1 420 260 420 400; }
qs_pull() { e2e_swipe 195 2 195 640 450; }
# Setup's bar names itself on the first and last beats; the ones between show progress.
oobe_showing() { e2e_a11y | grep -qE "	(Begin setup|Go home|Step [0-9] of 5)\$"; }
home_showing() { e2e_showing "Open apps" && ! oobe_showing; }
locked() { ! e2e_showing "Open apps" && ! oobe_showing; }

go_home() {
    local i
    for i in 1 2 3; do
        home_showing && ! cards_left && return 0
        pill_up
    done
    home_showing
}

enter_pin() { # digits [submit]
    local i
    for ((i = 0; i < ${#1}; i++)); do e2e_tap_name "${1:i:1}" || return 1; done
    [ -n "${2:-}" ] && e2e_tap_name Unlock
    sleep 1.2
}

unlock() {
    e2e_swipe 195 700 195 250 300
    e2e_wait_showing Unlock "" 5 || return 1
    enter_pin "$1" "${2:-}"
    e2e_wait_showing "Open apps" "" 5
}

security() { e2e_shell Security Security1 GetState; }
has_pin() { security | grep -q "'hasQuickPIN': <true>"; }
failed_attempts() { security | grep -q "'failedAttempts': <$1>"; }
not() { ! "$@"; }
heading() { e2e_a11y | grep -q "	heading	$1\$"; }
app_text() { e2e_a11y | grep -q "^marathon-app-runner	\(text\|entry\|paragraph\)	.*$1"; }
wait_heading() {
    local i
    for i in $(seq $((${2:-5} * 4))); do heading "$1" && return 0; sleep 0.25; done
    return 1
}
# Percentage of differing pixels inside a region of two shots: a b x y w h
region_diff() {
    magick compare -metric AE -fuzz 10% "$1[${5}x${6}+${3}+${4}]" "$2[${5}x${6}+${3}+${4}]" null: 2>&1 |
        awk -v t=$(($5 * $6)) '{printf "%d", ($1 * 100) / t}'
}

# Writes a quick PIN the way SecurityManager::storeQuickPIN does.
seed_pin() {
    python3 - "$1" "$E2E_HOME/.config/marathon/quickpin.conf" <<'EOF'
import hashlib, os, sys
pin, path = sys.argv[1], sys.argv[2]
salt = os.urandom(32)
h = salt + pin.encode()
for _ in range(10000):
    h = hashlib.sha256(h).digest()
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    f.write(salt.hex() + ":" + h.hex())
os.chmod(path, 0o600)
EOF
}

# Flows after pin4 need an unlocked shell; this provides one when they run alone.
ensure_session() {
    local pin
    pin=$(cat "$E2E_HOME/.e2e-pin" 2>/dev/null || echo $E2E_PIN6)
    e2e_alive && return 0
    if [ ! -f "$E2E_HOME/.config/marathon/quickpin.conf" ]; then
        flow_firstrun
        return
    fi
    e2e_session main || return 1
    if [ ${#pin} -lt 6 ]; then unlock "$pin" submit; else unlock "$pin"; fi
}

# Pages the home grid until an icon named $1 is showing.
find_icon() {
    local i
    for i in 1 2 3 4 5; do
        e2e_showing "$1" "Marathon Shell" && return 0
        e2e_swipe 330 450 60 450 250
    done
    for i in 1 2 3 4 5; do e2e_swipe 60 450 330 450 250; done
    return 1
}

app_mapped() { e2e_wait_since "Matched surfaceId [0-9]* to PID [0-9]* app \"$1\"" "${2:-20}"; }

# --- flows ---------------------------------------------------------------
flow_firstrun() {
    local f=firstrun
    e2e_reset_profile
    e2e_session firstrun || { e2e_check $f "shell starts" false; return; }
    e2e_shot oobe-hello
    e2e_check $f "setup says hello on first boot" e2e_showing "Begin setup"
    pill_up
    e2e_shot oobe-online
    e2e_check $f "a swipe up on the bar begins setup" e2e_showing "Step 1 of 5"
    e2e_tap_name "Not now"
    e2e_shot oobe-passcode
    e2e_check $f "Not now leaves getting online for later" e2e_showing "Step 2 of 5"
    enter_pin $E2E_PIN6
    e2e_shot oobe-confirm
    enter_pin 111111
    e2e_shot oobe-mismatch
    e2e_check $f "a mismatched confirmation is refused" e2e_showing "Passcodes don't match. Try again."
    enter_pin $E2E_PIN6
    e2e_shot oobe-look
    e2e_check $f "a matching passcode moves on" e2e_showing "Step 3 of 5"
    e2e_check $f "passcode stored" has_pin
    e2e_tap_name Continue
    e2e_shot oobe-size
    e2e_check $f "Continue keeps the wallpaper" e2e_showing "Step 4 of 5"
    e2e_tap_name Continue
    e2e_shot oobe-hub
    e2e_check $f "Continue keeps the size" e2e_showing "Step 5 of 5"
    hub_peek
    e2e_shot oobe-hub-peeked
    # The practice moves on 1.5 s after the peek; if the swipe missed, the
    # demo plays after 8 s and then offers Not now.
    if ! e2e_wait_showing "You're ready" "" 5; then
        e2e_wait_showing "Not now" "" 20 && e2e_tap_name "Not now"
    fi
    e2e_shot oobe-ready
    e2e_check $f "the Hub practice moves on" e2e_showing "Go home"
    pill_up
    e2e_wait_showing "Open apps" "" 5
    e2e_shot oobe-finished
    e2e_check $f "the flick up on the bar lands on the home screen" home_showing
}

flow_pin6() {
    local f=pin6
    e2e_session pin6 || { e2e_check $f "shell starts" false; return; }
    e2e_shot lock
    e2e_check $f "boots to the lock screen" locked
    e2e_swipe 195 700 195 250 300
    e2e_shot pin-pad
    e2e_check $f "swipe up shows the PIN pad" e2e_showing Unlock
    enter_pin 000000
    e2e_shot pin-wrong
    e2e_check $f "a wrong PIN is counted" failed_attempts 1
    e2e_check $f "wrong PIN keeps the pad up" e2e_showing Unlock
    enter_pin $E2E_PIN6
    e2e_wait_showing "Open apps" "" 5
    e2e_shot pin-unlocked
    e2e_check $f "right 6-digit PIN unlocks" home_showing
}

flow_pin4() {
    local f=pin4
    e2e_stop
    seed_pin $E2E_PIN4
    e2e_session pin4 || { e2e_check $f "shell starts" false; return; }
    e2e_swipe 195 700 195 250 300
    enter_pin $E2E_PIN4
    e2e_shot pin4-entered
    e2e_check $f "4 digits do not submit by themselves" e2e_showing Unlock
    e2e_tap_name Unlock 1.5
    e2e_wait_showing "Open apps" "" 5
    e2e_shot pin4-unlocked
    e2e_check $f "4-digit PIN unlocks with the Unlock key" home_showing
    echo $E2E_PIN4 >"$E2E_HOME/.e2e-pin"
}

flow_paging() {
    local f=paging
    ensure_session || { e2e_check paging "shell starts" false; return; }
    go_home
    e2e_shot home-p1
    e2e_check $f "page 1 shows Phone" e2e_showing Phone "Marathon Shell"
    e2e_swipe 330 450 60 450 250
    e2e_shot home-p2
    e2e_check $f "swipe left shows page 2 (Notes)" e2e_showing Notes "Marathon Shell"
    e2e_swipe 60 450 330 450 250
    e2e_shot home-p1-again
    e2e_check $f "swipe right returns to page 1" e2e_showing Messages "Marathon Shell"
}

# id:grid name
APPS=${E2E_APP_LIST:-"phone:Phone messages:Messages email:Mail browser:Browser store:App_Store music:Music
camera:Camera gallery:Gallery maps:Maps calendar:Calendar clock:Clock calculator:Calculator
notes:Notes settings:Settings terminal:Terminal"}

flow_apps() {
    local f=apps a id name
    ensure_session || { e2e_check apps "shell starts" false; return; }
    for a in $APPS; do
        id=${a%%:*}
        name=${a#*:}
        name=${name//_/ }
        go_home
        e2e_mark
        if find_icon "$name"; then
            e2e_tap_name "$name" "Marathon Shell" 0.3
        else
            e2e_log "$name not on the home grid; launching over D-Bus"
            E2E_RESULTS+=("NOTE  $f: $name has no home-grid icon")
            e2e_shell Navigation Navigation1 LaunchApp "$id" >/dev/null
        fi
        app_mapped "$id" 25
        local mapped=$?
        sleep 2.5
        if e2e_showing Allow; then
            e2e_shot "app-$id-permissions"
            e2e_tap_name Allow 1.5
            e2e_check $f "$name: Allow closes the permission prompt" not e2e_showing Allow
        fi
        e2e_shot "app-$id"
        e2e_check $f "$name launches and maps a surface" test $mapped -eq 0
        e2e_check $f "$name has no QML errors" not e2e_since_errors "$id"
        pill_back
        sleep 0.8
        e2e_shot "app-$id-back"
        e2e_check $f "$name: back from its first page goes home" home_showing
    done
}

cards_left() { e2e_a11y | grep -q "^Marathon Shell	push button	Close "; }

flow_switcher() {
    local f=switcher n
    ensure_session || { e2e_check switcher "shell starts" false; return; }
    go_home
    e2e_tap_name "Open apps" 1
    e2e_shot switcher
    n=$(e2e_a11y | grep -c "^Marathon Shell	push button	Close ")
    e2e_check $f "switcher lists running apps ($n)" test "$n" -gt 0
    e2e_mark
    e2e_tap 105 180 3
    e2e_shot switcher-open
    e2e_check $f "tapping a card brings its app forward" e2e_wait_since "Restoring running app\|Showing app window" 5
    pill_up
    e2e_tap_name "Open apps" 1
    local card i
    for i in $(seq 20); do
        card=$(e2e_a11y | sed -n 's/^Marathon Shell	push button	\(Close .*\)$/\1/p' | head -1)
        [ -n "$card" ] || break
        e2e_tap_name "$card" 0.8 || break
    done
    e2e_shot switcher-closed
    e2e_check $f "Close removes every card" not cards_left
}

flow_notifications() {
    local f=notifications id
    ensure_session || { e2e_check notifications "shell starts" false; return; }
    go_home
    e2e_mark
    hub_peek
    e2e_shot hub-empty
    e2e_check $f "left-edge swipe opens the Hub" e2e_wait_since "Peek gesture started" 1
    go_home
    e2e_mark
    e2e_notify messages "Sam Lee" "Running 10 minutes late" "[]" "$NOTIFY_HINTS" >/dev/null
    sleep 0.8
    e2e_shot banner
    e2e_check $f "Notify adds a notification" e2e_wait_since "Added notification: \"Sam Lee\"" 2
    e2e_mark
    e2e_tap 195 60 0.3
    e2e_wait_since "Matched surfaceId [0-9]* to PID [0-9]* app \"messages\"\|Restoring running app: \"messages\"" 20
    local opened=$?
    sleep 1.5
    e2e_shot banner-tapped
    e2e_check $f "tapping the banner opens Messages" test $opened -eq 0
    go_home
    e2e_notify messages "Ada" "Lunch?" "[]" "$NOTIFY_HINTS" >/dev/null
    sleep 6
    hub_peek
    e2e_shot hub-row
    e2e_mark
    e2e_swipe 120 140 385 140 250
    e2e_shot hub-dismissed
    e2e_check $f "swiping the Hub row dismisses it" e2e_wait_since "Dismissed notification" 2
    id=$(sqlite3 "$E2E_HOME/.local/share/Marathon OS/Marathon Shell/notifications.db" \
        "select count(*) from notifications where dismissed = 0" 2>/dev/null)
    e2e_check $f "dismissals are persisted ($id left)" test "${id:-x}" = 0
    go_home
}

flow_quicksettings() {
    local f=quicksettings
    ensure_session || { e2e_check quicksettings "shell starts" false; return; }
    go_home
    qs_pull
    e2e_shot qs
    e2e_check $f "pulling down from the top opens Quick Settings" e2e_showing Brightness
    if ! e2e_showing Brightness; then
        e2e_shell Navigation Navigation1 ShowQuickSettings >/dev/null
        sleep 1
    fi
    e2e_mark
    e2e_tap_name Silent 0.8
    e2e_shot qs-silent
    e2e_check $f "Silent turns Do Not Disturb on" e2e_wait_since "DND enabled changed to true" 2
    sleep 0.3
    e2e_check $f "...and it stays on" not e2e_wait_since "DND enabled changed to false" 0
    e2e_tap_name Silent 0.8
    e2e_shell Navigation Navigation1 HideQuickSettings >/dev/null
    sleep 0.8
    e2e_shot qs-closed
    e2e_check $f "Quick Settings closes" not e2e_showing Brightness
}

flow_search() {
    local f=search
    ensure_session || { e2e_check search "shell starts" false; return; }
    go_home
    e2e_tap_name Search 1.2
    e2e_type wifi
    sleep 1
    e2e_shot search-wifi
    e2e_mark
    e2e_tap 195 150 0.3
    app_mapped settings 20
    sleep 2
    e2e_shot search-opened
    e2e_check $f "the Wi-Fi result launches Settings on the wifi route" e2e_wait_since "--route \"wifi\"" 2
    e2e_check $f "Settings shows the Wi-Fi page" wait_heading "Wi-Fi"
    go_home
    e2e_tap_name Search 1.2
    e2e_type bluetooth
    sleep 1
    e2e_tap 195 150 3
    e2e_shot search-warm
    e2e_check $f "a result for a running app routes it (Bluetooth)" wait_heading Bluetooth
    go_home
}

flow_appinfo() {
    local f=appinfo
    ensure_session || { e2e_check appinfo "shell starts" false; return; }
    go_home
    find_icon Messages
    e2e_longpress_name Messages 1.2
    e2e_shot appmenu
    e2e_check $f "long-press shows the app menu" e2e_showing "App info"
    e2e_mark
    e2e_tap_name "App info" 3
    e2e_shot appinfo
    e2e_check $f "App info opens Settings on the app" wait_heading Messages 6
    go_home
}

# OSK key centres at this canvas (letters row by row).
declare -A OSK=([q]="20 637" [w]="60 637" [e]="99 637" [r]="138 637" [t]="177 637"
    [y]="216 637" [u]="254 637" [i]="292 637" [o]="331 637" [p]="370 637" [a]="40 685"
    [s]="80 685" [d]="118 685" [f]="157 685" [g]="196 685" [h]="234 685" [j]="273 685"
    [k]="312 685" [l]="350 685" [z]="72 730" [x]="111 730" [c]="149 730" [v]="188 730"
    [b]="226 730" [n]="264 730" [m]="303 730" [' ']="175 777" [BS]="357 730")
osk_type() {
    local i
    # shellcheck disable=SC2086
    for ((i = 0; i < ${#1}; i++)); do e2e_tap ${OSK[${1:i:1}]} 0.15; done
}

flow_keyboard() {
    local f=keyboard
    ensure_session || { e2e_check keyboard "shell starts" false; return; }
    go_home
    e2e_mark
    e2e_shell Navigation Navigation1 LaunchApp settings >/dev/null
    app_mapped settings 20 || e2e_wait_since "Restoring running app: \"settings\"" 3
    sleep 2
    local back=0
    until heading Settings || [ $back -ge 4 ]; do pill_back; back=$((back + 1)); done
    e2e_wait_showing "Search settings" marathon-app-runner 10
    e2e_shot osk-before
    local before=$E2E_LAST_SHOT
    e2e_tap_name "Search settings" marathon-app-runner 1.5
    e2e_shot osk
    e2e_check $f "focusing a field raises the keyboard" test "$(region_diff "$before" "$E2E_LAST_SHOT" 0 620 390 170)" -gt 20
    osk_type cafe
    _xdo mousemove 99 637 mousedown 1
    sleep 0.9
    e2e_shot osk-accents
    _xdo mousemove 120 600
    _xdo mousemove 139 590
    sleep 0.2
    _xdo mouseup 1
    sleep 0.5
    osk_type " bar"
    sleep 0.6
    e2e_shot osk-typed
    e2e_check $f "typed text with an accent reaches the app" app_text "[Cc]afeé [Bb]ar"
    _xdo mousemove 357 730 mousedown 1
    sleep 1.8
    _xdo mouseup 1
    sleep 0.6
    e2e_shot osk-held-backspace
    e2e_check $f "holding backspace deletes what was typed" not app_text "[Cc]af"
    pill_back
    go_home
}

SETTINGS_PAGES="Wi-Fi Bluetooth Display Sounds Notifications Battery About_device"

flow_settings() {
    local f=settings p
    ensure_session || { e2e_check settings "shell starts" false; return; }
    go_home
    e2e_mark
    e2e_shell Navigation Navigation1 LaunchApp settings >/dev/null
    app_mapped settings 20 || e2e_wait_since "Restoring running app" 5
    sleep 2
    local back=0
    until heading Settings || [ $back -ge 4 ]; do pill_back; back=$((back + 1)); done
    e2e_shot settings-root
    for p in $SETTINGS_PAGES; do
        p=${p//_/ }
        local tries=0
        until e2e_showing "$p" marathon-app-runner || [ $tries -ge 10 ]; do
            e2e_swipe 195 650 195 350 500 300
            tries=$((tries + 1))
        done
        if e2e_tap_name "$p" marathon-app-runner 2; then
            e2e_shot "settings-${p// /-}"
            e2e_check $f "$p page opens" wait_heading "$p" 3
        else
            e2e_check $f "$p entry found on the root page" false
        fi
        pill_back
        sleep 0.8
    done
    go_home
}

flow_alarm() {
    local f=alarm at
    ensure_session || { e2e_check alarm "shell starts" false; return; }
    go_home
    at=$(($(date +%s%3N) + 6000))
    e2e_mark
    e2e_shell Alarm Alarm1 CreateAlarm "" "Tea" "@ai []" "{'oneShot': <true>, 'at': <int64 $at>}" >/dev/null
    e2e_wait_since "TRIGGERING ALARM: \"Tea\"" 12
    e2e_check $f "one-shot alarm fires on time" e2e_wait_since "TRIGGERING ALARM" 1
    sleep 1
    e2e_shot alarm-ringing
    e2e_check $f "alarm overlay shows Dismiss" e2e_showing Dismiss
    e2e_tap_name Dismiss 0.8
    e2e_check $f "a tap on Dismiss does not stop it" not e2e_wait_since "Dismissed alarm" 0
    e2e_longpress_name Dismiss 2.0
    e2e_shot alarm-dismissed
    e2e_check $f "holding Dismiss stops it" e2e_wait_since "Dismissed alarm" 2
}

flow_screenshot() {
    local f=screenshot before after
    ensure_session || { e2e_check screenshot "shell starts" false; return; }
    go_home
    before=$(ls "$E2E_HOME/Pictures/Screenshots" 2>/dev/null | wc -l)
    e2e_shell Navigation Navigation1 ShowQuickSettings >/dev/null
    sleep 1
    e2e_mark
    e2e_tap_name Screenshot 0.3
    sleep 1
    e2e_shot screenshot-preview
    after=$(ls "$E2E_HOME/Pictures/Screenshots" 2>/dev/null | wc -l)
    e2e_check $f "Screenshot saves a file" test "$after" -gt "$before"
    e2e_check $f "a capture notification is posted" e2e_wait_since "Screenshot captured" 2
    e2e_mark
    e2e_tap 330 720 0.3
    app_mapped gallery 15 || e2e_wait_since "Restoring running app: \"gallery\"" 3
    local opened=$?
    sleep 1.5
    e2e_shot screenshot-opened
    e2e_check $f "tapping the preview opens Gallery" test $opened -eq 0
    go_home
}

# QML errors attributed to an app's runner since the last mark.
e2e_since_errors() {
    e2e_since | grep -- "--app-id $1" | grep -E "qrc:.*(Error|TypeError|ReferenceError|is not a type|not installed)" | head -5 >&2
    e2e_since | grep -- "--app-id $1" | grep -qE "qrc:.*(TypeError|ReferenceError|is not a type|not installed)"
}

ALL="firstrun pin6 pin4 paging apps switcher notifications quicksettings search appinfo keyboard settings alarm screenshot"
trap 'e2e_stop; [ -n "$E2E_RT" ] && rm -rf "$E2E_RT"' EXIT
[ $# -gt 0 ] || set -- $ALL
for flow in "$@"; do
    e2e_log "=== $flow"
    "flow_$flow"
done
e2e_report
