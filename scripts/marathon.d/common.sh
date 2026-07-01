#!/usr/bin/env bash
# marathon.d/common.sh — shared helpers for the marathon CLI.
#
# All phase modules source this. It provides:
#   marathon::{info,success,warn,error,step,debug}   — colored stderr
#   marathon::config::load                           — config + devices
#   marathon::ssh / marathon::scp                    — device SSH wrappers
#   marathon::device::pick / current / list          — multi-device
#   marathon::wait_reachable                         — post-suspend etc.
#   marathon::askpass::ensure                        — restore /tmp/askpass
#   marathon::usage                                  — help text

# ── Colored output ───────────────────────────────────────────────────
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    _c_reset=$'\e[0m'
    _c_bold=$'\e[1m'
    _c_dim=$'\e[2m'
    _c_red=$'\e[31m'
    _c_green=$'\e[32m'
    _c_yellow=$'\e[33m'
    _c_blue=$'\e[34m'
    _c_cyan=$'\e[36m'
else
    _c_reset=""; _c_bold=""; _c_dim=""; _c_red=""; _c_green=""; _c_yellow=""; _c_blue=""; _c_cyan=""
fi

marathon::info()    { [ "${MARATHON_QUIET:-0}" = "1" ] && return; echo "${_c_blue}▸${_c_reset} $*" >&2; }
marathon::step()    { [ "${MARATHON_QUIET:-0}" = "1" ] && return; echo "${_c_cyan}→${_c_reset} $*" >&2; }
marathon::success() { echo "${_c_green}✓${_c_reset} $*" >&2; }
marathon::warn()    { echo "${_c_yellow}⚠${_c_reset} $*" >&2; }
marathon::error()   { echo "${_c_red}✗${_c_reset} $*" >&2; }
marathon::debug()   { [ "${MARATHON_VERBOSE:-0}" = "1" ] && echo "${_c_dim}·${_c_reset} $*" >&2; return 0; }

# ── Config ───────────────────────────────────────────────────────────
MARATHON_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/marathon-dev"
MARATHON_CONFIG_FILE="$MARATHON_CONFIG_DIR/config"
MARATHON_DEVICES_FILE="$MARATHON_CONFIG_DIR/devices.conf"

marathon::config::load() {
    # Repo roots — assume the CLI lives at <shell>/scripts/marathon.
    export MARATHON_SRC="${MARATHON_SRC:-$(cd "$MARATHON_CLI_DIR/.." && pwd)}"

    # Load config file (env var overrides win).
    if [ -f "$MARATHON_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        . "$MARATHON_CONFIG_FILE"
    fi

    # Defaults.
    export MARATHON_PASSWORD="${MARATHON_PASSWORD:-marathon}"
    export MARATHON_PIN="${MARATHON_PIN:-027602}"
    export MARATHON_IMAGE="${MARATHON_IMAGE:-$HOME/Developer/Marathon-Image}"
    export MARATHON_SCRATCH="${MARATHON_SCRATCH:-/tmp/claude-1000/-home-patrickquinn-Developer-Marathon-Shell/9bbcb305-4fd3-4232-a2b7-9c9eafebbcf4/scratchpad}"

    marathon::device::resolve
}

# ── Multi-device support ─────────────────────────────────────────────
#
# Devices are declared in ~/.config/marathon-dev/devices.conf, one per
# line: `name kind host [notes]`. Example:
#   l5     librem5    root@marathon.local   USB-net 172.16.42.1 fallback
#   cm5    hackberry  root@marathon.local   HackberryPi CM5
#   qemu   qemu       root@localhost:2222   pmOS QEMU sim
#
# --device NAME picks one; env MARATHON_DEVICE also works.
# MARATHON_HOST overrides host directly.
# If neither is set, first entry in devices.conf is used, else marathon.local.

marathon::device::resolve() {
    if [ -n "${MARATHON_HOST:-}" ]; then
        marathon::debug "host from env: $MARATHON_HOST"
        return
    fi
    local name="${MARATHON_DEVICE:-}"
    if [ -z "$name" ] && [ -f "$MARATHON_DEVICES_FILE" ]; then
        name="$(grep -vE '^\s*(#|$)' "$MARATHON_DEVICES_FILE" | awk 'NR==1 {print $1}')"
    fi
    if [ -n "$name" ] && [ -f "$MARATHON_DEVICES_FILE" ]; then
        local line
        line="$(grep -vE '^\s*(#|$)' "$MARATHON_DEVICES_FILE" | awk -v n="$name" '$1==n {print; exit}')"
        if [ -n "$line" ]; then
            local host kind
            host="$(echo "$line" | awk '{print $3}')"
            kind="$(echo "$line" | awk '{print $2}')"
            export MARATHON_HOST="$host"
            export MARATHON_DEVICE="$name"
            export MARATHON_DEVICE_KIND="$kind"
            marathon::debug "device=$name kind=$MARATHON_DEVICE_KIND host=$MARATHON_HOST"
            return
        fi
        marathon::warn "device '$name' not in $MARATHON_DEVICES_FILE — falling back to marathon.local"
    fi
    export MARATHON_HOST="root@marathon.local"
    export MARATHON_DEVICE="${MARATHON_DEVICE:-default}"
    export MARATHON_DEVICE_KIND="${MARATHON_DEVICE_KIND:-unknown}"
}

marathon::device::list() {
    if [ ! -f "$MARATHON_DEVICES_FILE" ]; then
        echo "no $MARATHON_DEVICES_FILE — using default host root@marathon.local" >&2
        return
    fi
    printf '  %-10s %-10s %-30s %s\n' NAME KIND HOST NOTES
    grep -vE '^\s*(#|$)' "$MARATHON_DEVICES_FILE" | \
        awk '{name=$1; kind=$2; host=$3; notes=""; for(i=4;i<=NF;i++) notes=notes" "$i;
              printf "  %-10s %-10s %-30s%s\n", name, kind, host, notes}'
}

