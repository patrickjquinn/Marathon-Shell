# Contributing to Marathon OS

Thank you for your interest in contributing to Marathon OS! This guide will help you get started.

## Project Vision

Marathon OS is a BlackBerry 10-inspired mobile Linux distribution that prioritizes:
- **Responsiveness:** Sub-16ms touch latency, instant feel
- **Battery life:** Days-long standby on mobile hardware
- **Security:** Landlock LSM, seccomp sandboxing, Wayland-only
- **Openness:** 100% free software, no proprietary blobs required (where possible)

## Ways to Contribute

### 1. Device Support
Add support for new ARM64 mobile devices:
- Create device configuration in `devices/<codename>/`
- Test boot, display, touch, WiFi, modem
- Document hardware status
- Submit PR with working configuration

**Highly wanted devices:**
- OnePlus 6T (fajita) - nearly identical to OnePlus 6
- Xiaomi Poco F1 (beryllium) - same SDM845 SoC
- OnePlus 7/7 Pro - SDM855, needs new SoC fragment
- Raspberry Pi 4/5 - generic ARM64 testing platform

### 2. Performance Tuning
- Device-specific power profiles
- GPU-specific optimizations
- Alternative I/O schedulers for specific flash controllers
- Memory management improvements

### 3. Documentation
- Translate docs to other languages
- Add troubleshooting scenarios
- Create video guides
- Improve existing documentation clarity

### 4. Testing
- Test on different devices
- Report boot issues, hardware compatibility
- Validate performance metrics
- Test edge cases (modem, suspend/resume, etc.)

### 5. Integration
- App ecosystem development
- System services integration
- Hardware enablement (cameras, sensors)

## Development Workflow

### Setting Up

1. **Fork the repository:**
   ```bash
   # On GitHub, click "Fork"
   git clone https://github.com/YOUR_USERNAME/Marathon-Image.git
   cd Marathon-Image
   ```

2. **Add upstream remote:**
   ```bash
   git remote add upstream https://github.com/patrickjquinn/Marathon-Image.git
   git fetch upstream
   ```

3. **Create a branch:**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b device/device-codename
   ```

### Making Changes

1. **Follow the structure:**
   - Device configs: `devices/<codename>/device.conf`
   - SoC configs: `devices/<soc>/kernel-config.fragment`
   - System configs: `configs/`
   - Documentation: `docs/`

2. **Test your changes:**
   ```bash
   # Build for your device
   ./scripts/build-and-flash.sh <device>
   
   # Validate on device
   ./scripts/validate-system.sh
   ```

3. **Document your work:**
   - Update relevant docs in `docs/`
   - Add comments to config files
   - Update device support matrix in `docs/DEVICE_SUPPORT.md`

### Submitting Changes

1. **Commit your work:**
   ```bash
   git add .
   git commit -m "device: add support for Device Name"
   # or
   git commit -m "docs: improve kernel config explanations"
   ```

2. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

3. **Create Pull Request:**
   - Go to GitHub and create PR
   - Fill in the PR template
   - Link to any related issues

## Commit Message Format

Use conventional commit style:

```
type(scope): brief description

Longer description if needed.

- Additional details
- Can be in bullet points

Closes #123
```

**Types:**
- `device:` - New device support or fixes
- `config:` - System configuration changes
- `kernel:` - Kernel config modifications
- `docs:` - Documentation updates
- `scripts:` - Build/helper script changes
- `fix:` - Bug fixes
- `perf:` - Performance improvements
- `refactor:` - Code restructuring

**Examples:**
```
device: add support for OnePlus 6T (fajita)

Adds device configuration for OnePlus 6T which shares SDM845
SoC with OnePlus 6. Tested boot, display, touch, and WiFi.

- Reuses sdm845/kernel-config.fragment
- Minimal changes from enchilada config
- All core features working

Closes #45
```

```
perf: optimize zram compression for ARM64

Switched from zstd to lz4 for faster compression/decompression
on ARM64 devices with limited CPU power.

Benchmarks show 2x faster swapping with only 10% worse compression ratio.
```

## Code Style

### Shell Scripts
- Use `#!/bin/bash` shebang
- Use `set -e` for error handling
- Add comments for complex logic
- Use meaningful variable names in CAPS for env vars

### Configuration Files
- Include comments explaining each option
- Group related options together
- Reference documentation links where helpful

### Documentation
- Use Markdown
- Include code examples
- Keep line length reasonable (~80-100 chars)
- Use proper headings hierarchy

## Testing Requirements

### For Device Support PRs
Must test and document status of:
- [ ] Kernel boots to shell
- [ ] Display works (framebuffer or DRM)
- [ ] Touch input responsive
- [ ] WiFi connects
- [ ] GPU acceleration (glmark2-wayland)
- [ ] Suspend/resume (if supported)
- [ ] Modem (if phone device)
- [ ] Audio output
- [ ] Battery reporting

### For Performance Tuning PRs
- [ ] Provide before/after benchmarks
- [ ] Test on at least one device
- [ ] Document any trade-offs
- [ ] Explain rationale for changes

### For Kernel Config PRs
- [ ] Explain why option is needed
- [ ] Verify kernel still builds
- [ ] Test boot on reference device
- [ ] Document any size/performance impact

## Device Support Checklist

When adding a new device:

1. **Create device directory:**
   ```bash
   mkdir -p devices/<codename>
   ```

2. **Create `device.conf`:**
   ```bash
   cp devices/enchilada/device.conf devices/<codename>/
   # Edit with device-specific values
   ```

3. **Test build:**
   ```bash
   ./scripts/build-and-flash.sh <codename>
   ```

4. **Flash and validate:**
   ```bash
   # Flash to device
   # Boot and test
   ./scripts/validate-system.sh
   ```

5. **Document in PR:**
   - Hardware specs (CPU, RAM, storage)
   - What works / doesn't work
   - Known issues
   - Photos/video of working device (optional but awesome)

6. **Update `docs/DEVICE_SUPPORT.md`:**
   - Add device to support matrix
   - Document any quirks

## Review Process

1. **Automated checks:**
   - Basic linting
   - File structure validation

2. **Manual review:**
   - Maintainer reviews code
   - Tests on available hardware
   - Provides feedback

3. **Approval and merge:**
   - Once approved, PR is merged
   - Your contribution is credited

## Community Guidelines

- **Be respectful:** Treat everyone with respect
- **Be patient:** Maintainers are volunteers
- **Be helpful:** Help other contributors
- **Be constructive:** Provide actionable feedback
- **Be collaborative:** Work together to improve the project

## Questions or Help?

- **GitHub Issues:** Report bugs or request features
- **GitHub Discussions:** Ask questions, share ideas
- **Pull Requests:** Submit your contributions
- **Email:** patrick@jquinn.com (for sensitive issues only)

## License

By contributing, you agree that your contributions will be licensed under the MIT License (for configuration/build files) or GPL-3.0+ (for code that links with Marathon Shell).

See [LICENSE](LICENSE) for details.

---

**Thank you for contributing to Marathon OS!** 🚀

Together, we're building the mobile Linux experience we've always wanted.


