# Marathon OS Troubleshooting Guide

Common issues and solutions for Marathon OS on OnePlus 6.

## Performance Issues

### Laggy UI / Stuttering

**Symptoms:** Touch response feels delayed, animations stutter, apps freeze momentarily

**Diagnostics:**

```bash
# Check if RT priorities are active
ps -eo pid,rtprio,ni,comm | grep -E '(marathon|pipewire|ModemManager)'

# Verify CPU governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check I/O scheduler
cat /sys/block/mmcblk0/queue/scheduler

# Monitor CPU throttling
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
```

**Solutions:**

1. **RT priorities not active:**
   ```bash
   # Check if marathon-base-config is installed
   apk info marathon-base-config
   
   # Reinstall if missing
   sudo apk add --allow-untrusted marathon-base-config
   
   # Restart affected services
   sudo systemctl restart pipewire ModemManager
   ```

2. **Wrong CPU governor:**
   ```bash
   # Manually set schedutil
   for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
       echo schedutil | sudo tee $cpu
   done
   
   # Check udev rules
   sudo udevadm control --reload-rules
   sudo udevadm trigger
   ```

3. **Wrong I/O scheduler:**
   ```bash
   # Manually set kyber
   echo kyber | sudo tee /sys/block/mmcblk0/queue/scheduler
   
   # Verify udev rules exist
   cat /etc/udev/rules.d/60-marathon-iosched.rules
   ```

4. **CPU thermal throttling:**
   ```bash
   # Check temperatures
   cat /sys/class/thermal/thermal_zone*/temp
   
   # If > 80°C, check for runaway processes
   top -bn1 | head -20
   ```

### Slow App Launch

**Symptoms:** Apps take > 1 second to show first frame

**Diagnostics:**

```bash
# Check available memory
free -m

# Check zram status
zramctl

# Check I/O wait
iostat -x 1 5
```

**Solutions:**

1. **Low memory / no zram:**
   ```bash
   # Check if zram is active
   cat /proc/swaps
   
   # If not, enable zram-generator
   sudo systemctl enable systemd-zram-setup@zram0.service
   sudo systemctl start systemd-zram-setup@zram0.service
   ```

2. **Slow storage:**
   ```bash
   # Test read speed
   dd if=/dev/mmcblk0 of=/dev/null bs=1M count=100 iflag=direct
   
   # Test write speed
   dd if=/dev/zero of=/tmp/test bs=1M count=100 oflag=direct
   rm /tmp/test
   
   # Should be > 100 MB/s for both
   ```

3. **Filesystem issues:**
   ```bash
   # Check for ext4 errors
   sudo dmesg | grep -i ext4
   
   # Check F2FS status (if used)
   sudo dmesg | grep -i f2fs
   
   # Remount with proper options
   sudo mount -o remount,noatime,discard /home
   ```

## Power Issues

### Battery Drains Fast in Suspend

**Symptoms:** > 2% battery drain per hour while screen off

**Diagnostics:**

```bash
# Check wake sources
cat /sys/kernel/wakeup_sources | awk 'NR>1 && ($6>0 || $7>0)'

# Check suspend mode
cat /sys/power/mem_sleep

# Check which devices are preventing sleep
cat /sys/power/wakeup_count

# Monitor actual sleep state
sudo journalctl -f &
# Then press power button to sleep and wake
# Look for "PM: suspend entry" and "PM: suspend exit"
```

**Solutions:**

1. **Not using deep sleep:**
   ```bash
   # Check current sleep mode
   cat /sys/power/mem_sleep
   
   # Should show: s2idle [deep]
   # If not, set it:
   echo deep | sudo tee /sys/power/mem_sleep
   
   # Make permanent in kernel cmdline (edit /boot/grub/grub.cfg):
   # Add: mem_sleep_default=deep
   ```

2. **Too many wake sources:**
   ```bash
   # Disable Wi-Fi wake
   echo disabled | sudo tee /sys/class/net/wlan0/device/power/wakeup
   
   # Disable Bluetooth wake
   echo disabled | sudo tee /sys/class/bluetooth/hci0/power/wakeup
   
   # Only keep: modem, RTC, power button, USB
   ```

3. **Services preventing suspend:**
   ```bash
   # Check for systemd inhibitors
   systemd-inhibit --list
   
   # Check for active wakelocks
   cat /sys/power/wake_lock
   ```

