#!/usr/bin/env bash
# Marathon Mail verification harness — runs inside the QEMU guest as root
# (boot-and-verify-mail.sh). The user manager is reached with
# --machine=user@.host.
#
# Exit codes:
#   1  marathon-maild missing or does not load
#   2  marathon-maild.service not registered with the user manager
#   3  org.marathonos.Mail does not answer on the session bus
#   5  user@1000.service is not active
set -u
RC=0
say()  { printf '  %s\n' "$1"; }
fail() { echo "FAIL: $1" >&2; RC=$2; }
USER_BUS='systemctl --machine=user@.host --user'

echo "==> 1. marathon-maild on disk, its libraries resolved"
if [ -x /usr/bin/marathon-maild ]; then
    say "/usr/bin/marathon-maild ✓"
    BAD="$(ldd /usr/bin/marathon-maild 2>&1 | grep -E 'not found' || true)"
    [ -z "$BAD" ] && say "ldd clean ✓" || fail "ldd: $BAD" 1
else
    fail "marathon-maild missing" 1
fi

echo "==> 2. user@1000.service is active"
systemctl is-active --quiet user@1000.service && say "user@1000.service active ✓" \
    || fail "user@1000.service not active" 5

echo "==> 3. marathon-maild.service registered"
$USER_BUS list-unit-files marathon-maild.service 2>/dev/null | grep -q marathon-maild.service \
    && say "marathon-maild.service registered ✓" || fail "marathon-maild.service not registered" 2

echo "==> 4. org.marathonos.Mail answers (bus activation)"
if busctl --machine=user@.host --user call org.marathonos.Mail /org/marathonos/Shell/Mail \
        org.marathonos.Shell.Mail1 OAuthProviders >/dev/null 2>&1; then
    say "Mail1.OAuthProviders answered ✓"
else
    fail "org.marathonos.Mail did not answer" 3
fi

[ "$RC" -eq 0 ] && echo "==> all mail checks pass" || echo "==> mail checks failed (rc=$RC)"
exit "$RC"
