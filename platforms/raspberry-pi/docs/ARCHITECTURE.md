# Marathon Shell on Hackberry Pi - Technical Architecture

This document provides detailed technical information about how Marathon Shell runs on Raspberry Pi as a primary desktop environment.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Hardware Layer                          │
│  Raspberry Pi CM5 (BCM2712 SoC, ARM Cortex-A76)             │
│  GPU: VideoCore VII (OpenGL ES 3.1, Vulkan 1.3)             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Linux Kernel (6.6+)                       │
│  - DRM/KMS (Direct Rendering Manager)                       │
│  - Wayland Protocol Support                                 │
│  - Input Event Subsystem (evdev)                            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  systemd + LightDM                          │
│  - Display Manager (LightDM)                                │
│  - Session Management                                       │
│  - User Login & Autologin                                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              Marathon Shell (Qt6 + QML)                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Wayland Compositor (Marathon)                 │  │
│  │  - Window Management                                  │  │
│  │  - Surface Rendering                                  │  │
│  │  - Input Handling (Touch, Mouse, Keyboard)            │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │          Qt6 QPA Plugin (eglfs)                       │  │
│  │  - Direct EGL/KMS Rendering                           │  │
│  │  - No X11/Wayland Client Dependency                   │  │
│  │  - Full GPU Acceleration                              │  │
│  └───────────────────────────────────────────────────────┘  │
│                          ↓                                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Marathon OS Components                        │  │
│  │  - Shell UI (QML)                                     │  │
│  │  - App Launcher                                       │  │
│  │  - Notification System                                │  │
│  │  - Settings Manager                                   │  │
│  │  - Session Manager                                    │  │
│  │  - Lock Screen                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Wayland Clients                           │
│  (Apps running under Marathon Shell's compositor)           │
│  - GTK4/Wayland Apps                                        │
│  - Qt6/Wayland Apps                                         │
│  - Native Marathon Apps                                     │
└─────────────────────────────────────────────────────────────┘
```

## Boot Sequence

### 1. Hardware Initialization
```
Power On → Bootloader (Raspberry Pi firmware)
         → Loads Linux kernel from /boot
         → Kernel initializes hardware (GPU, DRM, input devices)
```

### 2. systemd Startup
```
systemd → Starts system services
        → Starts LightDM display manager (lightdm.service)
```

### 3. LightDM Session Launch
```
LightDM → Reads /etc/lightdm/lightdm.conf
        → Checks autologin-session=marathon
        → Skips greeter (or shows lightdm-gtk-greeter if manual login)
        → Looks for session in /usr/share/wayland-sessions/
        → Finds marathon.desktop
        → Executes: /usr/local/bin/marathon-shell-session
```

### 4. Marathon Shell Startup Script
```
marathon-shell-session
  ↓
1. Set environment variables:
   - XDG_SESSION_TYPE=wayland
   - XDG_SESSION_DESKTOP=marathon
   - XDG_CURRENT_DESKTOP=marathon
   - QT_* variables for Qt/QML configuration
   - Wayland socket path
  ↓
2. Start D-Bus session (if needed)
  ↓
3. Detect if running as primary compositor or nested:
   - Primary: No WAYLAND_DISPLAY or DISPLAY set
   - Nested: WAYLAND_DISPLAY or DISPLAY is set
  ↓
4. Launch Marathon Shell:
   - Primary: exec /usr/bin/marathon-shell-bin -platform eglfs
   - Nested: exec /usr/bin/marathon-shell-bin -platform wayland --fullscreen
```

### 5. Marathon Shell Initialization
```
Marathon Shell Binary
  ↓
1. Qt Platform Plugin Selection:
   - eglfs: Direct DRM/KMS access
   - Opens /dev/dri/card0
   - Initializes EGL context
   - Sets up OpenGL ES renderer
  ↓
2. Wayland Compositor Initialization:
   - Creates Wayland display (wayland-0 socket)
   - Registers compositor interfaces
   - Starts listening for client connections
  ↓
3. QML Engine Startup:
   - Loads MarathonShell.qml
   - Initializes UI components
   - Starts session manager
   - Shows lock screen
  ↓
4. Ready for User Interaction
```

## Graphics Rendering Pipeline

### eglfs Mode (Primary Compositor)

```
Marathon Shell QML UI
        ↓
Qt Quick Scenegraph (OpenGL ES)
        ↓
EGL (Embedded OpenGL Interface)
        ↓
Mesa DRI Driver (v3d for RPi)
        ↓
DRM/KMS (Direct Rendering Manager)
        ↓
VideoCore VII GPU
        ↓
Display Hardware (HDMI/DSI)
```

**Key Characteristics**:
- **Zero-Copy Rendering**: GPU buffers mapped directly to screen
- **VSync**: Synchronized with display refresh rate (60Hz typically)
- **GPU Acceleration**: All rendering operations hardware-accelerated
- **Low Latency**: Direct path from app to display (< 16ms)

## Session Management Architecture

### Components

#### 1. SessionManager.qml (Singleton)
**Location**: `shell/qml/services/SessionManager.qml`

**Responsibilities**:
- Tracks session state (active, idle, locked)
- Monitors user activity via timestamps
- Implements idle detection timer
- Locks/unlocks session
- Controls screen power state

**Key Properties**:
```qml
property double lastActivityTime: Date.now()  // 64-bit timestamp
property double idleTime: 0                    // Milliseconds since last activity
property int idleTimeout: 3600000              // 1 hour (milliseconds)
property int lockTimeout: 3600000              // Additional time before lock
property bool screenLocked: false              // Current lock state
property string sessionState: "active"         // active, idle, locked
```

**Idle Detection Algorithm**:
```javascript
Timer {
    interval: 5000  // Check every 5 seconds
    running: idleDetectionEnabled && sessionActive && !screenLocked
    onTriggered: {
        var now = Date.now()
        idleTime = now - lastActivityTime
        
        if (sessionState === "locked") {
            return  // Don't process if already locked
        }
        
        if (idleTime >= idleTimeout) {
            // Transition to idle, then lock after lockTimeout
            sessionState = "idle"
            if (idleTime >= (idleTimeout + lockTimeout)) {
                lockSession()
            }
        }
    }
}
```

#### 2. SessionStore.qml (Singleton)
**Location**: `shell/qml/stores/SessionStore.qml`

**Responsibilities**:
- High-level session state management
- Interfaces between UI and SessionManager
- Validates session timeouts
- Manages unlock timestamps

**Key Functions**:
```qml
function unlock() {
    SessionManager.unlockSession()
    isLocked = false
    lastUnlockTime = Date.now()
}

function lock() {
    SessionManager.lockSession()
    isLocked = true
}

function checkSession() {
    // Validate if session is still active within timeout window
    if (lastUnlockTime) {
        var elapsed = Date.now() - lastUnlockTime
        return elapsed <= sessionTimeout
    }
    return false
}
```

#### 3. MarathonLockScreen.qml
**Location**: `shell/qml/components/MarathonLockScreen.qml`

**Responsibilities**:
- Renders lock screen UI
- Handles swipe-to-unlock gesture
- Manages screen idle timer (screen dimming/off)
- Emits unlock signals

**Swipe Detection**:
```qml
MouseArea {
    property real startY: 0
    property real currentY: 0
    
    onPressed: (mouse) => {
        startY = mouse.y
    }
    
    onPositionChanged: (mouse) => {
        currentY = mouse.y
        var delta = startY - currentY
        
        if (delta > 100) {  // Threshold for unlock
            unlockRequested()
        }
    }
}
```

## Display Manager Integration

### LightDM Configuration

**File**: `/etc/lightdm/lightdm.conf`

Key settings:
```ini
[Seat:*]
user-session=marathon              # Default session for login
autologin-user=pi                  # Auto-login user
autologin-session=marathon         # Session to use for autologin
greeter-session=lightdm-gtk-greeter # X11-based greeter (avoids Wayland nesting)
```

### Session Definition

**File**: `/usr/share/wayland-sessions/marathon.desktop`

```ini
[Desktop Entry]
Name=Marathon Shell
Comment=Marathon OS Mobile Interface
Exec=/usr/local/bin/marathon-shell-session
Type=Application
```

**Why Wayland Sessions?**
- Located in `/usr/share/wayland-sessions/` (not `xsessions`)
- Indicates to LightDM that this is a Wayland compositor
- Prevents X11-specific initialization

## Qt Platform Abstraction (QPA)

### eglfs Platform Plugin

**Purpose**: Allows Qt applications to render directly to the framebuffer using EGL/OpenGL ES without an X11 or Wayland server.

**When Used**: Marathon Shell as primary compositor

**Configuration**:
```bash
-platform eglfs  # Command-line argument to Qt application
```

**Internal Operation**:
1. Opens `/dev/dri/card0` (DRM device)
2. Queries available displays via KMS (Kernel Mode Setting)
3. Creates an EGL context for OpenGL rendering
4. Sets up a render loop synchronized with VSync
5. Presents buffers directly to the display controller

**Advantages**:
- ✅ Lowest latency
- ✅ Highest performance
- ✅ Direct GPU access
- ✅ No intermediary display server

**Limitations**:
- ❌ Only one application can use eglfs at a time (exclusive DRM access)
- ❌ No window management (fullscreen only)
- ❌ Cannot run alongside X11 or another Wayland compositor

### wayland Platform Plugin

**Purpose**: Allows Qt applications to run as Wayland clients within another compositor.

**When Used**: Marathon Shell nested within another desktop (for testing)

**Configuration**:
```bash
-platform wayland --fullscreen
```

**Internal Operation**:
1. Connects to parent Wayland compositor via `$WAYLAND_DISPLAY` socket
2. Creates a Wayland surface for the window
3. Renders to that surface using OpenGL
4. Receives input events from parent compositor

## Wayland Compositor Implementation

Marathon Shell implements a Wayland compositor using Qt Wayland Compositor APIs.

### Key Interfaces Implemented

1. **wl_compositor**: Core window surface creation
2. **wl_shell**: Basic window management (deprecated but still used)
3. **xdg_shell**: Modern window management protocol
4. **wl_seat**: Input device management (keyboard, pointer, touch)
5. **wl_output**: Display configuration

### Window Management

```qml
WaylandCompositor {
    // Accept client connections
    onCreatedChanged: {
        if (created) {
            console.log("Compositor ready")
        }
    }
    
    // Handle new surfaces
    onSurfaceCreated: (surface) => {
        // Create shell surface
        var shellSurface = shellSurfaceComponent.createObject(surface)
        surfaces.append(shellSurface)
    }
}
```

## Input Handling

### Touch Events
```
Touch Hardware → evdev (/dev/input/eventX)
              → libinput
              → Qt Input System
              → QML MouseArea/TapHandler
              → App Logic
```

### Gesture Recognition
Marathon Shell implements custom gesture detection:
- **Swipe Up**: Unlock screen / Show app drawer
- **Swipe Down**: Show notifications
- **Swipe Left/Right**: Switch between apps
- **Edge Gestures**: System actions

## Performance Optimizations

### 1. QML Disk Cache
```bash
export QT_QML_DISK_CACHE_PATH="~/.cache/marathon-qml"
export QML_FORCE_DISK_CACHE=1
```
- Caches compiled QML bytecode
- Reduces startup time by ~40%
- Reduces CPU usage during runtime

### 2. GPU Memory Allocation
```bash
gpu_mem=256  # In /boot/firmware/config.txt
```
- Reserves 256MB RAM for GPU
- Improves texture upload performance
- Enables larger framebuffer allocations

### 3. Compositor Optimizations
- **Direct Rendering**: Clients render directly to compositor surfaces
- **Zero-Copy Textures**: DMA-BUF for buffer sharing
- **VSync Synchronization**: Prevents tearing

## Security Considerations

### 1. DRM Access
Marathon Shell requires access to `/dev/dri/card0` for GPU rendering.

**Solution**: User added to `video` and `render` groups:
```bash
sudo usermod -a -G video,render pi
```

### 2. Real-Time Priority
For smooth animations, Marathon Shell may request real-time scheduling.

**Solution**: Grant capability:
```bash
sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin
```

### 3. Wayland Socket Permissions
The Wayland socket (`/run/user/1000/wayland-0`) is owned by the user running the compositor.

**Security**: Only processes owned by the same user can connect.

## Debugging and Monitoring

### Enable Qt Debug Output
```bash
export QT_LOGGING_RULES="*.debug=true;marathon.*.info=true"
export QT_DEBUG_PLUGINS=1
```

### Monitor Compositor Performance
```bash
# Frame timing
QT_LOGGING_RULES="qt.scenegraph.info=true" marathon-shell-bin

# Wayland protocol messages
WAYLAND_DEBUG=1 marathon-shell-bin
```

### GPU Performance Monitoring
```bash
# Check GPU usage
sudo cat /sys/kernel/debug/dri/0/v3d_utilization

# Monitor memory usage
sudo cat /sys/kernel/debug/dri/0/bo_stats
```

## Future Enhancements

### Potential Improvements
1. **Wayland VNC Support**: Add `wayvnc` integration for remote access
2. **Multi-Display Support**: Extend to multiple HDMI outputs
3. **Hardware Video Decoding**: Leverage V4L2/MMAL for video playback
4. **Power Management**: Integrate with systemd-logind for suspend/resume
5. **Custom Boot Splash**: Replace rainbow screen with Marathon logo

### Performance Targets
- **Boot Time**: < 10 seconds from power-on to UI
- **Frame Rate**: Consistent 60 FPS on all UI interactions
- **Memory**: < 400MB idle memory usage
- **Latency**: < 10ms touch-to-photon latency

---

*Last updated: 2025-11-12*

