# AI Agent Build Instructions for Marathon OS on Fedora

**Target Agent:** Claude or similar LLM coding assistant  
**Task:** Build and flash Marathon OS to OnePlus 6 on Fedora Linux  
**Repository:** Marathon-Image (current directory)  
**Status:** Scaffolding complete, ready for build

---

## CONTEXT & BACKGROUND

### What is Marathon OS?
Marathon OS is a BlackBerry 10-inspired mobile Linux distribution built on postmarketOS with:
- **Kernel:** Linux 6.17+ with mainlined PREEMPT_RT for real-time responsiveness
- **Shell:** Marathon Shell (Qt 6.9+ Wayland Compositor)
- **Target:** OnePlus 6 (SDM845, enchilada) as reference device
- **Goals:** Sub-16ms touch latency, days-long standby, instant app launch

### Repository State
All static files have been created on macOS:
- ✅ 3 Alpine packages (APKBUILDs)
- ✅ 8 system configuration files
- ✅ Device profiles for multi-device support
- ✅ Build scripts and documentation
- ⚠️ APKBUILD checksums set to `SKIP` (will be generated on first build)
- ⚠️ Cannot test on macOS (requires Linux + pmbootstrap)

### Your Mission
1. Verify Fedora environment is ready
2. Build all Marathon OS packages
3. Create flashable images
4. Flash to OnePlus 6 device
5. Validate post-boot system

---

## PHASE 1: ENVIRONMENT VERIFICATION

### Step 1.1: Verify You're on Fedora
```bash
# Check OS
cat /etc/os-release | grep -i fedora

# Should output Fedora version
```

**Expected:** Fedora 38, 39, or 40  
**If not Fedora:** STOP - These instructions are Fedora-specific

### Step 1.2: Check Current Directory
```bash
pwd
# Should be in Marathon-Image repository root

# Verify key files exist
ls -la packages/marathon-base-config/APKBUILD
ls -la scripts/build-and-flash.sh
ls -la docs/BUILD_THIS.md

# All should exist
```

**If not in correct directory:** Ask user for repository location, then `cd` to it.

### Step 1.3: Verify Required Tools Installed
```bash
# Check each tool
command -v pmbootstrap || echo "MISSING: pmbootstrap"
command -v fastboot || echo "MISSING: fastboot"
command -v adb || echo "MISSING: adb"
command -v git || echo "MISSING: git"

# Check pmbootstrap version
pmbootstrap --version
```

**If missing tools:** Install them:
```bash
# Install all required packages
sudo dnf install -y pmbootstrap android-tools git python3 python3-pip

# Verify installations
pmbootstrap --version
fastboot --version
```

**Critical:** User MUST approve `sudo` command. Don't assume permission.

---

## PHASE 2: PMBOOTSTRAP INITIALIZATION

### Step 2.1: Check pmbootstrap Status
```bash
# Check if already initialized
pmbootstrap config device

# If output shows device: already configured
# If error: needs initialization
```

### Step 2.2: Initialize pmbootstrap (if needed)
```bash
# Run initialization
pmbootstrap init
```