### Device Won't Suspend

**Symptoms:** Screen turns off but CPU stays active, battery drains quickly

**Diagnostics:**

```bash
# Try manual suspend
sudo systemctl suspend

# Check for errors
sudo journalctl -xe

# List processes preventing suspend
sudo lsof | grep -i sleep
```

**Solutions:**

1. **Kernel doesn't support suspend:**
   ```bash
   # Verify PM_SLEEP is enabled
   zgrep CONFIG_PM_SLEEP /proc/config.gz
   
   # Should output: CONFIG_PM_SLEEP=y
   # If not, kernel rebuild required
   ```

2. **Driver issues:**
   ```bash
   # Check dmesg for suspend errors
   sudo dmesg | grep -i "suspend\|resume"
   
   # Common culprits: GPU, modem, audio
   # Try unloading and reloading drivers
   ```

### Device Won't Wake from Suspend

**Symptoms:** Device suspends but doesn't wake on power button

**Diagnostics:**

```bash
# Check if power button is wake source
cat /sys/devices/platform/soc/c440000.spmi/spmi-0/0-00/power/wakeup

# Check if wake interrupts are configured
cat /proc/interrupts | grep -i wake
```

**Solutions:**

1. **Enable power button wake:**
   ```bash
   # Find power button device
   find /sys/devices -name "power" | xargs grep -l "enabled" | grep power_supply
   
   # Enable wakeup
   echo enabled | sudo tee /sys/devices/.../power/wakeup
   ```

2. **Hard reboot required:**
   - Hold Power + Volume Down for 10 seconds
   - May indicate kernel panic during resume
   - Check logs after reboot: `sudo journalctl -b -1`

## Audio Issues

### No Sound / Audio Crackling

**Symptoms:** No audio output, or audio has pops/clicks

**Diagnostics:**

```bash
# Check PipeWire status
systemctl --user status pipewire pipewire-pulse wireplumber

# Check audio device
aplay -l

# Test audio
speaker-test -t sine -f 1000 -c 2
```

**Solutions:**

1. **PipeWire not running:**
   ```bash
   # Start services
   systemctl --user start pipewire pipewire-pulse wireplumber
   
   # Enable at login
   systemctl --user enable pipewire pipewire-pulse wireplumber
   ```

2. **Wrong audio device:**
   ```bash
   # List PipeWire devices
   pw-cli list-objects | grep -A10 "node.name"
   
   # Set default sink
   pactl set-default-sink <sink-name>
   ```

3. **Buffer underruns (crackling):**
   ```bash
   # Check RT priority
   ps -eo rtprio,comm | grep pipewire
   
   # Should be running with RTPRIO 88
   # If not, check /etc/systemd/system/pipewire.service.d/50-priority.conf
   
   # Increase buffer size (trade-off: higher latency)
   # Edit ~/.config/pipewire/pipewire.conf:
   # default.clock.quantum = 1024
   # default.clock.min-quantum = 512
   ```

### Audio Delays / Sync Issues

**Symptoms:** Audio lags behind video, or delayed touch sounds

**Solutions:**

```bash
# Check quantum setting
pw-metadata -n settings

# Should show quantum around 512-1024 for phone
# Lower = less latency, higher = fewer glitches

# Set quantum
pw-metadata -n settings 0 clock.force-quantum 512
```

## Telephony Issues

### Modem Not Detected

**Symptoms:** No cellular signal, modem missing in Settings

**Diagnostics:**

```bash
# List modems
mmcli -L

# Check ModemManager status
systemctl status ModemManager

# Check kernel modem driver
dmesg | grep -i qcom
dmesg | grep -i mhi
```

**Solutions:**

1. **ModemManager not running:**
   ```bash
   sudo systemctl start ModemManager
   sudo systemctl enable ModemManager
   ```

2. **Modem driver not loaded:**
   ```bash
   # Check if modules are loaded
   lsmod | grep qcom
   lsmod | grep mhi
   
   # Load manually
   sudo modprobe mhi_pci_generic
   sudo modprobe qcom_q6v5_mss
   ```

3. **Firmware missing:**
   ```bash
   # Check firmware directory
   ls /lib/firmware/qcom/sdm845/enchilada/
   
   # Should contain modem firmware
   # If missing, extract from stock ROM
   ```

### Calls Drop / No SMS

