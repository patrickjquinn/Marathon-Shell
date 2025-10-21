#include "waylandcompositormanager.h"
#include <QDebug>

WaylandCompositorManager::WaylandCompositorManager(QObject *parent)
    : QObject(parent)
{
    qInfo() << "[WaylandCompositorManager] Initialized";
#ifdef HAVE_WAYLAND
    qInfo() << "[WaylandCompositorManager] HAVE_WAYLAND is defined - Wayland support enabled";
#else
    qInfo() << "[WaylandCompositorManager] HAVE_WAYLAND not defined - Wayland support disabled";
#endif
}

WaylandCompositor* WaylandCompositorManager::createCompositor(QQuickWindow *window)
{
    qInfo() << "[WaylandCompositorManager] createCompositor called";
    qInfo() << "[WaylandCompositorManager] window pointer:" << window;
    
    if (!window) {
        qWarning() << "[WaylandCompositorManager] Cannot create compositor - window is NULL";
        return nullptr;
    }
    
#ifdef HAVE_WAYLAND
    qInfo() << "[WaylandCompositorManager] HAVE_WAYLAND defined, proceeding...";
    
    if (m_compositor) {
        qInfo() << "[WaylandCompositorManager] Compositor already exists, returning existing";
        return m_compositor;
    }
    
    qInfo() << "[WaylandCompositorManager] Creating new WaylandCompositor...";
    m_compositor = new WaylandCompositor(window);
    qInfo() << "[WaylandCompositorManager] WaylandCompositor created successfully";
    qInfo() << "[WaylandCompositorManager] Compositor pointer:" << m_compositor;
    return m_compositor;
#else
    qInfo() << "[WaylandCompositorManager] HAVE_WAYLAND not defined, returning NULL";
    return nullptr;
#endif
}

