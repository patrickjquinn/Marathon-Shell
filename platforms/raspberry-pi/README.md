# Marathon Shell on Raspberry Pi

This directory contains configuration and installation scripts for running Marathon Shell on Raspberry Pi devices, specifically tested on the Hackberry Pi (Raspberry Pi CM5).

## Quick Start

```bash
cd platforms/raspberry-pi
sudo ./scripts/install.sh
```

Then reboot and Marathon Shell should start automatically.

## What's Included

- **config/**: System configuration files
  - `lightdm.conf` - LightDM display manager configuration
  - `marathon.desktop` - Wayland session definition
  - `marathon-shell-session` - Session startup script

- **scripts/**: Installation and management scripts
  - `install.sh` - Automated installation script
  - `uninstall.sh` - Removes Marathon Shell configuration

- **docs/**: Platform-specific documentation
  - `ARCHITECTURE.md` - How Marathon Shell integrates with the system
  - `BOOT_CONFIGURATION.md` - Boot process details
  - `DEVELOPMENT.md` - Development tips for Raspberry Pi
  - `TROUBLESHOOTING.md` - Common issues and solutions

## Hardware Requirements

- Raspberry Pi 4 or newer (tested on CM5)
- At least 2GB RAM recommended
- Display with HDMI/DSI connection
- GPU with OpenGL ES 2.0+ support

## Software Requirements

- Raspberry Pi OS (64-bit recommended)
- Qt 6.5 or newer
- LightDM display manager
- Wayland support

## Key Features

- **Direct GPU Rendering**: Uses Qt's `eglfs` platform for hardware-accelerated graphics
- **Auto-login Support**: Automatically starts Marathon Shell on boot
- **Wayland Native**: Runs as a standalone Wayland compositor
- **Touch Optimized**: Designed for mobile/touch interfaces

## Performance Notes

The Raspberry Pi CM5's GPU is very capable, but for best performance:
- Use 64-bit OS
- Ensure GPU memory is allocated (at least 128MB in `config.txt`)
- Keep background services minimal
- Consider disabling desktop effects if running other apps

## Getting Help

Check the troubleshooting guide in `docs/TROUBLESHOOTING.md` first. For issues specific to Raspberry Pi, please open an issue with the "raspberry-pi" label.

## Testing Status

| Device | Status | Notes |
|--------|--------|-------|
| Hackberry Pi (CM5) | ✅ Tested | Fully working with GPU acceleration |
| Raspberry Pi 5 | 🟡 Should work | Not tested but compatible |
| Raspberry Pi 4 | 🟡 Should work | May need memory adjustments |

## Contributing

Improvements to Raspberry Pi support are welcome! Please test thoroughly on actual hardware before submitting PRs.

