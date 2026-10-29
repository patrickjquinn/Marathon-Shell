#ifndef WAYLANDCOMPOSITORMANAGER_H
#define WAYLANDCOMPOSITORMANAGER_H

#include <QObject>
#include <QQuickWindow>

#ifdef HAVE_WAYLAND
#include "src/wayland/waylandcompositor.h"
#endif

class WaylandCompositor;

class Apps;

class WaylandCompositorManager : public QObject {
    Q_OBJECT
#ifdef HAVE_WAYLAND
    Q_PROPERTY(WaylandCompositor *compositor READ compositor NOTIFY compositorCreated)
#endif

  public:
    explicit WaylandCompositorManager(QObject *parent = nullptr);

    Q_INVOKABLE WaylandCompositor *createCompositor(QQuickWindow *window);

    void                           setApps(Apps *apps) {
        m_apps = apps;
    }
    // Held until the compositor exists, which QML creates later.
    void setNativeScale(qreal scale);
#ifdef HAVE_WAYLAND
    WaylandCompositor *compositor() const {
        return m_compositor;
    }

  signals:
    void compositorCreated(WaylandCompositor *compositor);
#endif

  private:
    Apps *m_apps        = nullptr;
    qreal m_nativeScale = 1.0;
#ifdef HAVE_WAYLAND
    WaylandCompositor *m_compositor = nullptr;
#endif
};

#endif
