#!/bin/sh
# marathon-modem-sleep against stub mmcli, systemctl and sleep.
# Usage: test-modem-sleep.sh <path to marathon-modem-sleep>
set -eu

script=$1
STUB=$(mktemp -d)
export STUB
trap 'rm -rf "$STUB"' EXIT
mkdir "$STUB/bin" "$STUB/run"

cat > "$STUB/bin/mmcli" <<'EOF'
#!/bin/sh
if [ -e "$STUB/present" ]; then
	echo "    /org/freedesktop/ModemManager1/Modem/0 [BroadMobi] BM818"
else
	echo "No modems were found"
fi
EOF
cat > "$STUB/bin/systemctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB/systemctl.log"
[ ! -e "$STUB/restart-brings-modem" ] || : > "$STUB/present"
EOF
cat > "$STUB/bin/sleep" <<'EOF'
#!/bin/sh
echo "$1" >> "$STUB/sleep.log"
EOF
chmod +x "$STUB/bin/"*

PATH="$STUB/bin:$PATH"
RUNTIME_DIRECTORY="$STUB/run"
export PATH RUNTIME_DIRECTORY

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

reset() {
	rm -f "$STUB/present" "$STUB/restart-brings-modem" "$STUB/systemctl.log" \
		"$STUB/sleep.log" "$STUB/run/present"
}

lines() {
	if [ -e "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}

# A modem that is back after resume is left alone.
reset
: > "$STUB/present"
sh "$script" pre
[ -e "$STUB/run/present" ] || fail "pre did not note the modem"
out=$(sh "$script" post) || fail "post failed for a healthy modem"
[ "$out" = "event=marathon_modem_sleep state=healthy" ] || fail "healthy: $out"
[ ! -e "$STUB/systemctl.log" ] || fail "restarted ModemManager for a healthy modem"

# No modem before sleep: nothing to recover.
reset
sh "$script" pre
[ ! -e "$STUB/run/present" ] || fail "pre noted a modem that is not there"
out=$(sh "$script" post) || fail "post failed without a modem"
[ "$out" = "event=marathon_modem_sleep state=absent-before-sleep" ] || fail "absent: $out"
[ ! -e "$STUB/systemctl.log" ] || fail "restarted ModemManager without a modem"

# A modem missing after resume: ModemManager is restarted, without
# blocking the resume transaction, after the settle time.
reset
: > "$STUB/present"
sh "$script" pre
rm "$STUB/present"
: > "$STUB/restart-brings-modem"
out=$(sh "$script" post) || fail "post failed although the restart brought the modem back"
[ "$out" = "event=marathon_modem_sleep state=restored" ] || fail "restored: $out"
[ "$(cat "$STUB/systemctl.log")" = "restart --no-block ModemManager.service" ] ||
	fail "systemctl: $(cat "$STUB/systemctl.log")"
[ "$(lines "$STUB/sleep.log")" = 10 ] || fail "settled $(lines "$STUB/sleep.log") s, not 10"

# Still missing after the restart: a bounded wait, then failure.
reset
: > "$STUB/present"
sh "$script" pre
rm "$STUB/present"
if out=$(sh "$script" post); then fail "post succeeded with no modem"; fi
[ "$out" = "event=marathon_modem_sleep state=failed reason=modem-not-enumerated" ] ||
	fail "failed: $out"
[ "$(lines "$STUB/sleep.log")" = 40 ] || fail "waited $(lines "$STUB/sleep.log") s, not 40"

# Anything else is a usage error.
if sh "$script" resume 2> /dev/null; then fail "accepted an unknown action"; fi

echo "PASS: marathon-modem-sleep"
