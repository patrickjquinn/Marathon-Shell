#!/bin/bash
# Marathon Shell -- System Setup (idempotent)
#
# One-shot script that prepares a Linux system to run Marathon as the primary
# session. Safe to re-run: every step checks current state and only changes
# what's needed.
#
# Usage:
#   sudo ./scripts/setup-system.sh                # full setup
#   sudo ./scripts/setup-system.sh --no-greetd    # skip the autologin step
#   sudo ./scripts/setup-system.sh --check        # dry-run; report only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_ONLY=0
SKIP_GREETD=0

for arg in "$@"; do
  case "$arg" in
    --check)      CHECK_ONLY=1 ;;
    --no-greetd)  SKIP_GREETD=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

if [ "$EUID" -ne 0 ] && [ "$CHECK_ONLY" -eq 0 ]; then
    echo "Re-running under sudo..."
    exec sudo --preserve-env=USER,HOME "$0" "$@"
fi

# ---- helpers --------------------------------------------------------------

log_step()    { echo ""; echo "==> $*"; }
log_ok()      { echo "   $*"; }
log_skip()    { echo "    ~ $*"; }
log_err()     { echo "   $*" >&2; }

run_or_check() {
    if [ "$CHECK_ONLY" -eq 1 ]; then
        echo "    (would run) $*"
    else
        eval "$@"
    fi
}

ensure_pkgs() {
    local pkgs=("$@")
    local missing=()
    for p in "${pkgs[@]}"; do
        if command -v apk >/dev/null 2>&1; then
            apk info -e "$p" >/dev/null 2>&1 || missing+=("$p")
        elif command -v apt-get >/dev/null 2>&1; then
            dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
        elif command -v dnf >/dev/null 2>&1; then
            rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
        else
            return 0  # unknown package manager -- assume manual install
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_skip "Missing packages: ${missing[*]} -- install via your package manager"
        return 1
    fi
    return 0
}

enable_service() {
    local svc=$1
    if ! command -v systemctl >/dev/null 2>&1; then
        log_skip "systemctl not present -- assuming OpenRC; manually 'rc-update add $svc'"
        return 0
    fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        log_ok "$svc already enabled"
    else
        run_or_check "systemctl enable --now $svc 2>/dev/null || true"
        log_ok "$svc enabled"
    fi
}

# ---- 1. Required runtime packages -----------------------------------------

log_step "1/9 Required runtime packages"
ensure_pkgs ModemManager NetworkManager bluez upower power-profiles-daemon mmsd-tng \
            polkit pam at-spi2-core mobile-broadband-provider-info || \
    log_skip "Some optional services missing -- Marathon will degrade gracefully"

# ---- 2. PAM authentication stack ------------------------------------------

log_step "2/9 PAM (marathon-shell)"
PAM_SRC="$PROJECT_ROOT/pam.d/marathon-shell"
PAM_DST="/etc/pam.d/marathon-shell"
if [ -f "$PAM_DST" ] && cmp -s "$PAM_SRC" "$PAM_DST"; then
    log_ok "PAM config already current"
else
    if [ -f "$PAM_DST" ]; then
        run_or_check "cp '$PAM_DST' '$PAM_DST.backup-$(date +%Y%m%d-%H%M%S)'"
    fi
    run_or_check "install -m 644 -o root -g root '$PAM_SRC' '$PAM_DST'"
    log_ok "PAM config installed"
fi

# ---- 3. Backlight udev rule -----------------------------------------------

log_step "3/9 Backlight udev rule"
UDEV_SRC="$SCRIPT_DIR/90-backlight.rules"
UDEV_DST="/etc/udev/rules.d/90-backlight.rules"
if [ -f "$UDEV_DST" ] && cmp -s "$UDEV_SRC" "$UDEV_DST" 2>/dev/null; then
    log_ok "Backlight rule already current"
else
    if [ -f "$UDEV_SRC" ]; then
        run_or_check "install -m 644 '$UDEV_SRC' '$UDEV_DST'"
        run_or_check "udevadm control --reload-rules"
        run_or_check "udevadm trigger 2>/dev/null | grep -v macsmc || true"
        log_ok "Backlight rule installed"
    else
        log_skip "$UDEV_SRC not found"
    fi
fi

# ---- 4. RT scheduling -- CAP_SYS_NICE on the shell binary ------------------

log_step "4/9 Real-time scheduling capability"
SHELL_BIN_CANDIDATES=(
    "$PROJECT_ROOT/build/shell/marathon-shell-bin"
    "/usr/bin/marathon-shell-bin"
    "/usr/local/bin/marathon-shell-bin"
)
SHELL_BIN=""
for c in "${SHELL_BIN_CANDIDATES[@]}"; do
    if [ -f "$c" ]; then SHELL_BIN="$c"; break; fi
