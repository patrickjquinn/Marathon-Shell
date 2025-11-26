# Marathon Shell Architecture

## Overview

Marathon Shell is a Wayland compositor and mobile application shell implemented in C++ and QML using the Qt6 framework. The architecture is organized into four major subsystems:

1. **Compositor Layer** - Wayland protocol implementation and window management
2. **Shell Layer** - User interface, gesture navigation, and visual presentation
3. **Service Layer** - System service integration (D-Bus, network, power, etc.)
4. **Application Layer** - App lifecycle management, packaging, and distribution

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Marathon Shell Process                     │
├─────────────────────────────────────────────────────────────────┤
│  QML Shell UI (MarathonShell.qml)                               │
│  ├── App Grid                                                    │
│  ├── Task Switcher                                               │
│  ├── Hub (Notifications)                                         │
│  ├── Quick Settings                                              │
│  └── Status Bar                                                  │
├─────────────────────────────────────────────────────────────────┤
│  C++ Backend (main.cpp, src/)                                    │
│  ├── WaylandCompositor (QtWaylandCompositor)                    │
│  ├── AppLifecycleManager                                         │
│  ├── MarathonAppRegistry & Loader                                │
│  ├── DesktopFileParser                                           │
│  └── D-Bus Service Managers                                      │
│      ├── NetworkManagerCpp (NetworkManager D-Bus)                │
│      ├── PowerManagerCpp (UPower D-Bus)                          │
│      ├── BluetoothManager (BlueZ D-Bus)                          │
│      ├── ModemManagerCpp (ModemManager D-Bus)                    │
│      └── Security Manager (PAM)                                  │
├─────────────────────────────────────────────────────────────────┤
│  Marathon Core Library (libmarathon-core.a)                      │
│  ├── MarathonAppPackager                                         │
│  ├── MarathonAppVerifier (GPG)                                   │
│  ├── MarathonAppInstaller                                        │
│  └── Permission Manager                                          │
├─────────────────────────────────────────────────────────────────┤
│  Qt6 Framework                                                   │
│  ├── QtQuick & QML Engine                                        │
│  ├── QtWaylandCompositor                                         │
│  ├── QtDBus                                                      │
│  └── QtMultimedia                                                │
└─────────────────────────────────────────────────────────────────┘
         │                           │                    │
         ▼                           ▼                    ▼
    Wayland Protocol          D-Bus Services        Marathon Apps
    (Native Apps)          (System Integration)   (~/.local/share/)
```

## Compositor Layer

### Wayland Implementation

Marathon Shell implements a Wayland compositor using QtWaylandCompositor. The compositor provides:

- **Surface Management** - XDG shell protocol for application windows
- **Input Handling** - Touch, mouse, and keyboard input routing
- **Output Management** - Screen configuration and rendering
- **Client Communication** - Wayland protocol message handling

**Key Components:**

- `WaylandCompositor` (`waylandcompositor.cpp`) - Main compositor class
- `WaylandCompositorManager` (`waylandcompositormanager.cpp`) - Compositor lifecycle
- `WaylandShellSurfaceItem` (QML) - Visual representation of Wayland surfaces
- `NativeAppWindow` (QML) - Container for embedded native applications

### Native App Integration Flow

```
1. User launches app via App Grid
   ↓
2. Shell parses .desktop file (DesktopFileParser)
   ↓
3. Shell sets WAYLAND_DISPLAY=marathon-wayland-0
   ↓
4. Shell spawns app process with modified environment
   ↓
5. App connects to marathon-wayland-0 socket
   ↓
6. Compositor receives surface creation events
   ↓
7. WaylandShellSurfaceItem wraps surface for QML
   ↓
