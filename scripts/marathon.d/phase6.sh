#!/usr/bin/env bash
# marathon.d/phase6.sh — multi-device orchestration.
#
# Marathon supports Librem 5 + HackberryPi CM5 (+ QEMU sim). Commands:
#
#   marathon device list                          registered devices
#   marathon device current                       active target
#   marathon device use NAME                      persist default
#   marathon device add NAME KIND HOST [NOTES]    add to devices.conf
#   marathon device probe [NAME]                  reachable? uname? kind?
#   marathon --device NAME <verb>                 one-shot override
#   marathon all <verb> [ARGS]                    run on every reachable
#                                                 device in parallel
#   marathon compare <verb>                       run on all → side-by-side
#
# shellcheck source=common.sh
# shellcheck disable=SC2154

# ── device use ─────────────────────────────────────────────────────
cmd_device_use() {
    local name="${1:-}"
    [ -z "$name" ] && { marathon::error "usage: marathon device use NAME"; return 2; }
    if [ -f "$MARATHON_DEVICES_FILE" ] && \
       ! grep -qE "^\s*$name\s" "$MARATHON_DEVICES_FILE"; then
        marathon::error "device '$name' not in $MARATHON_DEVICES_FILE"
        return 2
    fi
    mkdir -p "$MARATHON_CONFIG_DIR"
    grep -vE '^MARATHON_DEVICE=' "$MARATHON_CONFIG_FILE" 2>/dev/null > "$MARATHON_CONFIG_FILE.new" || true
    echo "MARATHON_DEVICE=$name" >> "$MARATHON_CONFIG_FILE.new"
    mv "$MARATHON_CONFIG_FILE.new" "$MARATHON_CONFIG_FILE"
    marathon::success "default device → $name"
}

# ── device add ─────────────────────────────────────────────────────
cmd_device_add() {
    local name="${1:-}" kind="${2:-}" host="${3:-}"
    shift 3 2>/dev/null || true
    local notes="$*"
    if [ -z "$name" ] || [ -z "$kind" ] || [ -z "$host" ]; then
        marathon::error "usage: marathon device add NAME KIND HOST [NOTES]"
        return 2
    fi
    mkdir -p "$MARATHON_CONFIG_DIR"
    if [ -f "$MARATHON_DEVICES_FILE" ] && \
       grep -qE "^\s*$name\s" "$MARATHON_DEVICES_FILE"; then
        marathon::error "device '$name' already exists; edit $MARATHON_DEVICES_FILE"
        return 1
    fi
    printf '%s  %s  %s  %s\n' "$name" "$kind" "$host" "$notes" >> "$MARATHON_DEVICES_FILE"
    marathon::success "added: $name ($kind) → $host"
}

# ── device probe ────────────────────────────────────────────────────
cmd_device_probe() {
    local name="${1:-$MARATHON_DEVICE}"
    _probe_one() {
        local n="$1" k="$2" h="$3"
        printf '  %-10s %-10s %-25s  ' "$n" "$k" "$h"
        local out
        if out="$(sshpass -p "$MARATHON_PASSWORD" ssh -o ConnectTimeout=3 \
                    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR "$h" \
                    'echo -n reachable; echo -n " · $(uname -m)"; echo -n " · $(cat /proc/uptime | awk "{print int(\$1)}")s up"' \
                    2>/dev/null)"; then
            echo "${_c_green}$out${_c_reset}"
        else
            echo "${_c_red}unreachable${_c_reset}"
        fi
    }
    if [ "$name" = "all" ] || [ -z "$name" ]; then
        printf '  %-10s %-10s %-25s  %s\n' NAME KIND HOST STATUS
        if [ -f "$MARATHON_DEVICES_FILE" ]; then
            while read -r n k h _; do
                [ -z "$n" ] || [[ "$n" =~ ^# ]] && continue
                _probe_one "$n" "$k" "$h"
            done < "$MARATHON_DEVICES_FILE"
        else
            _probe_one "$MARATHON_DEVICE" "$MARATHON_DEVICE_KIND" "$MARATHON_HOST"
        fi
    else
        local line n k h
        if [ -f "$MARATHON_DEVICES_FILE" ]; then
            line="$(grep -E "^\s*$name\s" "$MARATHON_DEVICES_FILE" | head -1)"
        fi
        if [ -n "$line" ]; then
            n="$(echo "$line" | awk '{print $1}')"
            k="$(echo "$line" | awk '{print $2}')"
            h="$(echo "$line" | awk '{print $3}')"
        else
            n="$name"; k="$MARATHON_DEVICE_KIND"; h="$MARATHON_HOST"
        fi
        _probe_one "$n" "$k" "$h"
    fi
}

# ── all: run verb on every reachable device in parallel ────────────
cmd_all() {
    [ $# -eq 0 ] && { marathon::error "usage: marathon all <verb> [args]"; return 2; }
    if [ ! -f "$MARATHON_DEVICES_FILE" ]; then
        marathon::warn "no devices.conf — running on default only"
        "$@"
        return
    fi
    marathon::info "running '$*' on every reachable device"
    local pids=()
    local names=()
    while read -r n k h _; do
        [ -z "$n" ] || [[ "$n" =~ ^# ]] && continue
        (
            export MARATHON_DEVICE="$n"
            export MARATHON_DEVICE_KIND="$k"
            export MARATHON_HOST="$h"
            echo "── $n ($k) → $h ──"
            "$MARATHON_CLI_DIR/marathon" --device "$n" "$@" 2>&1 | sed "s/^/  /"
        ) &
        pids+=($!)
        names+=("$n")
    done < "$MARATHON_DEVICES_FILE"
    local i=0
    for pid in "${pids[@]}"; do
        wait "$pid" || marathon::warn "${names[$i]}: exit $?"
        i=$((i + 1))
    done
}

# ── compare: run verb on all, print side-by-side ────────────────────
cmd_compare() {
    [ $# -eq 0 ] && { marathon::error "usage: marathon compare <verb> [args]"; return 2; }
    if [ ! -f "$MARATHON_DEVICES_FILE" ]; then
        marathon::warn "no devices.conf — nothing to compare"
        return 1
    fi
    local outputs=()
    local names=()
    while read -r n _ _ _; do
        [ -z "$n" ] || [[ "$n" =~ ^# ]] && continue
        names+=("$n")
        local tmp
        tmp="$(mktemp)"
        outputs+=("$tmp")
        "$MARATHON_CLI_DIR/marathon" --device "$n" "$@" >"$tmp" 2>&1 &
    done < "$MARATHON_DEVICES_FILE"
    wait
    # Print side-by-side using paste.
    local hdr=""
    for n in "${names[@]}"; do
        hdr="${hdr}${n}\t"
    done
    printf "%b\n" "$hdr"
    paste "${outputs[@]}"
    rm -f "${outputs[@]}"
}