done
if [ -z "$SHELL_BIN" ]; then
    log_skip "marathon-shell-bin not found in expected paths -- build first"
else
    if getcap "$SHELL_BIN" 2>/dev/null | grep -q "cap_sys_nice"; then
        log_ok "CAP_SYS_NICE already granted on $SHELL_BIN"
    else
        run_or_check "setcap cap_sys_nice+ep '$SHELL_BIN'"
        log_ok "CAP_SYS_NICE granted on $SHELL_BIN"
    fi
fi

LIMITS_DST="/etc/security/limits.d/99-marathon.conf"
if [ ! -f "$LIMITS_DST" ]; then
    run_or_check "cat > '$LIMITS_DST' <<'EOF'
# Marathon Shell -- allow non-root processes to set realtime scheduling priority
# Required for QSGRenderThread / app render-thread elevation. See docs/RT_SCHEDULING.md.
*       hard    rtprio  10
*       soft    rtprio  10
EOF"
    log_ok "rtprio limit installed (10)"
else
    log_ok "rtprio limit already present"
fi

# ---- 5. systemd unit + greetd autologin -----------------------------------

log_step "5/9 marathon-shell.service"
SVC_SRC="$PROJECT_ROOT/platforms/generic/marathon-shell.service"
SVC_DST="/etc/systemd/system/marathon-shell.service"
if [ -f "$SVC_SRC" ]; then
    if [ -f "$SVC_DST" ] && cmp -s "$SVC_SRC" "$SVC_DST"; then
        log_ok "Unit already current"
    else
        run_or_check "install -m 644 '$SVC_SRC' '$SVC_DST'"
        run_or_check "systemctl daemon-reload"
        log_ok "Unit installed"
    fi
else
    log_skip "$SVC_SRC missing"
fi

if [ "$SKIP_GREETD" -eq 1 ]; then
    log_skip "greetd skipped (--no-greetd)"
else
    log_step "5b/9 greetd autologin"
    GREETD_SRC="$PROJECT_ROOT/platforms/generic/marathon-shell.toml"
    GREETD_DST="/etc/greetd/config.toml"
    if [ -f "$GREETD_SRC" ] && command -v greetd >/dev/null 2>&1; then
        if [ -f "$GREETD_DST" ] && cmp -s "$GREETD_SRC" "$GREETD_DST"; then
            log_ok "greetd config already current"
        else
            run_or_check "install -m 644 '$GREETD_SRC' '$GREETD_DST'"
            log_ok "greetd config installed"
        fi
    else
        log_skip "greetd not installed -- install it with your package manager"
    fi
fi

# ---- 6. Group memberships -------------------------------------------------

log_step "6/9 User group memberships"
TARGET_USER=${SUDO_USER:-${USER:-$(logname 2>/dev/null || echo unknown)}}
GROUPS_NEEDED=(audio video input render dialout)
if id "$TARGET_USER" >/dev/null 2>&1; then
    for g in "${GROUPS_NEEDED[@]}"; do
        if getent group "$g" >/dev/null 2>&1; then
            if id -nG "$TARGET_USER" | grep -qw "$g"; then
                log_ok "$TARGET_USER already in $g"
            else
                run_or_check "usermod -a -G $g $TARGET_USER"
                log_ok "$TARGET_USER added to $g"
            fi
        fi
    done
else
    log_skip "Cannot resolve target user -- set SUDO_USER explicitly"
fi

# ---- 7. Enable services ---------------------------------------------------

log_step "7/9 Enable services"
enable_service ModemManager
enable_service NetworkManager
enable_service bluetooth
enable_service power-profiles-daemon
# mmsd-tng is bus-activated; no enable step needed.

# ---- 8. Screenshot directory ----------------------------------------------

log_step "8/9 Screenshot directory"
SS_DIR="/home/$TARGET_USER/Pictures/Marathon-Screenshots"
if [ -d "$SS_DIR" ]; then
    log_ok "Already present"
else
    run_or_check "mkdir -p '$SS_DIR' && chown -R '$TARGET_USER':'$TARGET_USER' '$SS_DIR'"
    log_ok "Created $SS_DIR"
fi

# ---- 9. Summary -----------------------------------------------------------

log_step "9/9 Summary"
echo ""
echo "Marathon Shell setup complete."
echo ""
echo "Next steps:"
echo "  • Reboot, or:  systemctl start marathon-shell.service"
echo "  • Field-test the modem path per docs/MODEM_TESTING.md"
echo "  • Group changes require a logout/login (or reboot) to take effect"
echo ""
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "(--check was passed; no changes made.)"
fi
