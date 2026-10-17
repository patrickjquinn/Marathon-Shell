#!/bin/sh
# Runs a test against a private PipeWire and WirePlumber with Marathon's
# media roles (null sinks, no hardware, no system bus); the user's own audio
# session is never touched. Without PipeWire installed the test runs alone.
set -eu
src=$(cd "$(dirname "$0")/../.." && pwd)
audiod="$src/crates/marathon-audiod"
for p in pipewire wireplumber dbus-daemon; do
	command -v "$p" >/dev/null || exec "$@"
done

# Short: the PipeWire socket path must fit in sun_path.
dir=$(mktemp -d /tmp/roles.XXXXXX)
pids=""
cleanup() {
	for pid in $pids; do kill "$pid" 2>/dev/null || true; done
	rm -rf "$dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$dir/run" "$dir/config/wireplumber/wireplumber.conf.d" "$dir/state" \
	"$dir/data/wireplumber/scripts/marathon"
chmod 700 "$dir/run"
cp "$audiod/tests/session/wireplumber.conf.d/90-marathon-test.conf" \
	"$audiod/data/wireplumber/wireplumber.conf.d/61-marathon-media-roles.conf" \
	"$dir/config/wireplumber/wireplumber.conf.d/"
cp "$audiod/data/wireplumber/scripts/marathon/role-default-target.lua" \
	"$dir/data/wireplumber/scripts/marathon/"

export XDG_RUNTIME_DIR="$dir/run" PIPEWIRE_RUNTIME_DIR="$dir/run"
export XDG_CONFIG_HOME="$dir/config" XDG_STATE_HOME="$dir/state" XDG_DATA_HOME="$dir/data"
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --config-file="$audiod/tests/session/bus.conf" \
	--fork --print-address=1 --print-pid=3 3>"$dir/bus.pid")
export DBUS_SESSION_BUS_ADDRESS DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
pids="$(cat "$dir/bus.pid")"

pipewire -c "$audiod/tests/session/pipewire.conf" 2>"$dir/pipewire.log" &
pids="$pids $!"
wireplumber -p marathon-test 2>"$dir/wireplumber.log" &
pids="$pids $!"

export MARATHON_MEDIA_ROLES=1
"$@"
