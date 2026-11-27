#!/bin/sh
# marathon-fingerprint against fake fprintd-enroll and fprintd-delete that
# log their arguments.
# Usage: test-fingerprint.sh <path to marathon-fingerprint>
set -eu

helper=$1
PKEXEC_UID=$(id -u)
[ "$PKEXEC_UID" -ge 1000 ] || { echo "SKIP: needs a uid of 1000 or more"; exit 0; }
user=$(id -un)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/fprintd-enroll" <<EOF2
#!/bin/sh
echo "\$*" > "$W/enroll-args"
trap 'echo stopped > "$W/enroll-stopped"; exit 1' TERM
echo "Using device /net/reactivated/Fprint/Device/0"
echo "Enrolling \$2 finger."
echo "Enroll result: enroll-stage-passed"
[ -z "\${HANG:-}" ] || { sleep 30 & wait; }
echo "Enroll result: enroll-retry-scan"
echo "Enroll result: enroll-stage-passed"
echo "Enroll result: \${LAST:-enroll-completed}"
[ "\${LAST:-enroll-completed}" = enroll-completed ]
EOF2
cat > "$W/bin/fprintd-delete" <<EOF2
#!/bin/sh
echo "\$*" > "$W/delete-args"
EOF2
chmod +x "$W/bin/fprintd-enroll" "$W/bin/fprintd-delete"
PATH="$W/bin:$PATH"
export PATH PKEXEC_UID

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# Like the shell's pkexec pipe, stdin stays open: at end of input the
# helper stops the enrolment.
mkfifo "$W/stdin"
exec 5<> "$W/stdin"

run() {
	rc=0
	sh "$helper" "$@" < "$W/stdin" > "$W/out" 2> "$W/err" || rc=$?
}

run enroll right-index-finger
[ "$rc" = 0 ] || fail "enroll exited $rc: $(cat "$W/err")"
[ "$(cat "$W/enroll-args")" = "-f right-index-finger $user" ] || fail "enroll ran with $(cat "$W/enroll-args")"
printf 'enroll-stage-passed\nenroll-retry-scan\nenroll-stage-passed\nenroll-completed\n' | cmp -s - "$W/out" ||
	fail "enroll printed $(cat "$W/out")"

LAST=enroll-failed run enroll left-thumb
[ "$rc" = 1 ] || fail "a failed enrolment exited $rc"
[ "$(tail -n 1 "$W/out")" = enroll-failed ] || fail "a failed enrolment printed $(cat "$W/out")"

# Closing stdin stops the enrolment.
mkfifo "$W/in"
rc=0
HANG=1 sh "$helper" enroll right-thumb < "$W/in" > "$W/out" 2> "$W/err" &
pid=$!
exec 4> "$W/in"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -s "$W/out" ] && break
	sleep 0.2
done
[ "$(cat "$W/out")" = enroll-stage-passed ] || fail "before the stop it printed $(cat "$W/out")"
exec 4>&-
wait "$pid" || rc=$?
[ "$rc" = 1 ] || fail "a stopped enrolment exited $rc"
[ -e "$W/enroll-stopped" ] || fail "fprintd-enroll was not interrupted"

run delete right-thumb
[ "$rc" = 0 ] || fail "delete exited $rc"
[ "$(cat "$W/delete-args")" = "$user -f right-thumb" ] || fail "delete ran with $(cat "$W/delete-args")"
run delete
[ "$(cat "$W/delete-args")" = "$user" ] || fail "delete all ran with $(cat "$W/delete-args")"

run enroll ring-finger
[ "$rc" = 2 ] || fail "an unknown finger exited $rc"
run delete right-thumb left-thumb
[ "$rc" = 2 ] || fail "two fingers exited $rc"
PKEXEC_UID=0 run delete
[ "$rc" = 2 ] || fail "root's own prints exited $rc"
echo PASS
