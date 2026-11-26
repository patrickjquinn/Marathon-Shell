#pragma once

#include <QObject>

class QMimeData;
class QWaylandCompositor;
class QWaylandSurface;

// One clipboard for the shell and its apps. What an app copies becomes the
// shell's QClipboard (retainedSelectionReceived hands it to take()); the
// shell's clipboard is what the app with the keyboard is offered, so a paste
// never reads from an app that has since been frozen or closed.
class SharedClipboard : public QObject {
    Q_OBJECT

  public:
    // After compositor->create().
    explicit SharedClipboard(QWaylandCompositor *compositor);

    void take(const QMimeData *data);

  private:
    void                claim();
    void                offer(QWaylandSurface *focus) const;
    bool                hasDataDevice(QWaylandSurface *surface) const;

    QWaylandCompositor *m_compositor;
    bool                m_taking = false;
};
