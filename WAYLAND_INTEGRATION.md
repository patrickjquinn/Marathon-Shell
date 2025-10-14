# Wayland Native App Integration

## Overview

Marathon Shell now supports running native Linux Wayland applications alongside Marathon apps. This provides a seamless experience where users can launch, minimize, and switch between both types of apps using the same gestures and UI.

## Architecture

### Components

1. **WaylandCompositor (C++)**
   - Location: `shell/src/waylandcompositor.{h,cpp}`
   - Manages Wayland surfaces and client applications
   - Handles XDG Shell and WlShell protocols
   - Launches native apps with proper environment variables
   - Provides surface lifecycle events to QML

2. **DesktopEntryParser (QML Singleton)**
   - Location: `shell/qml/services/DesktopEntryParser.qml`
   - Scans `/usr/share/applications` and `/usr/local/share/applications` for `.desktop` files
   - Parses desktop entries to discover installed native apps
   - Provides app metadata (name, icon, exec command, categories)

3. **NativeAppWindow (QML Component)**
   - Location: `shell/qml/apps/native/NativeAppWindow.qml`
   - Embeds Wayland surfaces using `ShellSurfaceItem`
   - Extends `MApp` for lifecycle management
   - Provides consistent gesture support (minimize, close, back navigation)

4. **AppStore Integration**
   - Merges Marathon apps and native apps into a unified catalog
   - Tracks app type (`marathon` vs `native`)
   - Provides helper functions (`isNativeApp()`, `isInternalApp()`)

5. **TaskManagerStore Integration**
   - Tracks both Marathon and native app tasks
   - Stores surface IDs for native apps
   - Enables switching between running apps

6. **MarathonTaskSwitcher Integration**
   - Renders live previews of both Marathon and native apps
   - Scales native app surfaces to fit in the active frame grid
   - Provides consistent card UI for both app types

## How It Works

### App Discovery

1. On startup, `DesktopEntryParser` scans for `.desktop` files
2. Parsed apps are added to `AppStore.nativeApps`
3. `AppStore.refreshAppList()` merges Marathon and native apps
4. Native apps appear in the app grid alongside Marathon apps

### App Launching

1. User taps a native app in the app grid
2. `MarathonShell.onAppLaunched()` checks `app.type === "native"`
3. Shell stores app info in `pendingNativeApp` property
4. `WaylandCompositor.launchApp(app.exec)` starts the process
5. Process inherits `WAYLAND_DISPLAY=marathon-wayland-0` environment
6. Native app connects to Marathon's Wayland compositor

### Surface Management & Window Display

1. Wayland client creates a surface
2. `WaylandCompositor` emits `surfaceCreated(surface)` signal
3. Shell receives signal and matches with `pendingNativeApp`
4. **`MarathonAppWindow.show()` is called with `type: "native"` and surface reference**
5. Native app is loaded into `appWindowContainer` (same as Marathon apps!)
6. Surface is embedded using `ShellSurfaceItem` within `NativeAppWindow`
7. `TaskManagerStore` tracks the task with type and surface ID

### Window Management Feature Parity

Native apps now have **100% feature parity** with Marathon apps:

✅ **Safe Areas**: Native apps respect `Constants.safeAreaTop` and `Constants.safeAreaBottom`
- `MarathonAppWindow` applies `anchors.topMargin` and `anchors.bottomMargin`
- Native apps won't overlap status bar or navigation bar

✅ **Minimize Gesture**: Native apps scale down smoothly with gesture progress
- Uses same `appWindowContainer` scale/opacity transforms
- Card frame overlay appears at 30% gesture progress
- Snaps into active frame grid on release

✅ **Card Frame**: Native apps get the exact same card decorations
- Dark background (`Colors.backgroundDark`)
- Banner with app icon, title, and close button
- Matches TaskSwitcher card styling pixel-perfect

✅ **Back Navigation**: Native apps receive back gesture events
- `NativeAppWindow` extends `MApp` 
- `onBackPressed` signal is emitted
- App can handle or default to close

✅ **Lifecycle Management**: Native apps integrate with `AppLifecycleManager`
- Full state tracking (launched, resumed, paused, stopped)
- `bringToForeground()`, `minimize()`, `restore()`, `close()`

✅ **Fade-in Animation**: Native apps fade in smoothly when opened
- Same 300ms opacity animation as Marathon apps

### Gesture Support (Detailed)

- **Minimize (swipe up from nav bar)**: 
  - Native app scales to 65% and fades out
  - Card frame appears with icon/title/close button
  - Snaps into active frame grid at release
  - Live preview continues in TaskSwitcher

