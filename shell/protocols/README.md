# Wayland Protocol Infrastructure

This directory contains Wayland protocol definitions and generated bindings for Marathon Shell.

## Available Protocols

### wlr-layer-shell-unstable-v1
- **Purpose**: Proper z-ordering and layer management for system UI elements
- **Status**: Protocol files downloaded, bindings generated
- **Files**:
  - `wlr-layer-shell-unstable-v1.xml` - Protocol specification
  - `wlr-layer-shell-unstable-v1-protocol.c` - Generated C code
  - `wlr-layer-shell-unstable-v1-client-protocol.h` - Generated header
- **Implementation**: Requires Qt Wayland Compositor extension - **DEFERRED** for future implementation
- **Benefit**: Would allow Marathon system UI (status bar, panels) to properly layer above/below apps

### ext-session-lock-v1
- **Purpose**: Compositor-enforced screen locking
- **Status**: Protocol files downloaded, bindings generated
- **Files**:
  - `ext-session-lock-v1.xml` - Protocol specification
  - `ext-session-lock-v1-protocol.c` - Generated C code
  - `ext-session-lock-v1-client-protocol.h` - Generated header
- **Implementation**: Requires Qt Wayland Compositor extension - **DEFERRED** for future implementation
- **Benefit**: Would prevent apps from rendering when screen is locked (security improvement)

## Future Work

To fully implement these protocols, Marathon Shell would need:
1. Custom QWaylandShellIntegration subclasses for each protocol
2. Protocol global registration in WaylandCompositor
3. Surface role management for layer surfaces and lock surfaces
4. Z-ordering logic based on layer (background, bottom, top, overlay)
5. Exclusive zone calculations for panels

## Alternative Approach

For immediate z-ordering improvements without protocol changes:
- Use Qt's z-property and Item stacking
- Implement proper surface ordering in MarathonShell.qml
- Use modal overlays for lock screen

## References
- [wlr-protocols repository](https://gitlab.freedesktop.org/wlroots/wlr-protocols)
- [wayland-protocols repository](https://gitlab.freedesktop.org/wayland/wayland-protocols)
- [Qt Wayland Compositor documentation](https://doc.qt.io/qt-6/qtwaylandcompositor-index.html)