# ── SSH ──────────────────────────────────────────────────────────────
#
# ControlMaster/ControlPath multiplex every `marathon` command over a
# single persistent SSH connection to a device. Without it, each
# invocation opens a new SSH login: pam auth → logind session-start →
# systemd user-manager touch → dbus session-registered signal →
# eventually the shell + oom sidecar all wake and chew CPU. Dogfooding
# measured that overhead at ~20 % of one CPU sustained just from
# session churn (systemd 6.5 % + logind 4.2 % + sshd 3.0 % + dbus 2.2 %
# + journal 1.8 % + shell wake 3.6 %). ControlPersist=60 keeps the
# muxed socket for a minute after the last command — enough to reuse
# across a typical dev workflow — then reaps.
#
# Socket path is per-host so multi-device (`marathon --device cm5`)
# works. Path is under /tmp so it dies on reboot without cleanup.
_marathon_ssh_ctl_dir="/tmp/marathon-cli-ssh-$UID"
mkdir -p "$_marathon_ssh_ctl_dir" 2>/dev/null || true
chmod 700 "$_marathon_ssh_ctl_dir" 2>/dev/null || true
_marathon_ssh_opts=(
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=5
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=3
    -o ControlMaster=auto
    -o "ControlPath=$_marathon_ssh_ctl_dir/%r@%h:%p"
    -o ControlPersist=60
)

marathon::ssh() {
    marathon::debug "ssh $MARATHON_HOST -- $*"
    sshpass -p "$MARATHON_PASSWORD" ssh "${_marathon_ssh_opts[@]}" "$MARATHON_HOST" "$@"
}

# Interactive / long-lived SSH — allocates a remote TTY so that when
# this SSH channel closes (Ctrl-C locally, network drop, script exit),
# the remote TTY closes and SIGHUP kills the entire remote process
# group. Use for `while true` loops (monitors, taillers, benches).
# Without -t, the remote `sh -c` loop becomes an orphan and keeps
# spinning at ~5-10 % CPU forever — a real bug we hit in dogfooding.
marathon::ssh::interactive() {
    marathon::debug "ssh -t $MARATHON_HOST -- $*"
    sshpass -p "$MARATHON_PASSWORD" ssh -tt "${_marathon_ssh_opts[@]}" "$MARATHON_HOST" "$@"
}

marathon::scp() {
    # marathon::scp <local> <remote-path>
    marathon::debug "scp $1 -> $MARATHON_HOST:$2"
    sshpass -p "$MARATHON_PASSWORD" scp "${_marathon_ssh_opts[@]}" "$1" "$MARATHON_HOST:$2"
}

