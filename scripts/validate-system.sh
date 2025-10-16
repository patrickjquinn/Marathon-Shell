#!/bin/bash
# Marathon OS Post-Boot Validation Script
# Validates that all Marathon OS optimizations are active

set -e

COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

check_pass() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

check_fail() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

check_warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

echo "=== Marathon OS System Validation ==="
echo ""

echo "1. Kernel Version & RT Status"
KERNEL_VER=$(uname -r)
echo "   Kernel: $KERNEL_VER"
if echo "$KERNEL_VER" | grep -q "Marathon"; then
    check_pass "Custom Marathon kernel detected"
else
    check_warn "Not running Marathon kernel"
fi

if zgrep -q "CONFIG_PREEMPT_RT=y" /proc/config.gz 2>/dev/null || \
   grep -q "PREEMPT_RT" /boot/config-* 2>/dev/null; then
    check_pass "PREEMPT_RT enabled"
else
    check_fail "PREEMPT_RT not enabled"
fi

echo ""
echo "2. CPU Governor"
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
echo "   Governor: $GOVERNOR"
if [ "$GOVERNOR" = "schedutil" ]; then
    check_pass "schedutil governor active"
else
    check_warn "Expected schedutil, got $GOVERNOR"
fi

echo ""
echo "3. I/O Scheduler"
SCHED=$(cat /sys/block/mmcblk0/queue/scheduler 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' || echo "unknown")
echo "   Scheduler: $SCHED"
if [ "$SCHED" = "kyber" ]; then
    check_pass "Kyber scheduler active"
else
    check_warn "Expected kyber, got $SCHED"
fi

echo ""
echo "4. zram Status"
if command -v zramctl &> /dev/null; then
    zramctl
    if [ -e /dev/zram0 ]; then
        check_pass "zram enabled"
    else
        check_fail "zram not active"
    fi
else
    check_warn "zramctl not available"
fi

echo ""
echo "5. Real-Time Priorities"
echo "   Checking critical processes..."
ps -eo pid,rtprio,ni,comm | grep -E '(pipewire|ModemManager|marathon)' || \
    check_warn "No RT processes found for pipewire/ModemManager/marathon"

PIPEWIRE_RT=$(ps -eo rtprio,comm | grep pipewire | awk '{print $1}' | head -n1)
if [ ! -z "$PIPEWIRE_RT" ] && [ "$PIPEWIRE_RT" != "-" ]; then
    check_pass "PipeWire has RT priority ($PIPEWIRE_RT)"
else
    check_warn "PipeWire not running with RT priority"
fi

MODEM_RT=$(ps -eo rtprio,comm | grep ModemManager | awk '{print $1}' | head -n1)
if [ ! -z "$MODEM_RT" ] && [ "$MODEM_RT" != "-" ]; then
    check_pass "ModemManager has RT priority ($MODEM_RT)"
else
    check_warn "ModemManager not running with RT priority"
fi

echo ""
echo "6. Sleep Configuration"
SLEEP_MODE=$(cat /sys/power/mem_sleep 2>/dev/null || echo "unknown")
echo "   Available: $SLEEP_MODE"
if echo "$SLEEP_MODE" | grep -q "\[deep\]"; then
    check_pass "Deep sleep mode active"
elif echo "$SLEEP_MODE" | grep -q "deep"; then
    check_warn "Deep sleep available but not default"
else
    check_fail "Deep sleep not available"
fi

echo ""
echo "7. Wake Sources"
echo "   Active wake sources:"
cat /sys/kernel/wakeup_sources | awk 'NR>1 && ($6>0 || $7>0) {print "   - " $1}' || \
    echo "   (none active)"

echo ""
echo "8. Memory Info"
free -h

echo ""
echo "9. Swap Status"
cat /proc/swaps || echo "   No swap active"

echo ""
echo "=== Validation Complete ==="
echo ""
echo "Optional: Run performance tests"
echo "  I/O:  dd if=/dev/zero of=/tmp/test bs=1M count=100 oflag=direct"
echo "  GPU:  glmark2-wayland"
echo "  Stress: stress-ng --vm 2 --vm-bytes 400M --timeout 30s"


