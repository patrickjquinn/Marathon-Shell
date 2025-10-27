#!/bin/bash
# Marathon OS RT Configuration Script
# To be run as root during PostmarketOS setup

set -e

echo "=== Marathon OS Real-Time Configuration ==="
echo ""

# 1. Check kernel
echo "[1/5] Checking kernel configuration..."
if [ -f /sys/kernel/realtime ]; then
    RT_VALUE=$(cat /sys/kernel/realtime)
    if [ "$RT_VALUE" = "1" ]; then
        echo "  ✓ PREEMPT_RT kernel active"
    else
        echo "  ✗ PREEMPT_RT kernel not active"
        exit 1
    fi
else
    echo "  ✗ /sys/kernel/realtime not found"
    echo "  Checking uname..."
    if uname -a | grep -q "PREEMPT_RT"; then
        echo "  ✓ PREEMPT_RT found in kernel version"
    else
        echo "  ✗ PREEMPT_RT not detected"
        exit 1
    fi
fi

# 2. Configure RT limits
echo ""
echo "[2/5] Configuring RT scheduling limits..."
cat > /etc/security/limits.d/99-marathon.conf <<EOF
# Marathon OS Real-Time Scheduling Limits
# Per Marathon OS Technical Specification v1.2

@marathon-users  -  rtprio  90
@marathon-users  -  nice   -10
@marathon-users  -  memlock unlimited
EOF
echo "  ✓ Created /etc/security/limits.d/99-marathon.conf"

# 3. Create marathon-users group
echo ""
echo "[3/5] Creating marathon-users group..."
if ! getent group marathon-users > /dev/null 2>&1; then
    groupadd marathon-users
    echo "  ✓ Created marathon-users group"
else
    echo "  ✓ marathon-users group already exists"
fi

# Add default user to group (adjust username as needed)
DEFAULT_USER=$(getent passwd 1000 | cut -d: -f1)
if [ -n "$DEFAULT_USER" ]; then
    usermod -aG marathon-users "$DEFAULT_USER"
    echo "  ✓ Added $DEFAULT_USER to marathon-users group"
fi

# 4. Configure systemd services
echo ""
echo "[4/5] Configuring systemd service priorities..."

# ModemManager (Priority 90)
mkdir -p /etc/systemd/system/ModemManager.service.d
cat > /etc/systemd/system/ModemManager.service.d/rt-priority.conf <<EOF
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=90
EOF
echo "  ✓ Configured ModemManager (RT priority 90)"

# PipeWire (Priority 88)
mkdir -p /etc/systemd/user/pipewire.service.d
cat > /etc/systemd/user/pipewire.service.d/rt-priority.conf <<EOF
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=88
EOF
echo "  ✓ Configured PipeWire (RT priority 88)"

# Marathon Shell (Priority 75)
mkdir -p /etc/systemd/user/marathon-shell.service.d
cat > /etc/systemd/user/marathon-shell.service.d/rt-priority.conf <<EOF
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=75
EOF
echo "  ✓ Configured Marathon Shell (RT priority 75)"

# 5. Configure sysctl parameters
echo ""
echo "[5/5] Configuring kernel parameters..."
cat > /etc/sysctl.d/99-marathon.conf <<EOF
# Marathon OS System Tuning
# Per Marathon OS Technical Specification v1.2

# zram configuration
vm.swappiness = 100
vm.page-cluster = 0
vm.vfs_cache_pressure = 150

# Memory management
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.min_free_kbytes = 65536

# Network tuning
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fastopen = 3
EOF
echo "  ✓ Created /etc/sysctl.d/99-marathon.conf"
sysctl --system > /dev/null 2>&1
echo "  ✓ Applied kernel parameters"

# 6. Configure I/O scheduler
echo ""
echo "[6/6] Configuring I/O scheduler..."
cat > /etc/udev/rules.d/60-ioschedulers.rules <<EOF
# Marathon OS I/O Scheduler Configuration
# Kyber scheduler optimized for flash storage (UFS/eMMC)

ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*|nvme[0-9]*", ATTR{queue/scheduler}="kyber"
EOF
echo "  ✓ Created /etc/udev/rules.d/60-ioschedulers.rules"
udevadm control --reload-rules
echo "  ✓ Reloaded udev rules"

# Done
echo ""
echo "=== Configuration Complete ==="
echo ""
echo "⚠️  IMPORTANT: You must REBOOT for RT limits to take effect"
echo ""
echo "After reboot, verify with:"
echo "  ulimit -r   # Should show 90"
echo "  cat /sys/kernel/realtime   # Should show 1"
echo "  ps -eLo pid,tid,class,rtprio,comm | grep marathon   # Check RT priorities"
echo ""

