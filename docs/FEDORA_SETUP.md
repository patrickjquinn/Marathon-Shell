# Fedora Workstation Setup Guide

**Complete guide to set up Fedora for building Marathon OS.**

## System Requirements

- Fedora 38, 39, or 40 (recommended: latest)
- x86_64 or ARM64 architecture
- 16GB RAM (minimum 8GB)
- 50GB free disk space
- Internet connection

## Step 1: Update System

```bash
# Update all packages
sudo dnf update -y

# Reboot if kernel was updated
sudo reboot
```

## Step 2: Install Build Tools

```bash
# Install development tools
sudo dnf groupinstall -y "Development Tools"

# Install specific build dependencies
sudo dnf install -y \
    git \
    python3 \
    python3-pip \
    cmake \
    ninja-build \
    gcc \
    gcc-c++ \
    make \
    bison \
    flex \
    bc \
    openssl-devel \
    elfutils-libelf-devel \
    perl \
    rsync \
    xz \
    ncurses-devel

# Verify installations
gcc --version
cmake --version
git --version
```

## Step 3: Install Android Tools

```bash
# Install fastboot and ADB
sudo dnf install -y android-tools

# Verify installations
fastboot --version
adb version

# Add udev rules for Android devices
sudo dnf install -y android-udev-rules

# Add your user to plugdev group (for device access)
sudo usermod -aG plugdev $USER
sudo usermod -aG dialout $USER

# Apply group changes (or logout/login)
newgrp plugdev
```

## Step 4: Install pmbootstrap

### Method 1: From Fedora Repos (Recommended)

```bash
# Install pmbootstrap from Fedora repos
sudo dnf install -y pmbootstrap

# Verify installation
pmbootstrap --version
```

### Method 2: From PyPI (If not in repos)

```bash
# Install via pip
pip3 install --user pmbootstrap

# Add to PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
pmbootstrap --version
```

### Method 3: From Git (Latest Development)

```bash
# Clone pmbootstrap
git clone --depth=1 https://gitlab.postmarketOS.org/postmarketOS/pmbootstrap.git

# Create symlink
mkdir -p ~/.local/bin
ln -s "$PWD/pmbootstrap/pmbootstrap.py" ~/.local/bin/pmbootstrap

# Add to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
pmbootstrap --version
```

## Step 5: Install QEMU (For Testing)

```bash
# Install QEMU for ARM64 emulation (optional, for testing without hardware)
sudo dnf install -y \
    qemu-system-aarch64 \
    qemu-user-static \
    binfmt-support

# Enable and start binfmt service
sudo systemctl enable --now systemd-binfmt.service

# Verify QEMU
qemu-system-aarch64 --version
```

## Step 6: Configure pmbootstrap

```bash
# Initialize pmbootstrap
pmbootstrap init

# Answer prompts:
# 1. Channel: edge
# 2. Device vendor: oneplus
# 3. Device codename: enchilada
# 4. Username: user (or your choice)
# 5. User interface: none
# 6. Additional packages: (leave empty, Marathon packages added by script)
# 7. Device hostname: marathon-phone
# 8. Build options: accept defaults

# Verify configuration
pmbootstrap config device
# Should output: oneplus-enchilada

pmbootstrap status
```

## Step 7: Clone Marathon Image Repository

```bash
# Create projects directory
mkdir -p ~/Projects
cd ~/Projects

# Clone Marathon-Image repository
git clone https://github.com/patrickjquinn/Marathon-Image.git
cd Marathon-Image

# Verify structure
ls -la
# Should see: packages/, configs/, devices/, docs/, scripts/
```

## Step 8: Verify Build Environment

```bash
# Test pmbootstrap chroot
pmbootstrap chroot

# Inside chroot, verify Alpine version
cat /etc/alpine-release
# Should show: 3.x.x

# Exit chroot
exit

# Check pmaports location
PMAPORTS="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
ls -la "$PMAPORTS"

# Should show pmaports repository structure
```

## Step 9: Configure Disk Space (Important!)

```bash
# Check available space
df -h ~/.local/var/pmbootstrap

# pmbootstrap work directory needs ~30GB free
# If not enough space, change work directory:

# Create new work directory on larger partition
mkdir -p /path/to/larger/disk/pmbootstrap-work

# Configure pmbootstrap to use it
pmbootstrap config work /path/to/larger/disk/pmbootstrap-work

# Verify
pmbootstrap config work
```

## Step 10: Set Up USB Permissions

