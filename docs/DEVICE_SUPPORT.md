# Marathon OS Device Support

Marathon OS is designed to run on any ARM64 device with mainline Linux support. This document explains how to adapt it for different devices.

## Architecture

Marathon OS separates **device-agnostic** components from **device-specific** ones:

### Device-Agnostic (Universal)
- `marathon-base-config` - System tuning (works on all ARM64)
- `marathon-shell` - Compositor (works on any Wayland)
- Base kernel config - PREEMPT_RT, performance, security options

### Device-Specific
- Kernel device trees
- Device-specific kernel options (GPU, modem, display drivers)
- Bootloader requirements
- Partition layout

## Current Device Support

| Device | SoC | Status | Maintainer |
|--------|-----|--------|------------|
| OnePlus 6 (enchilada) | SDM845 | Reference | @patrickjquinn |
| Generic ARM64 | Any | Experimental | - |

## Adding a New Device

### 1. Create Device Directory

```bash
mkdir -p devices/<device-codename>
```

### 2. Create Device Configuration

`devices/<device-codename>/device.conf`:

```bash
# Device metadata
DEVICE_VENDOR="oneplus"
DEVICE_CODENAME="enchilada"
DEVICE_NAME="OnePlus 6"
DEVICE_SOC="sdm845"
DEVICE_ARCH="aarch64"

# Kernel
KERNEL_CMDLINE="console=ttyMSM0,115200n8 mem_sleep_default=deep"
KERNEL_DTB="qcom/sdm845-oneplus-enchilada.dtb"

# Bootloader
BOOTLOADER_TYPE="android"  # or "u-boot", "grub"
FLASH_METHOD="fastboot"    # or "dd", "jumpdrive"

# Partitions (Android devices)
BOOT_PARTITION="boot"
SYSTEM_PARTITION="userdata"
```

### 3. Create Kernel Config Fragment

`devices/<device-codename>/kernel-config.fragment`:

```
# Device-specific kernel options
CONFIG_ARCH_QCOM=y
CONFIG_QCOM_SMD_RPM=y
CONFIG_QCOM_SMEM=y

# GPU (Adreno)
CONFIG_DRM_MSM=y
CONFIG_DRM_MSM_GPU=y

# Display
CONFIG_DRM_MSM_DSI=y
CONFIG_DRM_MSM_DSI_PLL=y

# Modem
CONFIG_MHI_BUS=y
CONFIG_QRTR=y

# Audio
CONFIG_SND_SOC_QCOM=y
CONFIG_SND_SOC_WCD9335=y
```

### 4. Build for Your Device

```bash
./scripts/build-and-flash.sh --device <device-codename>
```

## Device Profiles

### Generic ARM64

For SBCs or devices with U-Boot:

```bash
# devices/generic/device.conf
DEVICE_VENDOR="generic"
DEVICE_CODENAME="arm64"
DEVICE_NAME="Generic ARM64"
DEVICE_ARCH="aarch64"
BOOTLOADER_TYPE="u-boot"
FLASH_METHOD="dd"
```

Good for:
- Raspberry Pi 4/5 (with U-Boot)
- Pine64 devices
- Generic ARM64 VMs
- Development boards

### SDM845 Devices (OnePlus 6, Poco F1, etc.)

Common Snapdragon 845 config works for:
- OnePlus 6/6T (enchilada/fajita)
- Xiaomi Poco F1 (beryllium)
- Shift6mq

### SDM855 Devices

Newer Snapdragon 855/855+ devices:
- OnePlus 7/7 Pro
- Xiaomi Mi 9
- Similar kernel requirements, better GPU

## Kernel Packaging Strategy

### Option 1: Per-Device Kernels (Current)

```
packages/
├── linux-marathon-enchilada/
├── linux-marathon-beryllium/
└── linux-marathon-fajita/
```

**Pros:** Device-optimized, minimal bloat
**Cons:** Duplication, maintenance overhead

### Option 2: Unified Kernel with Configs

```
packages/
└── linux-marathon/
    ├── APKBUILD
    ├── config-base.aarch64         # Universal Marathon config
    ├── config-sdm845.fragment      # SDM845 family
    ├── config-sdm855.fragment      # SDM855 family
    └── config-generic.fragment     # Generic ARM64
```

**Pros:** Shared maintenance, easier updates
**Cons:** Larger kernel, longer build time

### Option 3: Modular (Recommended)

```
packages/
├── linux-marathon-base/           # Base kernel + Marathon optimizations
│   └── config-marathon.aarch64    # PREEMPT_RT, perf, security
└── devices/<device>/
    └── linux-marathon-<device>/   # Device-specific overlay
        └── config-<device>.fragment
```