**Interactive prompts - Tell user to input:**
1. **Channel:** `edge`
2. **Vendor:** `oneplus`
3. **Codename:** `enchilada`
4. **Username:** (user's choice, suggest: `user`)
5. **UI:** `none` (Marathon Shell will be added separately)
6. **Additional packages:** (leave empty)
7. **Hostname:** (suggest: `marathon-phone`)
8. **Build options:** (accept defaults)

**Important:** Explain these choices to user as they input them.

### Step 2.3: Verify pmbootstrap Configuration
```bash
# Check configuration
pmbootstrap status

# Should show:
# - Device: oneplus-enchilada
# - Channel: edge
# - Init: systemd
```

**If wrong configuration:** Run `pmbootstrap init` again.

---

## PHASE 3: KERNEL VERSION VERIFICATION

### Step 3.1: Check Linux 6.17 Availability
```bash
# Try to fetch Linux 6.17
curl -I https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.0.tar.xz

# Check HTTP response code
```

**Expected:** HTTP 200 OK  
**If 404 (not released yet):**

```bash
# Check what versions are available
curl -s https://www.kernel.org/ | grep -oP 'linux-\d+\.\d+\.\d+' | sort -V | tail -5

# Use latest stable (6.16.x or whatever is available)
```

**Action if 6.17 not available:**
```bash
# Edit kernel APKBUILD
nano packages/linux-marathon/APKBUILD

# Change line:
# pkgver=6.17.0
# To:
# pkgver=6.16.x  (or latest available)

# Save and exit (Ctrl+O, Enter, Ctrl+X)
```

**Tell user:** "Linux 6.17 not yet released, using 6.16.x instead (still has mainlined PREEMPT_RT)."

---

## PHASE 4: MARATHON SHELL VERSION CHECK

### Step 4.1: Check Marathon Shell Releases
```bash
# Check GitHub releases
git ls-remote --tags https://github.com/patrickjquinn/Marathon-Shell | tail -5

# Lists available tags
```

**If releases exist:** Note latest version (e.g., v1.0.0)  
**If no releases:** Need to use git commit

### Step 4.2: Update marathon-shell APKBUILD

**If releases exist:**
```bash
# Verify version matches in APKBUILD
grep "^pkgver=" packages/marathon-shell/APKBUILD

# Should match latest release
# If not, update it
```

**If no releases exist:**
```bash
# Get latest commit hash
COMMIT=$(git ls-remote https://github.com/patrickjquinn/Marathon-Shell HEAD | awk '{print $1}' | cut -c1-8)
echo "Latest commit: $COMMIT"

# Edit APKBUILD to use git snapshot
nano packages/marathon-shell/APKBUILD

# Change:
# pkgver=1.0.0
# To:
# pkgver=0.1.0_git20251015
# 
# Add after pkgver line:
# _commit=<full-commit-hash>
#
# Change source line:
# source="marathon-shell-$_commit.tar.gz::https://github.com/patrickjquinn/Marathon-Shell/archive/$_commit.tar.gz"
```

**Tell user:** Explain which version is being used and why.

---

## PHASE 5: BUILD MARATHON OS

### Step 5.1: Run Build Script
```bash
# Start the build (this takes 30-60 minutes on first run)
./scripts/build-and-flash.sh enchilada

# Monitor output for errors
```

**Expected timeline:**
- Package copying: 1-2 minutes
- Kernel build: 20-30 minutes
- marathon-base-config build: 2-5 minutes
- marathon-shell build: 5-10 minutes
- Image creation: 5-10 minutes
- **Total: 30-60 minutes**

### Step 5.2: Monitor Build Progress

**Watch for these milestones:**
1. "Copying package sources to pmbootstrap workspace..." ✓
2. "Building custom kernel..." ✓
3. "Building marathon-base-config..." ✓
4. "Building marathon-shell..." ✓
5. "Installing system with custom packages..." ✓
6. "Exporting boot image and rootfs..." ✓
7. "Build Complete" ✓

**Common issues:**

**Issue: Package not found**
```
Error: Package 'marathon-base-config' not found
```
**Solution:** Check if packages were copied correctly:
```bash
ls ~/.local/var/pmbootstrap/cache_git/pmaports/main/marathon-base-config/
```

**Issue: Kernel build fails**
```
Error: Kernel compilation failed
```
**Solution:** Check build log:
```bash
pmbootstrap log | tail -100
```
Look for specific error, may need to adjust kernel config.

**Issue: Checksum mismatch**
```
Error: Checksum mismatch for source
```
**Solution:** Generate checksums:
```bash
cd ~/.local/var/pmbootstrap/cache_git/pmaports/main/marathon-base-config
abuild checksum

# Copy generated checksums back to source
```

### Step 5.3: Verify Build Output
```bash
# Check output directory
ls -lh out/enchilada/

# Should contain:
# - boot-oneplus-enchilada.img
# - postmarketos-oneplus-enchilada.img (or .img.xz)
```

**If output missing:** Build failed, check logs with `pmbootstrap log`.

---

## PHASE 6: DEVICE PREPARATION

### Step 6.1: Check Device Connection
```bash
# Is device connected?
lsusb | grep -i oneplus

# Check ADB connection (if device is in OS)
adb devices

# Check fastboot connection (if device is in bootloader)
fastboot devices
```

**If no devices found:**
```bash
# Check USB permissions
groups $USER | grep -E '(plugdev|dialout)'

# If not in groups, user needs to add themselves:
sudo usermod -aG plugdev,dialout $USER

# Then logout/login or:
newgrp plugdev
```

**Tell user:** "Need to connect OnePlus 6 via USB. Should I proceed?"

### Step 6.2: Boot Device to Fastboot
```bash
# If device is in Android/Linux OS:
adb reboot bootloader

# Wait 5-10 seconds, then verify:
fastboot devices

# Should show device serial number
```

**If fastboot doesn't detect device:**
```bash
# Try with sudo (not ideal, but may work)
sudo fastboot devices

# Check udev rules
cat /etc/udev/rules.d/51-android.rules

# If missing, create:
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0666", GROUP="plugdev"' | \
sudo tee /etc/udev/rules.d/51-android-oneplus.rules

sudo udevadm control --reload-rules
sudo udevadm trigger
```

### Step 6.3: Verify Bootloader Unlocked
```bash
# Check bootloader status
fastboot oem device-info

# Look for: "Device unlocked: true"
```

**If locked:**
```
ERROR: Bootloader is locked. Cannot flash custom images.
```

**Tell user:** "Bootloader must be unlocked. This will WIPE all data. Proceed?"

**If user approves:**
```bash
# Unlock bootloader (WIPES DATA!)
fastboot oem unlock
# Or on newer devices:
fastboot flashing unlock

# User must confirm on device screen
```

---

## PHASE 7: FLASH MARATHON OS

### Step 7.1: Flash Boot Image
```bash
# Get exact filename
BOOT_IMG=$(ls out/enchilada/boot-*.img)
echo "Flashing: $BOOT_IMG"

# Flash boot partition
fastboot flash boot "$BOOT_IMG"

# Wait for completion
```

**Expected output:**
```
Sending 'boot' (xxx KB)...                        OKAY
Writing 'boot'...                                 OKAY
Finished. Total time: x.xxx s
```

**If error:** Check that fastboot has permission, may need `sudo`.

### Step 7.2: Flash System Image
```bash
# Get exact filename
SYSTEM_IMG=$(ls out/enchilada/postmarketos-*.img 2>/dev/null || ls out/enchilada/postmarketos-*.img.xz)
echo "Flashing: $SYSTEM_IMG"

# If compressed, decompress first
if [[ "$SYSTEM_IMG" == *.xz ]]; then
    xz -d "$SYSTEM_IMG"
    SYSTEM_IMG="${SYSTEM_IMG%.xz}"
fi

# Flash userdata partition
fastboot flash userdata "$SYSTEM_IMG"

# This takes 2-5 minutes for large image
```

**Expected output:**
```
Sending 'userdata' (xxxx KB)...                   OKAY
Writing 'userdata'...                             OKAY
Finished. Total time: xxx.xxx s
```

### Step 7.3: Reboot Device
```bash
# Reboot to Marathon OS
fastboot reboot

# Device will restart
```

**Tell user:** "Device is rebooting to Marathon OS. First boot takes 2-3 minutes."

---

## PHASE 8: POST-BOOT VERIFICATION

### Step 8.1: Monitor First Boot
```bash
# Watch for device to boot
# Expected timeline:
# - Bootloader: 5 seconds
# - Kernel: 10-15 seconds  
# - Systemd init: 30-60 seconds
# - Marathon Shell: 10-20 seconds
# Total: 2-3 minutes
```

**Success indicators visible on device screen:**
- OnePlus logo (bootloader)
- Tux penguin / boot messages (kernel)
- Marathon Shell UI appears
- Status bar shows time
- Touch input responsive

**If stuck at OnePlus logo >1 minute:**
```
ISSUE: Bootloader not loading kernel
SOLUTION: Boot partition may not be flashed correctly
```

**If kernel panic / error messages:**
```
ISSUE: Kernel failed to boot
SOLUTION: Kernel config may be incompatible
```

**If black screen after boot messages:**
```
ISSUE: Marathon Shell not starting
SOLUTION: Display driver or compositor issue
```

### Step 8.2: Get Device IP Address

**Option A: Check on device screen**
- Marathon Shell should show WiFi settings
- Connect to network
- Note IP address

**Option B: USB networking**
```bash
# Check if USB networking enabled
ip addr show | grep usb

# Device may appear as 192.168.2.15 or similar
```

**Option C: Check router DHCP leases**
```bash
# Or ask user to check their router
```

### Step 8.3: SSH into Device
```bash
# SSH into device (use IP from previous step)
ssh user@192.168.x.x
# Or
ssh user@marathon-phone.local

# Default password may be prompted
# (set during pmbootstrap init)
```

### Step 8.4: Run Validation Script
```bash
# On device, run validation
./validate-system.sh

# Or if script not on device:
curl -o validate-system.sh https://raw.githubusercontent.com/patrickjquinn/Marathon-Image/main/scripts/validate-system.sh
chmod +x validate-system.sh
./validate-system.sh
```

**Expected output:**
```
=== Marathon OS System Validation ===

1. Kernel Version & RT Status
   Kernel: 6.17.0-Marathon
   ✓ Custom Marathon kernel detected
   ✓ PREEMPT_RT enabled

2. CPU Governor
   Governor: schedutil
   ✓ schedutil governor active

3. I/O Scheduler
   Scheduler: kyber
   ✓ Kyber scheduler active

4. zram Status
   ✓ zram enabled

5. Real-Time Priorities
   ✓ PipeWire has RT priority (88)
   ✓ ModemManager has RT priority (90)

6. Sleep Configuration
   ✓ Deep sleep mode active

=== Validation Complete ===
```

### Step 8.5: Report Results

**Success Criteria:**
- [x] Device boots to Marathon Shell UI
- [x] Display shows content
- [x] Touch input works
- [x] SSH accessible
- [x] Validation script passes all checks

**If all success criteria met:** 
```
✅ BUILD SUCCESSFUL! Marathon OS is running on OnePlus 6.

Performance Metrics to Test:
- Touch latency: Swipe and observe responsiveness (should feel instant)
- App launch: Tap app icon, measure to first frame (target: <300ms)
- Battery: Let device sleep overnight, check drain (target: ≤1%/hour)
```

**If any criteria fail:**
```
⚠️ BUILD PARTIALLY SUCCESSFUL
<List which criteria failed>

See docs/TROUBLESHOOTING.md for solutions.
```

---

## PHASE 9: ERROR HANDLING

### General Debugging Approach

1. **Check logs:**
   ```bash
   pmbootstrap log
   pmbootstrap log | tail -100
   ```

2. **Enter chroot for debugging:**
   ```bash
   pmbootstrap chroot
   # Inside chroot, can run commands, check package status
   exit
   ```

3. **Clean and retry:**
   ```bash
   # Clean package cache
   pmbootstrap zap -p
   
   # Clean everything (nuclear option)
   pmbootstrap zap -a
   
   # Re-initialize
   pmbootstrap init
   ```

4. **Check device logs (if SSH works):**
   ```bash
   ssh user@device-ip
   journalctl -xe
   dmesg | tail -50
   ```

### Specific Error Scenarios

**Scenario: Build fails with missing dependencies**
```bash
# Update pmaports
pmbootstrap pull

# Update chroot
pmbootstrap chroot -- apk upgrade
```

**Scenario: Kernel doesn't boot**
```bash
# Try booting with serial console to see error messages
# Or boot TWRP recovery to check logs
```

**Scenario: Marathon Shell doesn't start**
```bash
# Check if Marathon Shell binary exists
ssh user@device-ip "ls -la /usr/bin/marathon-shell"

# Check systemd status
ssh user@device-ip "systemctl --user status marathon-shell"

# Check logs
ssh user@device-ip "journalctl -u marathon-shell"
```

---

## AGENT BEHAVIOR GUIDELINES

### Communication Style
1. **Explain what you're doing:** Before each major step, tell user what's happening
2. **Show commands:** Always display commands before running them
3. **Report progress:** Update user on long-running operations
4. **Handle errors gracefully:** If something fails, explain why and suggest solutions
5. **Ask for confirmation:** For destructive operations (flashing, unlocking bootloader)

### Decision Making
1. **Adapt to environment:** If tool versions differ, adapt commands
2. **Handle missing files:** If expected file not found, investigate why
3. **Verify assumptions:** Don't assume - check that each step succeeded
4. **Timeout awareness:** Long builds are normal (30-60 min), don't give up

### Success Criteria
You've successfully completed your task when:
1. ✅ Marathon OS builds without errors
2. ✅ Images flash to device successfully
3. ✅ Device boots to Marathon Shell UI
4. ✅ Validation script passes (or you've documented which checks fail)
5. ✅ You've reported comprehensive results to user

### Documentation
After build, create a build report:
```markdown
# Marathon OS Build Report

**Date:** YYYY-MM-DD
**Device:** OnePlus 6 (enchilada)
**Build Duration:** XX minutes
**Status:** ✅ Success / ⚠️ Partial / ❌ Failed

## Environment
- Fedora version: XX
- pmbootstrap version: X.X.X
- Kernel version used: 6.X.X
- Marathon Shell version: X.X.X

## Build Steps Completed
- [x] Step 1...
- [x] Step 2...

## Issues Encountered
- Issue 1: Description and resolution
- Issue 2: Description and resolution

## Validation Results
<Paste validation script output>

## Performance Observations
- Touch latency: <observation>
- UI responsiveness: <observation>
- Boot time: <measurement>

## Recommendations
- <Any suggestions for improvement>
```

---

## QUICK REFERENCE COMMANDS

```bash
# Check status
pmbootstrap status
pmbootstrap log

# Build
./scripts/build-and-flash.sh enchilada

# Device interaction
adb devices
adb reboot bootloader
fastboot devices
fastboot flash boot <img>
fastboot flash userdata <img>
fastboot reboot

# Debugging
pmbootstrap chroot
pmbootstrap log | tail -100
pmbootstrap zap -p  # Clean packages
pmbootstrap zap -a  # Clean everything

# SSH to device
ssh user@<device-ip>
journalctl -xe
dmesg | tail
```

---

## IMPORTANT NOTES

1. **First build takes 30-60 minutes** - This is normal, don't timeout
2. **Bootloader unlock WIPES DATA** - Confirm with user first
3. **Device may appear bricked** - If black screen, try recovery mode
4. **Not all OnePlus 6 variants are identical** - Some may have different partitions
5. **This is experimental software** - User should have backup of important data

---

## COMPLETION CHECKLIST

At the end, verify you've done ALL of these:
- [ ] Verified Fedora environment
- [ ] Initialized pmbootstrap correctly
- [ ] Built all three packages successfully
- [ ] Created boot and system images
- [ ] Flashed images to device
- [ ] Verified device boots
- [ ] Ran validation script
- [ ] Documented results
- [ ] Reported to user

If any checklist item is incomplete, do not claim success. Identify what's missing and either complete it or explain why it couldn't be completed.

---

**END OF INSTRUCTIONS**

**Remember:** You are building a production mobile OS. Take your time, verify each step, and communicate clearly with the user. Good luck! 🚀


