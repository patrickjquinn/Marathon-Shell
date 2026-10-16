#ifndef WAYLANDCOMPOSITORMANAGER_H
#define WAYLANDCOMPOSITORMANAGER_H

#include <QObject>
#include <QQuickWindow>

#ifdef HAVE_WAYLAND
#include "src/wayland/waylandcompositor.h"
#endif

class WaylandCompositor;

class MarathonAppRegistry;

class WaylandCompositorManager : public QObject {
    Q_OBJECT

  public:
    explicit WaylandCompositorManager(QObject *parent = nullptr);

    Q_INVOKABLE WaylandCompositor *createCompositor(QQuickWindow *window);

    void setAppRegistry(MarathonAppRegistry *registry) {
        m_appRegistry = registry;
    }
    // Held until the compositor exists, which QML creates later.
    void setNativeScale(qreal scale);

  private:
    MarathonAppRegistry *m_appRegistry = nullptr;
    qreal                m_nativeScale = 1.0;
#ifdef HAVE_WAYLAND
    WaylandCompositor *m_compositor = nullptr;
#endif
};

#endif