## Porting Checklist

- [ ] Device has mainline Linux support (check wiki.postmarketos.org)
- [ ] Kernel 6.17+ works on device
- [ ] Wayland-capable GPU drivers available (mesa, freedreno, panfrost, etc.)
- [ ] Device tree exists in mainline kernel
- [ ] Bootloader is unlockable
- [ ] fastboot/U-Boot/GRUB available
- [ ] Display, touch, USB working in mainline
- [ ] Optional: Modem, WiFi, Bluetooth, cameras

## Minimal Requirements

For Marathon OS to be usable:

**Must Have:**
- ARM64 CPU (ARMv8+)
- 2GB+ RAM (3GB+ recommended)
- OpenGL ES 2.0+ GPU (for Qt/Wayland)
- Touch input or keyboard/mouse
- Display output

**Should Have:**
- WiFi or Ethernet
- 16GB+ storage
- Suspend/resume support
- Runtime PM for battery devices

**Nice to Have:**
- Modem (for phone calls)
- GPS
- Cameras
- Sensors (accel, gyro, proximity)

## Example: Porting to Raspberry Pi 4

1. **Create device profile:**
```bash
# devices/rpi4/device.conf
DEVICE_VENDOR="raspberrypi"
DEVICE_CODENAME="rpi4"
DEVICE_NAME="Raspberry Pi 4"
DEVICE_ARCH="aarch64"
BOOTLOADER_TYPE="u-boot"
FLASH_METHOD="dd"
KERNEL_DTB="broadcom/bcm2711-rpi-4-b.dtb"
```

2. **Kernel config fragment:**
```
# devices/rpi4/kernel-config.fragment
CONFIG_ARCH_BCM2835=y
CONFIG_DRM_V3D=y
CONFIG_DRM_VC4=y
CONFIG_BCM2835_THERMAL=y
```

3. **Build:**
```bash
./scripts/build-and-flash.sh --device rpi4
dd if=out/marathon-rpi4.img of=/dev/sdX bs=4M
```

## SoC Family Support Matrix

| SoC Family | Example Devices | Mainline Support | Recommended |
|------------|----------------|------------------|-------------|
| Snapdragon 845 | OnePlus 6, Poco F1 | ✅ Excellent | ✅ Yes |
| Snapdragon 855/+ | OnePlus 7 Pro | ✅ Good | ✅ Yes |
| Snapdragon 865 | OnePlus 8 | ⚠️ Partial | ⚠️ WIP |
| Exynos 9820+ | Some Samsungs | ⚠️ Limited | ❌ Not yet |
| MediaTek Dimensity | Various | ⚠️ Varies | ⚠️ Case by case |
| Rockchip RK33xx | Pine64, SBCs | ✅ Excellent | ✅ Yes |
| Broadcom BCM2711 | Raspberry Pi 4 | ✅ Good | ✅ Yes |
| Allwinner H6/A64 | Pine64 phones | ✅ Good | ✅ Yes |

## Device-Specific Notes

### Android Devices (Qualcomm/MediaTek)

- Bootloader unlock required
- Use fastboot for flashing
- May need vendor firmware blobs
- Check postmarketOS wiki for device status

### Single-Board Computers

- Usually easier to port
- Better mainline support
- May need custom U-Boot
- Can use SD card for easy testing

### Tablets

- Same as phones, often easier (less modem complexity)
- Check touchscreen drivers

## Testing Strategy

1. **Boot test:** Does kernel boot to shell?
2. **Display:** Does framebuffer/DRM work?
3. **Input:** Touch/keyboard responsive?
4. **GPU:** Can run glmark2-wayland?
5. **Network:** WiFi or Ethernet working?
6. **Performance:** RT priorities effective?
7. **Power:** Suspend/resume working?

## Contributing Device Support

To add a device to Marathon OS:

1. Fork repo, create branch: `device/<codename>`
2. Add `devices/<codename>/` with config
3. Test boot, display, input, GPU
4. Document hardware status in `devices/<codename>/README.md`
5. Submit PR with validation screenshots/logs

## Resources

- **postmarketOS Wiki:** https://wiki.postmarketos.org/wiki/Devices
- **Mainline kernel status:** https://linux-sunxi.org/Linux_mainlining_effort
- **Device trees:** https://github.com/torvalds/linux/tree/master/arch/arm64/boot/dts
- **Mesa driver support:** https://docs.mesa3d.org/drivers.html

---

**Goal:** Make Marathon OS run on any ARM64 device with decent mainline support!


