#pragma once

#include <QList>
#include <QObject>
#include <QQmlListProperty>
#include <QWaylandIdleInhibitManagerV1>
#include <QWaylandQuickCompositor>
#include <QWaylandQuickOutput>
#include <QWaylandTextInputManager>
#include <QWaylandViewporter>
#include <QWaylandXdgShell>

// Full headers (not forward declarations) — Qt's MOC-generated metatype
// registration for Q_PROPERTY pointer types static_asserts that the
// pointed-to class is fully defined. Forward decls fail that check.
#include "foreign_toplevel_v1.h"
#include "layer_shell_v1.h"
#include "screencopy_v1.h"
#include "session_lock_v1.h"
#include "textinputv3.h"

class QQuickWindow;

// The standalone Marathon compositor. Owns the QWaylandCompositor + every
// server-side protocol extension Marathon apps and the marathon-shell layer-
// shell client need to render.
//
// Lifecycle pattern (Qt-blessed for standalone QtQuick compositors):
//
//   1. main() registers MarathonCompositor as a QML type and loads
//      Compositor.qml. The QML root IS a MarathonCompositor.
//   2. QML's Window declares a child WaylandOutput with
//      compositor: comp / window: <thisWindow> as set-once bindings.
//   3. QQmlComponent calls componentComplete() on the MarathonCompositor
//      root. Inside Qt's implementation that invokes
//      QWaylandCompositor::create(), which is the moment display() becomes
//      fully usable. We override create() to register our wlr-* /
//      ext-session-lock-v1 globals — they all need a valid display.
//   4. QML's WaylandOutput then runs its OWN componentComplete; its
//      Component.onCompleted handler in Compositor.qml calls
//      setupOutput(output), which wires the screencopy extension to the
//      now-available output + window.
//
// Doing any of this from C++ AFTER engine.loadFromModule() returns races
// the threaded render loop and crashes on LLVMpipe + virtio-gpu (the
// real failure that gated Phase C-7 r41/r42/r43). See docs/C7_STATUS.md.
class MarathonCompositor : public QWaylandQuickCompositor {
    Q_OBJECT
    // QML default property — mirrors the private
    // QWaylandQuickCompositorQuickExtensionContainer::data that the stock
    // WaylandCompositor QML element uses, so child Window/WaylandOutput
    // declarations parse cleanly.
    Q_PROPERTY(QQmlListProperty<QObject> data READ data DESIGNABLE false)
    Q_CLASSINFO("DefaultProperty", "data")

    Q_PROPERTY(QWaylandXdgShell *xdgShell READ xdgShell CONSTANT)
    Q_PROPERTY(WlrLayerShellV1 *layerShell READ layerShell CONSTANT)
    Q_PROPERTY(ExtSessionLockManagerV1 *sessionLock READ sessionLock CONSTANT)
    Q_PROPERTY(ForeignToplevelManagerV1 *foreignToplevels READ foreignToplevels CONSTANT)
    Q_PROPERTY(ScreencopyManagerV1 *screencopy READ screencopy CONSTANT)
    QML_ELEMENT

  public:
    explicit MarathonCompositor(QObject *parent = nullptr);
    ~MarathonCompositor() override;

    QQmlListProperty<QObject> data() {
        return QQmlListProperty<QObject>(this, &m_data);
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
    ScreencopyManagerV1 *screencopy() const {
        return m_screencopy;
    }

    // Called from Compositor.qml's WaylandOutput.Component.onCompleted —
    // by then the output has its compositor + window bindings set and the
    // render thread can sample from it safely.
    Q_INVOKABLE void setupOutput(QWaylandQuickOutput *output);

  protected:
    // Hooked to register custom-extension globals against a fully-alive
    // display. Called by Qt's QML engine on componentComplete of this
    // QML root.
    void create() override;

  private:
    QList<QObject *>              m_data;
    QWaylandXdgShell             *m_xdgShell         = nullptr;
    QWaylandViewporter           *m_viewporter       = nullptr;
    QWaylandTextInputManager     *m_textInputV2      = nullptr;
    QWaylandIdleInhibitManagerV1 *m_idleInhibit      = nullptr;
    TextInputManagerV3           *m_textInputV3      = nullptr;
    WlrLayerShellV1              *m_layerShell       = nullptr;
    ExtSessionLockManagerV1      *m_sessionLock      = nullptr;
    ForeignToplevelManagerV1     *m_foreignToplevels = nullptr;
    ScreencopyManagerV1          *m_screencopy       = nullptr;
};