marathon::ssh::alive() {
    sshpass -p "$MARATHON_PASSWORD" ssh -o ConnectTimeout=3 -o BatchMode=no \
        "${_marathon_ssh_opts[@]}" "$MARATHON_HOST" 'echo ok' >/dev/null 2>&1
}

marathon::wait_reachable() {
    local timeout="${1:-90}"
    local deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        marathon::ssh::alive && return 0
        sleep 2
    done
    marathon::error "device not reachable within ${timeout}s"
    return 1
}

# ── Askpass ─────────────────────────────────────────────────────────
marathon::askpass::ensure() {
    if [ -x /tmp/askpass.sh ]; then
        export SUDO_ASKPASS=/tmp/askpass.sh
        return 0
    fi
    if [ -x "$HOME/.marathon-secrets/askpass.sh" ]; then
        cp "$HOME/.marathon-secrets/askpass.sh" /tmp/askpass.sh
        chmod 700 /tmp/askpass.sh
        export SUDO_ASKPASS=/tmp/askpass.sh
        marathon::debug "restored /tmp/askpass.sh from ~/.marathon-secrets/"
        return 0
    fi
    marathon::error "no askpass — put askpass.sh at ~/.marathon-secrets/ (0700)"
    return 1
}

# ── Help ────────────────────────────────────────────────────────────
marathon::usage() {
    cat >&2 <<'HELP'
marathon — dev CLI for Marathon Shell.

USAGE
  marathon [FLAGS] <verb> [ARGS]

GLOBAL FLAGS
  --device, -d NAME     target device (see 'marathon device list')
  --host, -H HOST       override SSH host (root@marathon.local etc.)
  --verbose, -v         debug output
  --quiet, -q           suppress info/step lines
  --help, -h            this help
  --version             tool version

DAILY-DRIVERS (Phase 1)
  status                shell state + hash + device state at a glance
  deploy [--hot|--full] build shell (if src changed) + push binary + verify
  reset                 restart greetd cleanly
  wake                  force backlight on (bl_power=0, brightness=200)
  unlock [PIN]          enter PIN reliably (default 027602)
  snap [LABEL]          screenshot device (SIGUSR1 capture)
  logs [-f] [GREP]      tail shell log
  apps                  running app-runners + their cgroup state
  launch APPID          unlock + navigate + tap the app icon

INTERACTION + MEASUREMENT (Phase 2)
  monitor <what>        cgroup | logs | wifi | modem | freq | bl | wakeups
  tap X Y               synthetic tap
  swipe X1 Y1 X2 Y2     synthetic swipe
  power                 synthetic KEY_POWER (test wake path)
  doze enter|exit|status
  freq [--sample N]     cpufreq time-in-state histogram over N seconds
  irqs                  /proc/interrupts delta over 2 seconds
  wakeups               /sys/kernel/debug/wakeup_sources sorted
  cgroup APPID          full per-app cgroup state

SPECIALIST PROBES (Phase 3)
  modem <at CMD|psm|edrx|info|reset>
  wifi <psm|scan>
  gov <ondemand|schedutil|conservative|performance>
  scheduler <disk> <sched>
  fuel-gauge            current, voltage, charge, temp, health
  backlight <val>       set brightness

APP-DEV LIFECYCLE (Phase 4)
  app new NAME          scaffold app from template
  app run [--hot] DIR   local + on-device run
  app package [--sign] DIR
  app validate DIR
  app install FILE
  app watch DIR         auto-repackage + hot-swap on file change
  app registry          list installed marathon apps

DOCTOR (Phase 5)
  doctor [--fix]        check env + auto-heal known failures

DEVICES
  device list           list configured devices
  device current        show active device

  Devices file: ~/.config/marathon-dev/devices.conf
    <name>  <kind>  <ssh-host>  [notes]
    l5      librem5    root@marathon.local  USB-net 172.16.42.1 fallback
    cm5     hackberry  root@marathon.local  HackberryPi CM5
HELP
}

cmd_device_list()    { marathon::device::list; }
cmd_device_current() { echo "$MARATHON_DEVICE ($MARATHON_DEVICE_KIND) → $MARATHON_HOST"; }
