#ifndef WAYLANDCOMPOSITORMANAGER_H
#define WAYLANDCOMPOSITORMANAGER_H

#include <QObject>
#include <QQuickWindow>

#ifdef HAVE_WAYLAND
#include "waylandcompositor.h"
#endif

// Forward declarations
class WaylandCompositor;
class SettingsManager;

class WaylandCompositorManager : public QObject {
    Q_OBJECT

  public:
    explicit WaylandCompositorManager(SettingsManager *settingsManager, QObject *parent = nullptr);

    Q_INVOKABLE WaylandCompositor *createCompositor(QQuickWindow *window);

  private:
    SettingsManager *m_settingsManager;
#ifdef HAVE_WAYLAND
    WaylandCompositor *m_compositor = nullptr;
#endif
};

#endif // WAYLANDCOMPOSITORMANAGER_H
