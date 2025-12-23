#include "src/wayland/waylandcompositormanager.h"
#include <QDebug>

WaylandCompositorManager::WaylandCompositorManager(QObject *parent)
    : QObject(parent) {
#ifdef HAVE_WAYLAND
    (void)parent;
#else
    qInfo() << "[WaylandCompositorManager] HAVE_WAYLAND not defined - Wayland support disabled";
#endif
}

WaylandCompositor *WaylandCompositorManager::createCompositor(QQuickWindow *window) {
    if (!window) {
        qWarning() << "[WaylandCompositorManager] Cannot create compositor: window is null";
        return nullptr;
    }

#ifdef HAVE_WAYLAND
    if (m_compositor) {
        return m_compositor;
    }

    m_compositor = new WaylandCompositor(window);
    return m_compositor;
#else
    return nullptr;
#endif
}
