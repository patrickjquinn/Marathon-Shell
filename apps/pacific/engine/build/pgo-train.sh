#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# On the phone as root: drive the PGO-instrumented engine through a browsing
# workload so its profile reflects real use. Profiles land in
# ~defaultuser/.cache/org.shipwright/pacific/pgo (writable inside Sailjail).
#   [PACIFIC_PGO_WRITE=0x...] pgo-train.sh [sites|speedometer|all]
#   PACIFIC_BOLT_DUMP=0x... pgo-train.sh [...]: a BOLT training run instead
#     (build.sh bolt-instrument prints the value; the instrumented library in
#     place of the release one, libpacific-boltwrite.so in /opt/pacific/lib).
#     The .fdata files land in the same directory.
# Another phone than the Jolla Phone: TOUCH_DEV and TOUCH_SCREEN for touch.py.
B="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket"
PGO=/home/defaultuser/.cache/org.shipwright/pacific/pgo
# The training opens its own tabs, and an engine that fails to load leaves
# Pacific saving an empty session: the person's tabs are kept aside for the
# run and put back after it (26 October 2026: 30 tabs lost to a BOLT run).
SESSION=/home/defaultuser/.local/share/org.shipwright/pacific/session.lz4
mode=${1:-all}
open() { su defaultuser -c "$B dbus-send --session --print-reply --dest=org.shipwright.pacific.ui /ui org.shipwright.pacific.ui.openUrl array:string:$1" >/dev/null 2>&1; }
fling() { python3 /tmp/touch.py swipe 516 1700 516 500 160; sleep 0.9; }
flingup() { python3 /tmp/touch.py swipe 516 600 516 1900 160; sleep 0.9; }
start() {
    mkdir -p $PGO; chown defaultuser:defaultuser $PGO
    [ -f $SESSION ] && cp -p $SESSION $SESSION.pgo-train
    # The helper processes are SIGKILLed, so pgo-write.c (libpacific-pgowrite.so
    # in /opt/pacific/lib) writes their profiles every 5 s. PACIFIC_PGO_WRITE:
    # __llvm_profile_write_file's value in this build's libWPEWebKit
    # (llvm-nm <lib> | grep __llvm_profile_write_file). Firejail drops
    # LD_PRELOAD, so for the run it takes the place of the launcher's
    # libsyncskip.so shim (inert at ATLANTIC_SKIP_SWAP_FENCE=0); stop() puts
    # the shim back.
    w=
    if [ -n "$PACIFIC_BOLT_DUMP" ]; then
        # bolt-write.c the same way: it writes each process's BOLT counts.
        cp -n /opt/pacific/lib/shims/libsyncskip.so /opt/pacific/lib/shims/libsyncskip.so.pgo-orig
        cp /opt/pacific/lib/libpacific-boltwrite.so /opt/pacific/lib/shims/libsyncskip.so
        w="PACIFIC_BOLT_DUMP=$PACIFIC_BOLT_DUMP PACIFIC_BOLT_DIR=$PGO"
    elif [ -n "$PACIFIC_PGO_WRITE" ]; then
        cp -n /opt/pacific/lib/shims/libsyncskip.so /opt/pacific/lib/shims/libsyncskip.so.pgo-orig
        cp /opt/pacific/lib/libpacific-pgowrite.so /opt/pacific/lib/shims/libsyncskip.so
        w="PACIFIC_PGO_WRITE=$PACIFIC_PGO_WRITE"
    fi
    # --systemd too: Pacific runs as its prestart user service, which takes
    # its environment from systemd, not from D-Bus activation. Set before
    # the restart, so the instance the service starts again has it.
    su defaultuser -c "$B dbus-update-activation-environment --systemd LLVM_PROFILE_FILE=$PGO/%m-%p.profraw $w"
    kill $(pgrep -f '^/usr/bin/[s]hipwright-pacific') 2>/dev/null; sleep 5
}
stop() {
    # The writer (pgo-write.c / bolt-write.c) has written every process's
    # counts within the last 5 s; the UI process goes and the helpers with
    # it. (A swipe down from the top edge, once Sailfish's close gesture,
    # opens the Top Menu on 5.x and left everything running.)
    sleep 6
    kill $(pgrep -f '^/usr/bin/[s]hipwright-pacific') 2>/dev/null
    for i in $(seq 1 20); do pgrep -f '^/usr/bin/[s]hipwright-pacific|WPE(Web|Network)Process' >/dev/null || break; sleep 1; done
    pgrep -af '^/usr/bin/[s]hipwright-pacific|WPE(Web|Network)Process' && echo "pgo-train: still running after close"
    su defaultuser -c "$B dbus-update-activation-environment --systemd LLVM_PROFILE_FILE= PACIFIC_PGO_WRITE= PACIFIC_BOLT_DUMP= PACIFIC_BOLT_DIR="
    # Set but empty is still set to systemd: unset them there too.
    su defaultuser -c "$B XDG_RUNTIME_DIR=/run/user/100000 systemctl --user unset-environment LLVM_PROFILE_FILE PACIFIC_PGO_WRITE PACIFIC_BOLT_DUMP PACIFIC_BOLT_DIR"
    # The prestart service would start Pacific again on the training's tabs
    # and save them over the person's: stopped while they go back.
    if [ -f $SESSION.pgo-train ]; then
        su defaultuser -c "$B XDG_RUNTIME_DIR=/run/user/100000 systemctl --user stop shipwright-pacific-prestart.service"
        kill $(pgrep -f '^/usr/bin/[s]hipwright-pacific') 2>/dev/null; sleep 3
        mv $SESSION.pgo-train $SESSION && cp -p $SESSION ${SESSION%.lz4}.bak.lz4
        su defaultuser -c "$B XDG_RUNTIME_DIR=/run/user/100000 systemctl --user start shipwright-pacific-prestart.service"
    fi
    [ -f /opt/pacific/lib/shims/libsyncskip.so.pgo-orig ] &&
        mv /opt/pacific/lib/shims/libsyncskip.so.pgo-orig /opt/pacific/lib/shims/libsyncskip.so
}
start
if [ "$mode" != speedometer ]; then
    for u in https://en.wikipedia.org/wiki/Finland https://www.bbc.com/news https://www.theguardian.com/international \
             https://forum.sailfishos.org/latest https://github.com/sailfishos https://news.ycombinator.com \
             https://www.reddit.com/r/sailfishos/ https://duckduckgo.com/?q=jolla+phone https://www.yle.fi/ \
             https://developer.mozilla.org/en-US/docs/Web/CSS/grid https://en.wikipedia.org/wiki/Tampere \
             https://www.youtube.com/ https://www.nytimes.com/ https://stackoverflow.com/questions; do
        open "$u"; sleep 14
        for i in 1 2 3 4 5 6; do fling; done
        sleep 2; flingup; flingup; sleep 2
    done
fi
if [ "$mode" != sites ]; then
    open "https://browserbench.org/Speedometer3.1/?iterationCount=1&startAutomatically"
    sleep ${SPEEDOMETER_SECS:-900}
fi
stop
ls -la $PGO | tail -8
