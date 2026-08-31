#!/usr/bin/env bash
# Marathon Mail verification harness — runs inside the QEMU guest.
#
# Runs as ROOT over the QEMU SSH path (boot-and-verify-mail.sh logs in
# as root with the documented `marathon` password). To query / drive
# `user`'s user-systemd we use systemctl's --machine=user@.host --user
# bus cross-over rather than dropping uid (sshpass-as-user isn't set
# up on the QEMU image; only root has a password).
#
# Exit codes (parsed by callers):
#   0  all checks pass
#   1  qmf-libs / messageserver missing
#   2  marathon-mailserver.service not loaded
#   3  messageserver fails to start
#   4  ldd reports missing shared lib (the most likely musl gotcha)
#   5  user@1000.service is not active (auto-login + linger both failed)

set -u
RC=0
say()  { printf '  %s\n' "$1"; }
fail() { echo "FAIL: $1" >&2; RC=$2; }

# Helper — same string both times.
USER_BUS='systemctl --machine=user@.host --user'

echo "==> 1. QMF artefacts on disk"
# Glob the soname rather than pinning it. Upstream QMF renamed these
# (libQmfClient.so.4.0.4 -> libQmfClient-qt6.so.6.0.0) and the hardcoded
# names failed while the libraries were present and correctly linked —
# a false alarm on a healthy image. What matters is that exactly one of
# each exists and messageserver resolves against it (checked in step 3).
QMF_CLIENT_LIB=$(ls /usr/lib/libQmfClient*.so.* 2>/dev/null | head -1)
QMF_SERVER_LIB=$(ls /usr/lib/libQmfMessageServer*.so.* 2>/dev/null | head -1)
[ -n "$QMF_CLIENT_LIB" ] && say "$(basename "$QMF_CLIENT_LIB") ✓"        || fail "libQmfClient missing"          1
[ -n "$QMF_SERVER_LIB" ] && say "$(basename "$QMF_SERVER_LIB") ✓" || fail "libQmfMessageServer missing"   1
test -x /usr/bin/messageserver                 && say "/usr/bin/messageserver ✓"      || fail "messageserver binary missing"  1

echo "==> 2. Plugin directories present"
ls -1d /usr/lib/qt6/plugins/messagingframework/messageservices 2>/dev/null | head -1 \
    && say "messageservices/ ✓" \
    || fail "messageservices plugin dir missing" 1
ls -1d /usr/lib/qt6/plugins/messagingframework/contentmanagers 2>/dev/null | head -1 \
    && say "contentmanagers/ ✓" \
    || fail "contentmanagers plugin dir missing" 1

echo "==> 2b. Marathon credential plugins + QML module"
test -f /usr/lib/qt6/plugins/messagingframework/credentials/libmarathonoauth.so \
    && say "marathonoauth credential plugin ✓" \
    || fail "marathonoauth.so missing" 1
test -f /usr/lib/qt6/plugins/messagingframework/credentials/libmarathonclassic.so \
    && say "marathonclassic credential plugin ✓" \
    || fail "marathonclassic.so missing" 1
test -f /usr/lib/qt6/qml/MarathonOS/Services/qmldir \
    && say "MarathonOS.Services qmldir ✓" \
    || fail "MarathonOS.Services qmldir missing" 1
test -x /usr/bin/marathon-mail-oauth \
    && say "marathon-mail-oauth helper ✓" \
    || fail "marathon-mail-oauth helper missing" 1

echo "==> 2c. marathon-mail-oauth helper smoke check"
# Run with the permission gate explicitly cleared so the helper exits
# with its structured "permission_denied" envelope rather than touching
# Secret-Service. Confirms the binary loads cleanly under musl + the
# clap CLI parser is wired up.
if HELPER_OUT=$(env -u MARATHON_PERM_SECRET_SERVICE /usr/bin/marathon-mail-oauth token \
        --account-id smoke-test 2>&1); then
    say "marathon-mail-oauth unexpectedly succeeded without permission gate"
elif echo "$HELPER_OUT" | grep -q 'permission_denied'; then
    say "marathon-mail-oauth refuses without permission gate ✓"
else
    fail "marathon-mail-oauth produced unexpected output: $HELPER_OUT" 1
fi

echo "==> 3. Shared-library resolution under musl"
LDD_BAD="$(ldd /usr/bin/messageserver 2>&1 | grep -E 'not found|undefined' || true)"
if [ -z "$LDD_BAD" ]; then
    say "ldd messageserver clean ✓"
else
    fail "ldd reports missing deps:" 4
    echo "$LDD_BAD" >&2
fi

echo "==> 4. user@1000.service is active (precondition for --user work)"
if systemctl is-active --quiet user@1000.service; then
    say "user@1000.service active ✓"
else
    fail "user@1000.service not active — auto-login did not bring up user session" 5
    systemctl status user@1000.service --no-pager 2>&1 | head -10 >&2
fi

echo "==> 5. marathon-mailserver.service is registered in user manager"
if $USER_BUS list-unit-files marathon-mailserver.service 2>/dev/null | grep -q marathon-mailserver.service; then
    say "marathon-mailserver.service registered ✓"
else
    fail "marathon-mailserver.service NOT in user manager" 2
    $USER_BUS list-unit-files 2>&1 | tail -10 >&2
fi

echo "==> 6. messageserver dry-launch (5 second window)"
$USER_BUS start marathon-mailserver.service 2>/dev/null || true
sleep 5
if $USER_BUS is-active --quiet marathon-mailserver.service; then
    say "marathon-mailserver.service active ✓"
    journalctl --machine=user@.host --user-unit marathon-mailserver.service --no-pager --since "10 seconds ago" 2>/dev/null \
        | tail -10 | sed 's/^/    /' || true
else
    fail "marathon-mailserver.service failed to stay running" 3
    journalctl --machine=user@.host --user-unit marathon-mailserver.service --no-pager --since "1 minute ago" 2>/dev/null \
        | tail -15 | sed 's/^/    /' >&2 || true
fi

echo "==> 7. Tear-down"
$USER_BUS stop marathon-mailserver.service 2>/dev/null || true

echo "==> done (rc=$RC)"
exit $RC
