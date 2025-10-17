# Marathon OS Build Instructions

Complete step-by-step instructions to build Marathon OS from scratch for OnePlus 6 (enchilada).

## Prerequisites

### System Requirements
- **OS**: Fedora Linux (tested on Fedora 42)
- **RAM**: 8GB+ recommended
- **Storage**: 20GB+ free space
- **Internet**: Required for package downloads
- **Root Access**: Required for pmbootstrap operations

### Required Packages
```bash
sudo dnf install -y pmbootstrap android-tools git
```

## Quick Build (Recommended)

The easiest way to build Marathon OS is using the automated build script:

```bash
# Clone repository
git clone https://github.com/patrickjquinn/Marathon-Image.git
cd Marathon-Image

# Initialize pmbootstrap (one-time setup)
pmbootstrap init
# Choose: edge, oneplus/enchilada, systemd, none

# Build everything automatically
./scripts/build-and-flash.sh enchilada
```

This script handles all the complex steps below automatically.

## Manual Build Process

If you prefer to build manually or need to troubleshoot:

### Step 1: Initialize pmbootstrap

```bash
pmbootstrap init
```

**Configuration Options:**
- **Channel**: `edge` (latest)
- **Device**: `oneplus-enchilada`
- **UI**: `none`
- **Extra packages**: (leave empty)
- **Hostname**: `marathon-phone`
- **User**: `user`

### Step 2: Build All Packages

```bash
# Build custom kernel (Linux 6.17.3 with PREEMPT_RT)
pmbootstrap build linux-marathon

# Build system optimizations
pmbootstrap build marathon-base-config

# Build Marathon Shell (Qt6/QML Wayland compositor)
pmbootstrap build marathon-shell
```

### Step 3: Install Complete System

```bash
# Install everything with Marathon Shell
pmbootstrap install --add marathon-shell
```

### Step 4: Generate Kernel Modules

```bash
# Generate kernel module dependencies
pmbootstrap chroot -r -- /bin/sh -c "depmod -a 6.17.3"
```

### Step 5: Export Images

```bash
# Create boot and rootfs images
pmbootstrap export
```

### Step 6: Flash to Device

```bash
# Boot OnePlus 6 into fastboot mode (Power + Vol Down)
# Flash images
fastboot flash boot out/enchilada/boot.img
fastboot flash userdata out/enchilada/oneplus-enchilada-root.img
fastboot reboot
```

## Expected Results

After flashing, the device will:

### Boot Process
1. **Kernel**: Custom Linux 6.17.3 with PREEMPT_RT patches
2. **Initramfs**: postmarketOS initramfs with device support  
3. **Rootfs**: Marathon OS with all optimizations
4. **Display Manager**: greetd with Marathon Shell autologin
5. **Shell**: Marathon Shell Wayland compositor with all apps

### Available Features
- **Marathon Shell**: BlackBerry 10-inspired Qt6/QML interface
- **System Apps**: 11 pre-installed apps (browser, settings, clock, phone, messages, notes, calendar, camera, gallery, music, maps)
- **Real-time Performance**: Optimized kernel and systemd priorities
- **GPU Acceleration**: Mesa/Freedreno for Adreno 630
- **Mobile Optimizations**: zram, schedutil, kyber, F2FS support

### Performance Characteristics
- **Boot Time**: ~30-45 seconds to Marathon Shell
- **Memory Usage**: ~1.5GB RAM with Marathon Shell running
- **Battery Life**: Optimized for mobile use with deep sleep
- **Responsiveness**: Real-time kernel provides smooth UI

## Troubleshooting

### Common Issues

**1. Build Failures**
```bash
# Check build logs
pmbootstrap log | tail -100

# Clean and retry
pmbootstrap zap -p
pmbootstrap build <package-name> --force
```

**2. Device Not Detected**
```bash
# Check fastboot connection
fastboot devices
# Install android-tools if missing
sudo dnf install -y android-tools
```

**3. Marathon Shell Not Starting**
```bash
# Check if Marathon Shell is installed
pmbootstrap chroot -r -- ls -la /usr/bin/marathon-shell

# Check systemd status
pmbootstrap chroot -r -- systemctl --user status marathon-shell
```

### Verification Commands

**Check Build Output:**
```bash
# Check generated images
ls -la out/enchilada/
# Should show: boot.img, oneplus-enchilada-root.img, vmlinuz, initramfs
```

**Check Marathon Shell Installation:**
```bash
# Verify Marathon Shell is installed
pmbootstrap chroot -r -- ls -la /usr/bin/marathon-shell
pmbootstrap chroot -r -- ls -la /usr/share/marathon-apps/
```

## Build Time

**Total Build Time**: 30-60 minutes (depending on hardware)
- Kernel build: ~20-30 minutes
- Base config: ~2-5 minutes  
- Marathon Shell: ~5-10 minutes
- System installation: ~5-10 minutes
- Image creation: ~5-10 minutes

## Current Status

**✅ Build System**: Fully functional and tested
**✅ Marathon Shell**: Latest version with all upstream fixes
**✅ System Apps**: All 11 apps properly integrated
**✅ Kernel**: Custom 6.17.3 with PREEMPT_RT patches
**✅ Optimizations**: All performance tuning applied

## Next Steps

After successful build and flash:

1. **First Boot**: Device boots directly to Marathon Shell
2. **App Usage**: All 11 system apps ready to use
3. **Development**: Use Marathon Shell's app development system
4. **Customization**: Modify system configs in `configs/` directory

---

**Last Updated**: October 17, 2025
**Marathon OS Version**: Latest with all fixes applied
**Target Device**: OnePlus 6 (enchilada)
**Kernel Version**: 6.17.3 with PREEMPT_RT
**Status**: ✅ Ready for production use