```bash
# Create udev rule for OnePlus 6
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0666", GROUP="plugdev"' | \
sudo tee /etc/udev/rules.d/51-android-oneplus.rules

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Verify user groups
groups $USER
# Should include: plugdev, dialout
```

## Step 11: Test Device Connection

```bash
# Connect OnePlus 6 via USB with USB debugging enabled

# Test ADB connection
adb devices
# Should show your device if booted into OS

# Reboot to fastboot
adb reboot bootloader

# Test fastboot connection
fastboot devices
# Should show your device in fastboot mode

# Reboot back to OS
fastboot reboot
```

## Step 12: Optional - Install Qt Creator (For Shell Development)

```bash
# Only if you want to modify Marathon Shell
sudo dnf install -y \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel \
    qt6-qtwayland-devel \
    qt-creator

# Launch Qt Creator
qtcreator &
```

## Step 13: Verify Everything Works

```bash
cd ~/Projects/Marathon-Image

# Run a dry-run check (doesn't actually build)
./scripts/build-and-flash.sh enchilada --dry-run 2>/dev/null || echo "Script will work once on device"

# Check all dependencies
pmbootstrap status

# List available devices in pmaports
ls -la ~/.local/var/pmbootstrap/cache_git/pmaports/device/
```

## Common Issues & Solutions

### Issue: pmbootstrap command not found

```bash
# If installed via pip
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Or install from Fedora repos
sudo dnf install pmbootstrap
```

### Issue: Permission denied accessing device

```bash
# Check if in correct groups
groups $USER

# Add to groups if missing
sudo usermod -aG plugdev,dialout $USER

# Logout and login, or:
newgrp plugdev
```

### Issue: Not enough disk space

```bash
# Check space
df -h ~

# Clean dnf cache
sudo dnf clean all

# Remove old kernels (keep 2 latest)
sudo dnf remove --oldinstallonly --setopt installonly_limit=2 kernel

# Change pmbootstrap work directory to larger disk
pmbootstrap config work /path/to/larger/disk
```

### Issue: Android tools not detecting device

```bash
# Install android-udev-rules
sudo dnf install android-udev-rules

# Or manually add OnePlus 6 vendor ID
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0666", GROUP="plugdev"' | \
sudo tee /etc/udev/rules.d/51-android.rules

sudo udevadm control --reload-rules
```

### Issue: SELinux blocking operations

```bash
# Check SELinux status
getenforce

# Temporarily set to permissive for testing
sudo setenforce 0

# If that fixes it, create proper SELinux policy
# Or permanently set to permissive in /etc/selinux/config
```

### Issue: Slow builds

```bash
# Use ccache to speed up rebuilds
sudo dnf install -y ccache

# Configure pmbootstrap to use it
pmbootstrap config ccache_size 5G
```

## System Optimization for Builds

```bash
# Increase inotify watches (for large builds)
echo 'fs.inotify.max_user_watches=524288' | \
sudo tee -a /etc/sysctl.conf

# Apply immediately
sudo sysctl -p

# Increase open file limits
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
```

## Ready to Build!

Once all steps are complete:

```bash
cd ~/Projects/Marathon-Image

# Read pre-build checklist
cat docs/PRE_BUILD_CHECKLIST.md

# When ready, start build
./scripts/build-and-flash.sh enchilada
```

## Next Steps

After successful build:
1. Flash to device (follow script output)
2. Boot device
3. Configure network (via UART or USB networking)
4. SSH into device
5. Run validation: `./validate-system.sh`
6. Report results!

## Useful Commands Reference

```bash
# pmbootstrap
pmbootstrap status              # Show configuration
pmbootstrap log                 # View build logs
pmbootstrap chroot              # Enter build chroot
pmbootstrap zap -p              # Clean packages cache
pmbootstrap zap -a              # Clean everything
pmbootstrap shutdown            # Stop background processes

# Device
adb devices                     # List ADB devices
adb reboot bootloader           # Reboot to fastboot
fastboot devices                # List fastboot devices
fastboot reboot                 # Reboot to OS

# System
df -h ~/.local/var/pmbootstrap  # Check disk usage
du -sh ~/.local/var/pmbootstrap/cache_*  # Cache sizes
journalctl -xe                  # System logs
```

## Resources

- **Fedora Documentation:** https://docs.fedoraproject.org
- **pmbootstrap Wiki:** https://wiki.postmarketos.org/wiki/Pmbootstrap
- **Marathon OS Docs:** See `docs/` directory in this repo

---

**Setup complete!** You're ready to build Marathon OS on Fedora. 🚀


