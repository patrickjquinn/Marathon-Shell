#!/bin/sh
# marathon-update-splash against a stub plymouth.
# Usage: test-update-splash.sh <path to marathon-update-splash>
set -eu

script=$1
STUB=$(mktemp -d)
export STUB
trap 'rm -rf "$STUB"' EXIT
mkdir "$STUB/bin" "$STUB/state"

cat > "$STUB/bin/plymouth" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB/plymouth.log"
[ ! -e "$STUB/no-daemon" ] || exit 1
EOF
chmod +x "$STUB/bin/plymouth"

PATH="$STUB/bin:$PATH"
STATE_DIRECTORY="$STUB/state"
MARATHON_OS_RELEASE="$STUB/os-release"
export PATH STATE_DIRECTORY MARATHON_OS_RELEASE

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

booted() {
	rm -f "$STUB/plymouth.log"
	printf 'ID=postmarketos\nIMAGE_VERSION=%s\n' "$1" > "$MARATHON_OS_RELEASE"
	sh "$script" boot || fail "boot of $1 failed"
}

said() {
	[ "$(cat "$STUB/plymouth.log" 2>/dev/null)" = 'display-message --text=Finishing update…' ]
}

quiet() {
	[ ! -e "$STUB/plymouth.log" ] || fail "$1: $(cat "$STUB/plymouth.log")"
}

# The very first boot is no update.
booted 26101701
quiet "first boot"
sh "$script" started
[ "$(cat "$STUB/state/started-version")" = 26101701 ] || fail "started did not note 26101701"

# The same version again: the usual splash.
booted 26101701
quiet "same version"

# A new version, until its shell has come up: every try says so.
booted 26101801
said || fail "first boot of 26101801"
booted 26101801
said || fail "retry of 26101801"

# Back on the version that last came up: nothing to finish.
booted 26101701
quiet "rollback"

# Up on the new version: later boots are plain.
booted 26101801
sh "$script" started
booted 26101801
quiet "after the shell started"

# A quoted value is read too.
printf 'IMAGE_VERSION="26101901"\n' > "$MARATHON_OS_RELEASE"
rm -f "$STUB/plymouth.log"
sh "$script" boot
said || fail "quoted IMAGE_VERSION"

# No plymouth daemon, no IMAGE_VERSION, no state directory: never a failure.
: > "$STUB/no-daemon"
booted 26102001
rm "$STUB/no-daemon"
printf 'ID=postmarketos\n' > "$MARATHON_OS_RELEASE"
rm -f "$STUB/plymouth.log"
sh "$script" boot || fail "boot without IMAGE_VERSION"
quiet "no IMAGE_VERSION"
sh "$script" started || fail "started without IMAGE_VERSION"
[ "$(cat "$STUB/state/started-version")" = 26101801 ] || fail "started noted an empty version"
STATE_DIRECTORY="$STUB/missing" sh "$script" started 2> /dev/null || fail "missing state directory"

echo "PASS: marathon-update-splash"
