# Development Notes

This document chronicles the development process and key discoveries made while adapting Marathon Shell to run on Raspberry Pi.

## Project Timeline

### Initial Setup
- **Goal**: Get Marathon Shell compiled and running on Raspberry Pi CM5
- **Challenges**: Missing Qt6 dependencies, CMake configuration issues
- **Solution**: Installed Qt6 from Raspberry Pi repositories, adjusted build flags for ARM

### First Boot Attempts
- **Issue**: Marathon Shell would crash immediately on launch
- **Root Cause**: Trying to use Wayland client mode (`-platform wayland`) when no Wayland compositor was available
- **Solution**: Use `eglfs` platform plugin for direct rendering

### The Immediate Re-Lock Bug

This was the most significant bug encountered and took extensive debugging to resolve.

#### Symptom
After successfully swiping up and entering the PIN, Marathon Shell would immediately lock again within 1-2 seconds.

#### Investigation Process

1. **Initial Hypothesis**: Race condition or spurious signal
   - Added 2-second guard in `SessionStore.lock()` → Still occurred after 2 seconds
   - Increased to 30-second guard → Still occurred after 30 seconds
   - **Conclusion**: Something was actively trying to re-lock the session

2. **Debug Logging**
   - Added `Logger.warn()` statements throughout `SessionManager.qml`
   - Discovered `_checkIdleState()` was being called and detecting immediate idle state

3. **Timestamp Analysis**
   ```
   Logs showed:
   CHECK: idleTime=-4398046511103ms, idleTimeout=3600000ms
   ```
   - Negative (or massive positive due to overflow) idle time!
   - This pointed to timestamp calculation issue

4. **Root Cause Discovery**
   - `lastActivityTime` was declared as `property int`
   - `Date.now()` returns a 64-bit millisecond timestamp (e.g., `1731398400000`)
   - QML `int` is 32-bit, causing integer overflow
   - Overflow resulted in incorrect `idleTime` calculation
   - System immediately thought it was idle and triggered lock

5. **The Fix**
   ```qml
   // Before:
   property int lastActivityTime: 0
   property int idleTime: 0
   
   // After:
   property double lastActivityTime: Date.now()
   property double idleTime: 0
   ```
   
   - Changed to `double` (64-bit floating point) to store full timestamp
   - Initialized `lastActivityTime` to `Date.now()` instead of 0
   - Added aggressive idle reset in `unlockSession()`
   - Added guard to prevent re-locking when already locked

#### Additional Fixes
- Modified `idleMonitor.running` to stop when `screenLocked` is true
- Added explicit `idleTime = 0` reset on unlock
- Added `idleMonitor.stop()/start()` cycle on unlock

#### Lessons Learned
- **Always use `double` for timestamps in QML**: `int` is only 32-bit
- **Initialize time values properly**: Don't start at 0, start at `Date.now()`
- **Add defensive checks**: Prevent redundant state transitions
- **Debug logging is essential**: Use `Logger.warn()` for important state changes

### Boot Configuration Challenges

#### Problem: Black Screen → Login Screen Loop

**Sequence of Events**:
1. Log in via LightDM
2. Brief black screen
3. Return to login screen

**Investigation**:

1. **First Attempt**: Assumed session file was incorrect
   - Verified `/usr/share/wayland-sessions/marathon.desktop` was correct
   - Still failed

2. **Second Attempt**: Checked LightDM configuration
   - Found `autologin-session=LXDE-pi-labwc` was overriding `user-session=marathon`
   - Changed to `autologin-session=marathon`
   - Still failed

3. **Third Attempt**: Examined session script
   - Discovered script was setting `WAYLAND_DISPLAY=wayland-0` at the beginning
   - Then checking if `WAYLAND_DISPLAY` was set to determine if running nested
   - Result: Always thought it was running nested!
   - **Fix**: Save original `WAYLAND_DISPLAY` before modifying, check original value

4. **Fourth Attempt**: Qt platform plugin errors
   - Logs showed: `Failed to create wl_display (No such file or directory)`
   - Marathon Shell was trying to connect to a Wayland compositor that didn't exist
   - **Root Cause**: The Wayland greeter (`pi-greeter-labwc`) was terminating before Marathon Shell started
   - Marathon Shell tried to use `-platform wayland` but had no parent compositor
   - **Fix**: Use X11-based greeter (`lightdm-gtk-greeter`) + explicitly use `eglfs`

5. **Fifth Attempt**: Permission errors
   - Using `eglfs` requires exclusive access to `/dev/dri/card0`
   - User needs to be in `video` and `render` groups
   - Binary needs `cap_sys_nice` capability for real-time priority
   - **Fix**: 
     ```bash
     sudo usermod -a -G video,render pi
     sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin
     ```

#### Final Working Configuration

**LightDM Config**:
```ini
[Seat:*]
user-session=marathon
autologin-user=pi
autologin-session=marathon
greeter-session=lightdm-gtk-greeter  # X11-based, not Wayland
```

**Session Script Logic**:
```bash
# Save ORIGINAL display variables (before modification)
ORIGINAL_WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
ORIGINAL_DISPLAY="$DISPLAY"

# Later, check ORIGINAL values to detect nested vs. primary
if [ -n "$ORIGINAL_WAYLAND_DISPLAY" ] || [ -n "$ORIGINAL_DISPLAY" ]; then
    # Running nested
    exec /usr/bin/marathon-shell-bin -platform wayland --fullscreen
else
    # Running as primary compositor
    exec /usr/bin/marathon-shell-bin -platform eglfs
fi
```