8. NativeAppWindow displays surface in shell UI
```

### D-Bus Session Integration

The compositor spawns a D-Bus session bus on startup, providing:

- `org.freedesktop.Notifications` - Notification service
- `org.marathonos.shell.PermissionPortal` - Permission management
- MPRIS2 media player control
- GSettings/dconf access for GNOME apps

## Shell Layer

### QML Architecture

The shell UI is implemented as a state machine with three primary states:

1. **Home** - App Grid visible, bottom nav bar active
2. **Locked** - Lock screen with PIN/password entry
3. **PinEntry** - Authentication in progress

**State Transitions:**

```
LOCKED ──(swipe up)──> PIN_ENTRY
PIN_ENTRY ──(auth success)──> HOME
HOME ──(lock gesture)──> LOCKED
```

### Component Hierarchy

```
MarathonShell.qml (root)
├── MarathonLockScreen
│   └── MarathonPinScreen (PIN/password/fingerprint)
├── MainContent (state: home)
│   ├── MarathonStatusBar
│   ├── MarathonAppGrid
│   ├── MarathonTaskSwitcher
│   ├── MarathonHub (notifications)
│   ├── MarathonQuickSettings
│   ├── MarathonNavBar
│   └── AppWindow Container
│       ├── NativeAppWindow (Wayland apps)
│       └── MarathonAppWindow (Marathon QML apps)
└── Gesture Handlers (EdgeGesture, SwipeGesture)
```

### State Management

Marathon uses QML singletons for global state:

- **UIStore** - UI state (current view, gestures, animations)
- **SessionStore** - Session state (locked, unlocked, user info)
- **SystemStatusStore** - System status (battery, network, time)
- **SystemControlStore** - System controls (brightness, volume, toggles)
- **AppStore** - Application registry and lifecycle

Stores are QML singletons (marked `QT_QML_SINGLETON_TYPE`) loaded once and shared across all components.

### Gesture System

Gestures are implemented using QML `MouseArea` and `TapHandler` with custom logic:

**Gesture Types:**

- **Edge Swipe** - From screen edges (bottom, top, left)
- **Flick** - Quick swipe with velocity
- **Long Press** - Hold gesture for context actions
- **Drag** - Continuous movement (sliders, scrolling)

**Gesture Physics:**

Gestures use spring physics for natural feel:

```qml
SpringAnimation {
    spring: MMotion.springLight    // 1.5
    damping: MMotion.dampingLight  // 0.15
    epsilon: MMotion.epsilon        // 0.01
}
```

All gesture thresholds are configurable in `marathon-config.json`.

## Service Layer

### D-Bus Service Managers

Marathon Shell integrates with system services via D-Bus. Each service has a C++ manager class:

**Network Services:**

- `NetworkManagerCpp` - Interfaces with `org.freedesktop.NetworkManager`
  - WiFi scanning, connection, AP management
  - Ethernet status
  - Airplane mode
  - Hotspot/tethering (if supported)

**Power Management:**

- `PowerManagerCpp` - Interfaces with `org.freedesktop.UPower`
  - Battery level and state
  - Power profiles (performance, balanced, power-saver)
  - AC adapter status
  - Suspend/hibernate

**Bluetooth:**

- `BluetoothManager` - Interfaces with `org.bluez`
  - Device discovery and pairing
  - Connection management
  - Service UUID filtering

**Telephony:**

- `ModemManagerCpp` - Interfaces with `org.freedesktop.ModemManager1`
  - Call handling
  - SMS send/receive
  - Signal strength
  - Network registration

**Authentication:**

- `SecurityManager` - Uses Linux PAM directly
  - System password authentication
  - Quick PIN (encrypted, stored locally)
  - Fingerprint (via fprintd D-Bus service)
  - Rate limiting and lockout

### Service Initialization

Services are initialized in `main.cpp` in dependency order:

```cpp
// 1. Core services

SettingsManager *settingsManager = new SettingsManager(&app);

// 2. Display compositor
WaylandCompositorManager *compositorManager = 
    new WaylandCompositorManager(settingsManager, &app);

// 3. System services
NetworkManagerCpp *networkManager = new NetworkManagerCpp(&app);
PowerManagerCpp *powerManager = new PowerManagerCpp(&app);
SecurityManager *securityManager = new SecurityManager(&app);

// 4. App system
MarathonAppRegistry *appRegistry = new MarathonAppRegistry(&app);
MarathonAppLoader *appLoader = new MarathonAppLoader(appRegistry, &engine, &app);

