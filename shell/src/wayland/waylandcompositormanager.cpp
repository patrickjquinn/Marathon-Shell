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
    m_compositor->setApps(m_apps);
    m_compositor->setNativeScale(m_nativeScale);
    emit compositorCreated(m_compositor);
    return m_compositor;
#else
    return nullptr;
#endif
}

void WaylandCompositorManager::setNativeScale(qreal scale) {
    m_nativeScale = scale;
#ifdef HAVE_WAYLAND
    if (m_compositor)
        m_compositor->setNativeScale(scale);
#endif
}
