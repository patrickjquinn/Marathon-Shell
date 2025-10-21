#ifndef WAYLANDCOMPOSITORMANAGER_H
#define WAYLANDCOMPOSITORMANAGER_H

#include <QObject>
#include <QQuickWindow>

#ifdef HAVE_WAYLAND
#include "waylandcompositor.h"
#endif

// Forward declare for when HAVE_WAYLAND is not defined
class WaylandCompositor;

class WaylandCompositorManager : public QObject
{
    Q_OBJECT

public:
    explicit WaylandCompositorManager(QObject *parent = nullptr);
    
    Q_INVOKABLE WaylandCompositor* createCompositor(QQuickWindow *window);

private:
#ifdef HAVE_WAYLAND
    WaylandCompositor *m_compositor = nullptr;
#endif
};

#endif // WAYLANDCOMPOSITORMANAGER_H