// 5. Expose to QML
engine.rootContext()->setContextProperty("NetworkManagerCpp", networkManager);
engine.rootContext()->setContextProperty("PowerManagerCpp", powerManager);
// etc...
```

Services expose properties and methods to QML via `Q_PROPERTY` and `Q_INVOKABLE`.

## Application Layer

### Marathon App System

Marathon apps are QML modules installed to `~/.local/share/marathon-apps/`:

**App Structure:**

```
~/.local/share/marathon-apps/myapp/
├── manifest.json           # Metadata
├── MyApp.qml              # Entry point
├── qmldir                 # QML module definition
├── components/            # Reusable components
├── pages/                 # App screens
├── assets/                # Icons, images
└── libmyapp.so           # Optional C++ plugin
```

**Loading Process:**

1. `MarathonAppScanner` scans `~/.local/share/marathon-apps/`
2. Parses `manifest.json` for each app
3. `MarathonAppRegistry` stores app metadata
4. User launches app from App Grid
5. `MarathonAppLoader` loads QML module via `QQmlComponent`
6. App instance created with `MApp` root component
7. `AppLifecycleManager` transitions app to foreground state

### Package Format

`.marathon` packages are ZIP archives with this structure:

```
myapp.marathon (ZIP)
├── manifest.json
├── SIGNATURE.txt          # GPG detached signature (optional)
├── MyApp.qml
├── qmldir
├── components/
├── pages/
└── assets/
```

**Installation:**

1. User installs via `marathon-dev install` or App Store
2. `MarathonAppVerifier` checks GPG signature (if present)
3. `MarathonAppPackager` extracts to temp directory
4. `MarathonAppInstaller` validates manifest and permissions
5. Files copied to `~/.local/share/marathon-apps/`
6. App appears in App Grid on next scan

### Permission System

Apps declare permissions in `manifest.json`:

```json
{
  "permissions": ["network", "location", "camera"]
}
```

**Permission Enforcement:**

```
App requests resource
    ↓
Permission Portal D-Bus call
    ↓
PermissionManager checks manifest.json
    ↓
If granted: allow access
If denied: return error
```

Users can review/revoke permissions in Settings app.

## Data Flow Examples

### Example 1: WiFi Connection

```
User taps WiFi network in Settings
    ↓
WiFiPage.qml: calls NetworkManagerCpp.connectToNetwork(ssid, password)
    ↓
NetworkManagerCpp: sends D-Bus message to NetworkManager
    ↓
NetworkManager (system service): connects to AP
    ↓
NetworkManager: emits PropertiesChanged signal on D-Bus
    ↓
NetworkManagerCpp: receives signal, updates activeConnection property
    ↓
QML: property binding triggers, UI updates to "Connected"
```

### Example 2: App Launch (Marathon App)

```
User taps app icon in App Grid
    ↓
AppGrid.qml: emits appLaunched(appId)
    ↓
MarathonShell.qml: calls AppLifecycleManager.launchApp(appId)
    ↓
AppLifecycleManager: queries MarathonAppRegistry for app metadata
    ↓
MarathonAppLoader: creates QQmlComponent from app's entry point
    ↓
QML Engine: loads MyApp.qml and dependencies
    ↓
MApp component: signals appReady()
    ↓
AppLifecycleManager: transitions app to foreground
    ↓
MarathonShell: displays app in AppWindow
```

### Example 3: Gesture Navigation

```
User swipes up from bottom edge
    ↓
EdgeGesture MouseArea: pressed event at y > screenHeight - edgeThreshold
    ↓
EdgeGesture: tracks drag.y position
    ↓
UIStore.gestureProgress: updates (0.0 to 1.0)
    ↓
AppGrid: binds y position to gestureProgress
    ↓
User releases: flick velocity calculated
    ↓
If velocity > threshold: complete gesture (show app grid)
If velocity < threshold: cancel gesture (return to previous state)
    ↓
SpringAnimation: animates to final position with physics
```



## Build System

### CMake Structure

```
CMakeLists.txt (root)
├── marathon-core/CMakeLists.txt
├── marathon-ui/CMakeLists.txt
│   ├── Theme/CMakeLists.txt
│   ├── Core/CMakeLists.txt
│   └── ... (other UI modules)
├── shell/CMakeLists.txt
├── apps/CMakeLists.txt
│   ├── browser/CMakeLists.txt
│   ├── settings/CMakeLists.txt
│   └── ... (other apps)
└── tools/CMakeLists.txt
    └── marathon-dev/CMakeLists.txt
