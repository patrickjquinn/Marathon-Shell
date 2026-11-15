#pragma once

#include "src/components/windowtextureitem.h"

#include <QWaylandClient>
#include <QWaylandSurface>
#include <QWaylandView>

#include <algorithm>

namespace IdleInhibit {

    // The protocol honours an inhibitor only while its surface is visible: not
    // from an app in the background or behind the lock screen. The app (or
    // "pid N") of the first shown surface that inhibits idle, else empty.
    inline QString shownInhibitor(const QList<QWaylandSurface *> &surfaces) {
        for (const QWaylandSurface *surface : surfaces) {
            if (!surface->inhibitsIdle() || !surface->hasContent())
                continue;
            const QList<QWaylandView *> views = surface->views();
            if (std::none_of(views.cbegin(), views.cend(), [](const QWaylandView *view) {
                    const auto *item = qobject_cast<const QQuickItem *>(view->renderObject());
                    return WindowTextureItem::isShown(item) || WindowTextureItem::isSampled(item);
                }))
                continue;
            const QString appId = surface->property("appId").toString();
            return !appId.isEmpty() ? appId :
                                      QStringLiteral("pid %1").arg(surface->client()->processId());
        }
        return {};
    }

} // namespace IdleInhibit