### Performance Optimization

#### Software Rendering (linuxfb)
- **Initial attempt**: Used `-platform linuxfb` for software rendering
- **Result**: Worked, but choppy and slow (15-20 FPS)
- **Why**: All rendering done in CPU, no GPU acceleration

#### Hardware Rendering (eglfs)
- **Final configuration**: Using `-platform eglfs` with proper permissions
- **Result**: Smooth 60 FPS, full GPU acceleration
- **Requirements**:
  - User in `video` and `render` groups
  - Exclusive DRM access (no other compositor running)
  - Proper EGL/OpenGL ES libraries

## Key Technical Insights

### Qt Platform Plugins

**eglfs**: 
- Direct rendering to framebuffer via EGL/KMS
- Exclusive access required
- Best performance
- Use for primary compositor

**wayland**:
- Runs as Wayland client
- Needs parent compositor
- Good for testing nested
- Slightly lower performance

**linuxfb**:
- Software rendering to framebuffer
- No GPU acceleration
- Slow but guaranteed to work
- Last resort fallback

### Wayland Compositor Nesting

**You cannot nest Wayland compositors easily!**

If LightDM's greeter is a Wayland compositor (like `pi-greeter-labwc`), and Marathon Shell is also a Wayland compositor, they conflict:
- Both want exclusive DRM access
- Both try to create the Wayland display socket
- One must be terminated before the other starts

**Solution**: Use X11-based greeter (`lightdm-gtk-greeter`), which doesn't conflict with Wayland compositor startup.

### Display Manager Session Files

**Wayland vs. X11 Sessions**:
- Wayland sessions: `/usr/share/wayland-sessions/*.desktop`
- X11 sessions: `/usr/share/xsessions/*.desktop`

LightDM looks in the appropriate directory based on the session type. Marathon Shell must be in `wayland-sessions` since it's a Wayland compositor.

### Session Timeout Values

**Current Configuration**:
- `idleTimeout`: 3600000ms (1 hour)
- `lockTimeout`: 3600000ms (1 additional hour)
- Total time to lock: 2 hours of inactivity

**Rationale**:
- Long enough for demos without interruption
- Short enough for security
- Can be adjusted per user preference

### QML Performance

**Best Practices Discovered**:
1. Use disk cache: `export QML_FORCE_DISK_CACHE=1`
2. Don't disable optimizer: `export QML_DISABLE_OPTIMIZER=0`
3. Use hardware acceleration: `-platform eglfs` not `linuxfb`
4. Cache compiled QML: Set `QT_QML_DISK_CACHE_PATH`

## Debugging Techniques Used

### 1. Incremental Guards
Added temporary guards (2s → 30s) to isolate timing issues and confirm something was actively triggering the bug.

### 2. Extensive Logging
Replaced `console.log` with `Logger.warn` for visibility. Added logs at every state transition to trace execution flow.

### 3. Timestamp Analysis
Printed actual timestamp values to identify integer overflow issue.

### 4. Process Monitoring
```bash
# Watch for process crashes
journalctl -u lightdm -f

# Check what platform plugin is being used
ps aux | grep marathon-shell

# Test startup script directly
/usr/local/bin/marathon-shell-session
```

### 5. Minimal Reproduction
Tested Marathon Shell in isolation (not through LightDM) to separate compositor issues from session management issues.

## Remaining Challenges

### 1. Remote Access
- **Challenge**: VNC/XRDP don't work with Wayland compositors by default
- **Potential Solution**: Integrate `wayvnc` for VNC support
- **Status**: Not yet implemented

### 2. Boot Time
- **Current**: ~15 seconds from power to UI
- **Goal**: < 10 seconds
- **Potential Optimizations**:
  - Parallel service startup
  - Faster QML loading
  - Pre-compiled QML cache

### 3. Multi-Display Support
- **Current**: Single display only
- **Challenge**: Qt eglfs multi-display configuration
- **Status**: Not tested

## Future Development Ideas

1. **Custom Boot Splash**: Replace Raspberry Pi rainbow screen with Marathon logo
2. **Hardware Video Acceleration**: Integrate V4L2 for video playback
3. **Power Management**: Suspend/resume support via systemd-logind
4. **Touch Calibration UI**: Built-in touch screen calibration tool
5. **OTA Updates**: System for updating Marathon Shell remotely
6. **Custom App Store**: Repository of Marathon-optimized apps

## Contributing

If you're working on this project:

1. **Test thoroughly**: Always test on actual hardware before committing
2. **Document changes**: Update this file with discoveries and solutions
3. **Preserve backups**: Session files, configs, etc. should have backup copies
4. **Use version tags**: Tag releases for stability tracking

## References

- [Marathon Shell GitHub](https://github.com/MarathonOS/marathon-shell)
- [Qt QPA Documentation](https://doc.qt.io/qt-6/qpa.html)
- [Wayland Protocol Specs](https://wayland.freedesktop.org/docs/html/)
- [LightDM Configuration](https://wiki.archlinux.org/title/LightDM)
- [Raspberry Pi DRM/KMS](https://www.raspberrypi.com/documentation/computers/configuration.html#drm-kms)

---

*Last updated: 2025-11-12*

