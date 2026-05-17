#pragma once

#include <QObject>
#include <QWaylandCompositor>
#include <QWaylandIdleInhibitManagerV1>
#include <QWaylandQuickOutput>
#include <QWaylandTextInputManager>
#include <QWaylandViewporter>
#include <QWaylandXdgShell>

// Full headers (not forward declarations) — Qt's MOC-generated metatype
// registration for Q_PROPERTY pointer types static_asserts that the
// pointed-to class is fully defined. Forward decls fail that check.
#include "foreign_toplevel_v1.h"
#include "layer_shell_v1.h"
#include "session_lock_v1.h"
#include "textinputv3.h"

class QQuickWindow;

// The standalone Marathon compositor. Owns the QWaylandCompositor + every
// server-side protocol extension Marathon apps and the marathon-shell layer-
// shell client need to render.
//
// Intentionally narrow: no process spawning, no QML INVOKABLEs for app launch
// (that's the shell's job). The compositor exposes surfaces to its own QML
// scene (compositor.qml) for rendering, and that's it. App launches happen in
// marathon-shell; the runner processes connect here as plain Wayland clients.
class MarathonCompositor : public QWaylandCompositor {
    Q_OBJECT
    Q_PROPERTY(QQuickWindow *window READ window CONSTANT)
    Q_PROPERTY(QWaylandQuickOutput *quickOutput READ quickOutput CONSTANT)
    Q_PROPERTY(QWaylandXdgShell *xdgShell READ xdgShell CONSTANT)
    Q_PROPERTY(WlrLayerShellV1 *layerShell READ layerShell CONSTANT)
    Q_PROPERTY(ExtSessionLockManagerV1 *sessionLock READ sessionLock CONSTANT)
    Q_PROPERTY(ForeignToplevelManagerV1 *foreignToplevels READ foreignToplevels CONSTANT)
    QML_ELEMENT

  public:
    explicit MarathonCompositor(QObject *parent = nullptr);
    ~MarathonCompositor() override;

    Q_INVOKABLE void attachWindow(QQuickWindow *window);
    QQuickWindow    *window() const {
        return m_window;
    }
    QWaylandQuickOutput *quickOutput() const {
        return m_output;
    }
    QWaylandXdgShell *xdgShell() const {
        return m_xdgShell;
    }
    WlrLayerShellV1 *layerShell() const {
        return m_layerShell;
    }
    ExtSessionLockManagerV1 *sessionLock() const {
        return m_sessionLock;
    }
    ForeignToplevelManagerV1 *foreignToplevels() const {
        return m_foreignToplevels;
    }

  private:
    void calculatePhysicalSize();

    // Plain pointers: every child is parented to this QWaylandCompositor
    // via QObject parentage, so Qt cleans them up. QPointer adds a guarded
    // dereference but breaks for forward-declared types in the QML
    // registration template (qmltyperegistrations needs the full type).
    QQuickWindow                 *m_window           = nullptr;
    QWaylandQuickOutput          *m_output           = nullptr;
    QWaylandXdgShell             *m_xdgShell         = nullptr;
    QWaylandViewporter           *m_viewporter       = nullptr;
    QWaylandTextInputManager     *m_textInputV2      = nullptr;
    QWaylandIdleInhibitManagerV1 *m_idleInhibit      = nullptr;
    TextInputManagerV3           *m_textInputV3      = nullptr;
    WlrLayerShellV1              *m_layerShell       = nullptr;
    ExtSessionLockManagerV1      *m_sessionLock      = nullptr;
    ForeignToplevelManagerV1     *m_foreignToplevels = nullptr;
};
