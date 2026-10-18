#!/bin/sh
# marathon-data-key against a LUKS2 image file, with the real cryptsetup
# behind a wrapper that fails the calls matching the glob $FAIL_ON.
# Usage: test-data-key.sh <path to marathon-data-key>
set -eu

helper=$1
real=$(command -v cryptsetup) || { echo "SKIP: no cryptsetup"; exit 0; }
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/bin"
cat > "$W/bin/cryptsetup" <<EOF
#!/bin/sh
case " \$* " in \${FAIL_ON:-@@}) exit 1 ;; esac
exec "$real" "\$@"
EOF
chmod +x "$W/bin/cryptsetup"
PATH="$W/bin:$PATH"
MARATHON_DATA_KEY_DEV=$W/data.img
MARATHON_DATA_KEY_DIR=$W/var/lib/marathon-data-key
MARATHON_DATA_KEY_LOCK=$W/lock
export PATH MARATHON_DATA_KEY_DEV MARATHON_DATA_KEY_DIR MARATHON_DATA_KEY_LOCK

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

opens() {
	printf '%s\n' "$1" | cryptsetup open --test-passphrase "$MARATHON_DATA_KEY_DEV" 2> /dev/null
}

slot_count() {
	cryptsetup luksDump "$MARATHON_DATA_KEY_DEV" | grep -c '^  [0-9]*: luks2$'
}

run() {
	rc=0
	printf '%s' "${2:-}" | sh "$helper" "$1" > "$W/out" 2> "$W/err" || rc=$?
}

# Not encrypted.
truncate -s 32M "$MARATHON_DATA_KEY_DEV"
run status
[ "$rc" = 0 ] && [ "$(cat "$W/out")" = plain ] || fail "status of a plain partition: $rc $(cat "$W/out")"
run set 123456
[ "$rc" = 3 ] || fail "set on a plain partition exited $rc"

# A new install: LUKS2 with the empty passphrase only.
echo | cryptsetup -q --force-password luksFormat --type luks2 --pbkdf pbkdf2 \
	--pbkdf-force-iterations 1000 "$MARATHON_DATA_KEY_DEV"
run status
[ "$(cat "$W/out")" = open ] || fail "status of a new install: $(cat "$W/out")"

# The first PIN.
run set 123456
[ "$rc" = 0 ] || fail "set exited $rc: $(cat "$W/err")"
opens 123456 || fail "the PIN does not open it"
opens "" && fail "the empty passphrase still opens it"
[ "$(slot_count)" = 2 ] || fail "$(slot_count) keyslots after set, not the PIN and the device key"
cryptsetup open --test-passphrase --key-file "$MARATHON_DATA_KEY_DIR/device.key" "$MARATHON_DATA_KEY_DEV" ||
	fail "the device key does not open it"
[ "$(stat -c %a "$MARATHON_DATA_KEY_DIR/device.key")" = 600 ] || fail "device key mode"
[ "$(cat "$MARATHON_DATA_KEY_DIR/state")" = pin ] || fail "state after set"
cryptsetup luksDump "$MARATHON_DATA_KEY_DEV" | grep -q 'PBKDF:      argon2id' || fail "the PIN slot is not argon2id"
run status
[ "$(cat "$W/out")" = pin ] || fail "status with a PIN: $(cat "$W/out")"

# A changed PIN replaces the old one.
run set 654321
[ "$rc" = 0 ] || fail "rekey exited $rc: $(cat "$W/err")"
opens 654321 || fail "the new PIN does not open it"
opens 123456 && fail "the old PIN still opens it"
[ "$(slot_count)" = 2 ] || fail "$(slot_count) keyslots after the rekey"

# Failures part way leave a PIN that opens it.
FAIL_ON='*argon2id*' run set 111111
[ "$rc" = 1 ] || fail "a failed add exited $rc"
opens 654321 || fail "a failed add lost the PIN"
[ "$(slot_count)" = 2 ] || fail "a failed add left $(slot_count) keyslots"

FAIL_ON='*luksKillSlot*' run set 222222
[ "$rc" = 1 ] || fail "a failed removal exited $rc"
opens 222222 || fail "a failed removal lost the new PIN"
opens 654321 || fail "a failed removal lost the old PIN"
[ "$(cat "$MARATHON_DATA_KEY_DIR/state")" = pin ] || fail "state after a failed removal"
run set 222222
[ "$rc" = 0 ] && [ "$(slot_count)" = 2 ] || fail "set after a failed removal: $rc, $(slot_count) keyslots"

FAIL_ON="* --test-passphrase --key-slot [0-9] $MARATHON_DATA_KEY_DEV *" run set 333333
[ "$rc" = 1 ] || fail "an unchecked slot exited $rc"
opens 222222 || fail "an unchecked slot lost the PIN"

run set ""
[ "$rc" = 2 ] || fail "an empty PIN exited $rc"
opens 222222 || fail "an empty PIN lost the PIN"

# Removing the PIN: it opens by itself again.
run clear
[ "$rc" = 0 ] || fail "clear exited $rc: $(cat "$W/err")"
opens "" || fail "the empty passphrase does not open it after clear"
opens 222222 && fail "the PIN still opens it after clear"
[ "$(slot_count)" = 2 ] || fail "$(slot_count) keyslots after clear"
[ "$(cat "$MARATHON_DATA_KEY_DIR/state")" = open ] || fail "state after clear"

# Without the device key a PIN can't be changed, and stays.
run set 444444
rm "$MARATHON_DATA_KEY_DIR/device.key"
run set 555555
[ "$rc" = 4 ] || fail "set without the device key exited $rc"
opens 444444 || fail "set without the device key lost the PIN"

# consume-boot-unlock: once, and only for the boot that wrote it.
MARATHON_BOOT_ID_FILE=$W/boot_id
export MARATHON_BOOT_ID_FILE
echo boot-a > "$W/boot_id"
note=$MARATHON_DATA_KEY_DIR/boot-unlocked
run consume-boot-unlock
[ "$rc" = 5 ] || fail "consume without a note exited $rc"
echo boot-a > "$note"
run consume-boot-unlock
[ "$rc" = 0 ] || fail "consume of this boot's note exited $rc"
run consume-boot-unlock
[ "$rc" = 5 ] || fail "a second consume exited $rc"
echo boot-z > "$note"
run consume-boot-unlock
[ "$rc" = 5 ] || fail "consume of another boot's note exited $rc"
[ ! -e "$note" ] || fail "another boot's note was left behind"

echo "PASS: marathon-data-key"