- **Close (from TaskSwitcher)**: 
  - Closes the Wayland client connection
  - Surface destroyed signal triggers cleanup
  - Task removed from `TaskManagerStore`

- **Restore (from TaskSwitcher)**: 
  - Shows native app in `MarathonAppWindow`
  - Re-embeds existing Wayland surface
  - App resumes from paused state

- **Back (swipe right from nav bar)**: 
  - Routed through `AppLifecycleManager.handleSystemBack()`
  - Native app's `MApp.onBackPressed` is called
  - If not handled, app closes

## Platform Support

### Linux (Wayland)
✅ **Fully Supported**
- Native Wayland apps run directly
- XWayland can be used for X11 apps
- Full compositor functionality

### macOS
⚠️ **Not Supported**
- Qt WaylandCompositor not available on macOS
- Code conditionally compiled with `#ifdef HAVE_WAYLAND`
- Native app UI gracefully hidden on macOS

### Future: Other Platforms
- Windows: Would require different window embedding approach
- Android/iOS: Would use native window management

## Configuration

### CMake Flags

```cmake
HAVE_WAYLAND - Automatically set if Qt6::WaylandCompositor is found
```

### Wayland Socket

- Socket name: `marathon-wayland-0`
- Location: `$XDG_RUNTIME_DIR/marathon-wayland-0`

### Environment Variables

Native apps are launched with:
```bash
WAYLAND_DISPLAY=marathon-wayland-0
XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland
CLUTTER_BACKEND=wayland
SDL_VIDEODRIVER=wayland
```

## Testing

### On Linux

1. Build Marathon Shell on a Linux system with Wayland
2. Install a native Wayland app (e.g., `gnome-calculator`)
3. Launch Marathon Shell
4. Native apps should appear in the app grid
5. Tap a native app to launch it
6. Test gestures (minimize, restore, close)

### Mock Apps (Development)

For development without native apps, `DesktopEntryParser` includes mock entries:
- Calculator (`gnome-calculator`)
- Text Editor (`gnome-text-editor`)
- Terminal (`gnome-terminal`)

## API Reference

### WaylandCompositor

```qml
import MarathonOS.Wayland

WaylandCompositor {
    property string socketName // "marathon-wayland-0"
    
    signal surfaceCreated(surface)
    signal surfaceDestroyed(surface)
    signal appLaunched(command, pid)
    signal appClosed(pid)
    
    function launchApp(command)
    function closeWindow(surfaceId)
    function getSurfaceById(surfaceId)
}
```

### DesktopEntryParser

```qml
import MarathonOS.Shell

// Singleton
DesktopEntryParser.nativeApps // Array of app objects
DesktopEntryParser.scanDesktopEntries() // Rescan
DesktopEntryParser.getApp(appId) // Get app by ID
DesktopEntryParser.getCategoryApps(category) // Filter by category
```

### NativeAppWindow

```qml
import MarathonOS.Shell

NativeAppWindow {
    property var waylandSurface
    property string nativeAppId
    property string nativeTitle
    property int surfaceId
    
    // Inherits from MApp:
    // - appId, appName, appIcon
    // - onBackPressed, onMinimizeRequested, onClosed
    // - Full lifecycle events
}
```

## Troubleshooting

### Native apps don't appear in grid
- Check `DesktopEntryParser` logs
- Verify `.desktop` files exist in search paths
- Run `AppStore.refreshAppList()` manually

### Native apps fail to launch
- Check Wayland compositor is initialized
- Verify `XDG_RUNTIME_DIR` is set
- Check app command in `.desktop` file

### Surface not rendering
- Verify `ShellSurfaceItem` is receiving surface
- Check surface ID is passed correctly
- Look for QML errors in console

### App doesn't respond to gestures
- Ensure `NativeAppWindow` extends `MApp`
- Verify `AppLifecycleManager` integration
- Check gesture area isn't blocked

## Future Enhancements

1. **XWayland Integration**
   - Support X11 apps via XWayland
   - Automatic fallback for legacy apps

2. **Window Decorations**
   - Custom title bars for native apps
   - Consistent branding across all apps

3. **Multi-Monitor Support**
   - Wayland output management
   - Per-monitor DPI scaling

4. **Performance Optimization**
   - Offscreen buffer caching
   - Lazy surface creation
   - GPU texture sharing

5. **Security Sandboxing**
   - Per-app Wayland sockets
   - Permission management
   - Resource quotas

## References

- [Qt Wayland Compositor Documentation](https://doc.qt.io/qt-6/qtwaylandcompositor-index.html)
- [Wayland Protocol Specification](https://wayland.freedesktop.org/docs/html/)
- [XDG Shell Protocol](https://wayland.app/protocols/xdg-shell)
- [Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/)