**Symptoms:** Can't make calls, SMS not sending/receiving

**Diagnostics:**

```bash
# Check modem state
mmcli -m 0

# Check signal strength
mmcli -m 0 --signal-get

# Check registration
mmcli -m 0 --3gpp-scan
```

**Solutions:**

1. **Wrong APN:**
   ```bash
   # List connections
   nmcli connection show
   
   # Edit cellular connection
   nmcli connection edit <connection-name>
   
   # Set APN (carrier-specific)
   set gsm.apn "your-carrier-apn"
   save
   quit
   
   # Reconnect
   nmcli connection up <connection-name>
   ```

2. **Modem not registered:**
   ```bash
   # Force network scan
   mmcli -m 0 --3gpp-scan
   
   # Register manually
   mmcli -m 0 --3gpp-register-in-operator=<operator-id>
   ```

## Display Issues

### Screen Doesn't Turn On

**Symptoms:** Backlight off, or frozen display

**Diagnostics:**

```bash
# Check if compositor is running
ps aux | grep marathon-shell

# Check GPU
dmesg | grep -i msm
dmesg | grep -i drm

# Check for kernel panic
sudo journalctl -b -1 | grep -i panic
```

**Solutions:**

1. **Compositor crashed:**
   ```bash
   # Restart from SSH
   sudo systemctl restart display-manager
   
   # Or kill and restart
   killall marathon-shell
   /usr/bin/marathon-compositor &
   ```

2. **GPU driver issue:**
   ```bash
   # Check GPU firmware
   ls /lib/firmware/qcom/a630_*
   
   # Reload GPU driver
   sudo modprobe -r msm
   sudo modprobe msm
   ```

### Screen Tearing / Artifacts

**Symptoms:** Visual glitches, screen tearing during scrolling

**Solutions:**

```bash
# Enable VSync in compositor
# Check Marathon Shell settings for VSync option

# Verify refresh rate
cat /sys/class/drm/card0-DSI-1/modes

# Should match panel (60Hz for OnePlus 6)
```

## System Issues

### System Won't Boot

**Symptoms:** Stuck at boot logo or black screen

**Recovery:**

1. **Boot into recovery:**
   - Power off
   - Hold Volume Down + Power
   - Select Recovery mode

2. **Check boot logs:**
   ```bash
   # From recovery, mount root
   mount /dev/mmcblk0p17 /mnt
   
   # Check logs
   cat /mnt/var/log/boot.log
   ```

3. **Boot into single-user mode:**
   - Edit kernel command line in bootloader
   - Add: `single` or `systemd.unit=rescue.target`
   - Debug from rescue shell

### Out of Memory / OOM Kills

**Symptoms:** Apps randomly close, system sluggish

**Diagnostics:**

```bash
# Check OOM kills
sudo dmesg | grep -i oom

# Check memory pressure
systemd-cgtop

# Check zram usage
zramctl
```

**Solutions:**

1. **Increase zram:**
   ```bash
   # Edit /etc/systemd/zram-generator.conf.d/50-marathon.conf
   # Change: zram-size = ram/2
   # To:     zram-size = ram * 0.75
   
   sudo systemctl restart systemd-zram-setup@zram0.service
   ```

2. **Tune OOM behavior:**
   ```bash
   # Adjust systemd-oomd
   sudo systemctl edit systemd-oomd.service
   
   # Add:
   [Service]
   Environment="SYSTEMD_DEFAULT_MEMORY_PRESSURE_DURATION_SEC=5s"
   Environment="SYSTEMD_MEMORY_PRESSURE_DEFAULT_THRESHOLD_PERMILLE=80"
   ```

## Getting Help

If issues persist:

1. **Collect logs:**
   ```bash
   sudo journalctl -b > ~/marathon-boot.log
   sudo dmesg > ~/marathon-dmesg.log
   sudo systemctl status > ~/marathon-services.log
   ```

2. **Check config:**
   ```bash
   zgrep CONFIG_PREEMPT_RT /proc/config.gz > ~/kernel-config.txt
   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor > ~/governor.txt
   cat /sys/block/mmcblk0/queue/scheduler > ~/iosched.txt
   ```

3. **Report issue:**
   - GitHub: https://github.com/patrickjquinn/Marathon-Image/issues
   - Include: device model, kernel version, logs, steps to reproduce

---

**Last updated:** October 2025


