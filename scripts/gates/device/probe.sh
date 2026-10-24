# Read-only facts behind every gate. Writes nothing on the phone outside the
# run's own temporary directory.

kv() {
    printf '%s=%s\n' "$1" "$2" >> "$G_TMP/probe.txt"
}

threads_of() {
    pid=$(pidof "$1" | awk '{print $1}')
    [ -n "$pid" ] || { step "threads-$1" skip "not running"; return; }
    kv "$1.pid" "$pid"
    kv "$1.threads" "$(ls /proc/"$pid"/task | wc -l)"
    kv "$1.thread_names" "$(cat /proc/"$pid"/task/*/comm | sort | uniq -c | awk '{printf "%s%s:%s", sep, $2, $1; sep=","}')"
    kv "$1.pss_kb" "$(awk '/^Pss:/ {print $2}' /proc/"$pid"/smaps_rollup)"
    kv "$1.private_dirty_kb" "$(awk '/^Private_Dirty:/ {print $2}' /proc/"$pid"/smaps_rollup)"
    kv "$1.bus_names" "$(as_user 'busctl --user list --no-legend' | awk -v p="$pid" '$1 ~ /^:/ && $2 == p' | wc -l)"
    step "threads-$1" ok
}

: > "$G_TMP/probe.txt"
kv kernel "$(uname -r)"
kv uclamp "$([ -e /sys/fs/cgroup/user.slice/cpu.uclamp.min ] && echo yes || echo no)"
threads_of marathon-shell-bin
threads_of deckard-bridge
threads_of deckard-containerd
if [ -n "$G_SHELL_PID" ]; then
    kv shell.render_loop_env "$(tr '\0' '\n' < /proc/"$G_SHELL_PID"/environ | sed -n 's/^QSG_RENDER_LOOP=//p')"
    kv shell.render_thread "${G_RENDER_TID:-none}"
fi

C=$(ls -d /sys/fs/cgroup/lxc.payload.* 2>/dev/null | head -n 1)
if [ -n "$C" ]; then
    kv container.cgroup "$C"
    kv container.freeze "$(cat "$C"/cgroup.freeze)"
    kv container.subtree_control "$(cat "$C"/cgroup.subtree_control)"
    kv container.frozen_children "$(cat "$C"/*/*/cgroup.freeze 2>/dev/null | grep -c 1)"
    kv container.children "$(ls -d "$C"/*/pid_* 2>/dev/null | wc -l)"
    kv container.oom_kill "$(awk '$1 == "oom_kill" {print $2}' "$C"/memory.events)"
    kv container.memory_high "$(cat "$C"/memory.high)"
    kv container.memory_max "$(cat "$C"/memory.max)"
    kv container.uclamp_min "$(cat "$C"/cpu.uclamp.min 2>/dev/null || echo absent)"
fi
kv binder.freeze_notification "$(cat /dev/binderfs/features/freeze_notification 2>/dev/null || echo absent)"
kv android.suspend_prop "$(sed -n 's/^persist.waydroid.suspend *= *//p' /var/lib/waydroid/waydroid.cfg)"
kv android.suspend_action "$(sed -n 's/^suspend_action *= *//p' /var/lib/waydroid/waydroid.cfg)"
if [ -n "$C" ]; then
    init=$(cat "$C"/cgroup.procs "$C"/*/cgroup.procs 2>/dev/null | head -n 1)
    [ -n "$init" ] && kv android.own_pid_namespace \
        "$([ "$(readlink /proc/"$init"/ns/pid)" != "$(readlink /proc/1/ns/pid)" ] && echo yes || echo no)"
fi
A=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/marathon.slice/marathon-apps
kv shell.android_app_cgroups "$(ls -d "$A"/marathon-app-waydroid.* "$A"/marathon-app-deckard.* 2>/dev/null | wc -l)"
kv shell.frozen_apps "$(cat "$A"/marathon-app-*/cgroup.freeze 2>/dev/null | grep -c 1)"

if android_up; then
    android 'dumpsys activity settings' > "$G_TMP/am-settings.txt" 2>&1
    kv android.use_freezer "$(sed -n 's/^ *use_freezer=//p' "$G_TMP/am-settings.txt")"
    kv android.freeze_debounce_ms "$(sed -n 's/^ *freeze_debounce_timeout=//p' "$G_TMP/am-settings.txt")"
    kv android.cached_apps_freezer "$(android 'settings get global cached_apps_freezer')"
    android 'logcat -d -b main -b system' 2>/dev/null | grep -E 'ActivityManager.*([Ff]reez)' > "$G_TMP/freezer-log.txt"
    kv android.freezer_log "$(head -n 3 "$G_TMP/freezer-log.txt" | sed 's/^.*ActivityManager: //' | tr '\n' '|')"
    android 'dumpsys activity lru' > "$G_TMP/am-lru.txt" 2>&1
    kv android.cached_procs "$(grep -c ' cch' "$G_TMP/am-lru.txt")"
    android 'getprop' | grep -E 'lmk|freez' > "$G_TMP/android-props.txt"
    step android-probe ok
else
    step android-probe skip "container not running"
fi

# Gate 7: what the phone runs against what was packaged.
kv apk_db.deckard "$(awk '/^P:deckard$/ {getline; print substr($0, 3); exit}' /lib/apk/db/installed)"
kv apk_db.marathon_shell "$(awk '/^P:marathon-shell$/ {getline; print substr($0, 3); exit}' /lib/apk/db/installed)"
S=/usr/share/deckard/overlay
L=/var/lib/waydroid/overlay
if [ -d "$S" ] && [ -d "$L" ]; then
    (cd "$S" && find . -type f -exec sha256sum {} +) | sort -k2 > "$G_TMP/overlay-share.sha"
    (cd "$L" && find . -type f -exec sha256sum {} +) | sort -k2 > "$G_TMP/overlay-live.sha"
    kv overlay.share_files "$(wc -l < "$G_TMP/overlay-share.sha")"
    kv overlay.live_files "$(wc -l < "$G_TMP/overlay-live.sha")"
    kv overlay.differing "$(join -1 2 -2 2 "$G_TMP/overlay-share.sha" "$G_TMP/overlay-live.sha" | awk '$2 != $3' | wc -l)"
    kv overlay.live_only "$(join -v 2 -1 2 -2 2 "$G_TMP/overlay-share.sha" "$G_TMP/overlay-live.sha" | wc -l)"
    step overlay-drift ok
else
    step overlay-drift skip "no overlay dirs"
fi
M=/usr/share/deckard/build-manifest
if [ -f "$M" ]; then
    kv manifest.commit "$(sed -n 's/^commit //p' "$M")"
    kv manifest.mismatch "$(grep -E '^[0-9a-f]{64}  ' "$M" | (cd / && sha256sum -c - 2>/dev/null) | grep -vc ': OK$')"
    step manifest ok
else
    kv manifest.commit none
    step manifest fail "no $M: the installed Deckard files cannot be traced to a commit"
fi
for f in /usr/libexec/deckard-bridge /usr/libexec/deckard-containerd /usr/bin/marathon-shell-bin; do
    kv "mtime.$(basename "$f")" "$(stat -c %Y "$f" 2>/dev/null)"
done
kv apk_db.mtime "$(stat -c %Y /lib/apk/db/installed)"
kv python3 "$(command -v python3 || echo absent)"
kv waydroid_cli "$(command -v waydroid || echo absent)"