```

**Build Flow:**

1. Root CMakeLists.txt configures global settings
2. Subdirectories build in order:
   - marathon-core (static library)
   - marathon-ui (QML modules)
   - shell (executable, links marathon-core)
   - apps (QML modules, some with C++ plugins)
   - tools (marathon-dev CLI)

**QML Module Building:**

```cmake
qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
```

QML modules are built with `qt6_add_qml_module`, which:
- Generates `qmldir` files
- Compiles QML to C++ if enabled
- Creates import paths for QML engine
- Handles resource embedding

## Threading Model

### Main Thread

- QML engine and UI rendering
- D-Bus signal handling (queued connections)
- App lifecycle management

### Background Threads

- PAM authentication (QtConcurrent)
  - `SecurityManager::authenticateViaPAM()` runs in thread pool
  - Result delivered via `QFutureWatcher::finished()` signal
- App scanning (future: currently synchronous)
- Network requests (Qt's internal threading)

**Thread Safety:**

- D-Bus managers use Qt's auto-connection (queued if cross-thread)
- Signals/slots between threads are queued automatically
- QML property updates always occur on main thread
- Mutex protection not typically needed due to Qt's signal/slot thread safety

## Memory Management

### Object Ownership

- QML objects owned by QML engine (garbage collected)
- C++ objects typically have parent (`QObject *parent`)
- Objects with QML engine as parent deleted on engine destruction
- Context properties (`setContextProperty`) not owned by context - parent must be set

### Resource Lifecycle

**Application Resources:**
- Loaded on app launch
- Cached in QML engine
- Released when app backgrounded (configurable)
- Full cleanup on app quit

**System Resources:**
- D-Bus connections persist for shell lifetime
- Wayland surfaces destroyed when client disconnects
- Compositor framebuffers recreated on window resize

## Security Considerations

### Authentication

- PAM used for system password (secure, audited)
- Quick PIN stored as bcrypt hash (cost factor 12)
- Fingerprint uses fprintd D-Bus service (hardware-backed)
- Rate limiting: 5 attempts, exponential lockout

### Sandboxing

- Marathon apps run in same process (no sandboxing currently)
- Permission system provides access control
- Future: consider sandboxing via Flatpak or custom approach

### Native Apps

- Wayland protocol provides some isolation
- Apps cannot access other app surfaces
- Input events routed only to focused surface
- Flatpak/Snap apps use container sandboxing

### Code Signing

- GPG signatures for Marathon apps
- Verification during installation
- Trust status displayed in App Store
- Users can configure trusted keys

## Performance Characteristics

### Target Performance

- 60 FPS UI rendering on embedded hardware (Raspberry Pi 4)
- Sub-100ms gesture response time
- Sub-500ms app launch time (QML apps)
- Sub-1s app launch time (native apps)

### Optimization Strategies

- **Opaque rendering** - Prefer opaque colors for efficiency
- **Layer caching** - Complex QML items cached as textures
- **Spring animations** - Hardware-accelerated, efficient physics
- **Lazy loading** - Apps loaded on-demand, not at startup
- **QML compilation** - Ahead-of-time compilation for release builds
- **Resource sharing** - MarathonUI library shared across apps

### Bottlenecks

- Wayland surface composition (GPU-bound)
- D-Bus signal marshalling for high-frequency events
- QML property binding evaluation (CPU-bound)
- App scanning on first launch (I/O-bound)

## Future Architecture Considerations

### Planned Improvements

1. **Multi-process Architecture**
   - Separate compositor from shell UI process
   - App sandboxing via separate processes
   - Fault isolation (app crash doesn't kill shell)

2. **Permission Portals**
   - Implement full freedesktop.org portal spec
   - File picker, camera, microphone portals
   - Better Flatpak integration

3. **XWayland Support**
   - Run legacy X11 applications
   - Compatibility with wider app ecosystem

4. **Async App Scanning**
   - Scan apps in background thread
   - Progressive loading of app grid

5. **QML Caching**
   - Disk cache for compiled QML
   - Faster subsequent launches

### Known Technical Debt

- Some D-Bus managers lack proper error handling
- App lifecycle state machine could be more robust
- Compositor lacks fractional scaling support
- No crash reporting or recovery system
- QML validation warnings not all resolved

## References

- Qt6 Documentation: https://doc.qt.io/qt-6/
- Wayland Protocol: https://wayland.freedesktop.org/
- freedesktop.org Specifications: https://www.freedesktop.org/wiki/Specifications/
- PAM Documentation: http://www.linux-pam.org/
- D-Bus Specification: https://dbus.freedesktop.org/doc/dbus-specification.html

