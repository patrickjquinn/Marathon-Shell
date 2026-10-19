#include "remotetextinputtarget.h"

#include <QQuickItem>
#include <QWaylandCompositor>
#include <QWaylandQuickShellSurfaceItem>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandView>
#include <QWaylandXdgShell>

namespace {
    QString itemAppId(QObject *object) {
        auto *item = qobject_cast<QWaylandQuickShellSurfaceItem *>(object);
        auto *xdg  = item ? qobject_cast<QWaylandXdgSurface *>(item->shellSurface()) : nullptr;
        return xdg && xdg->toplevel() ? xdg->toplevel()->appId() : QString();
    }
} // namespace

QString RemoteTextInputTarget::appIdOf(QObject *object, QWaylandCompositor *compositor) {
    if (QString id = itemAppId(object); !id.isEmpty())
        return id;
    auto *item = qobject_cast<QQuickItem *>(object);
    if (item && item->flags().testFlag(QQuickItem::ItemAcceptsInputMethod))
        return {};
    QWaylandSeat    *seat  = compositor ? compositor->defaultSeat() : nullptr;
    QWaylandSurface *focus = seat ? seat->keyboardFocus() : nullptr;
    if (!focus)
        return {};
    const QList<QWaylandView *> views = focus->views();
    for (QWaylandView *view : views) {
        if (QString id = itemAppId(view->renderObject()); !id.isEmpty())
            return id;
    }
    return {};
}
