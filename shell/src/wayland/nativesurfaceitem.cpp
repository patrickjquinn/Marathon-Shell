#include "src/wayland/nativesurfaceitem.h"

#include "src/wayland/nativeinput.h"

#include <QTouchEvent>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandXdgShell>
#include <QWaylandXdgSurface>

NativeSurfaceItem::NativeSurfaceItem(QQuickItem *parent)
    : QWaylandQuickShellSurfaceItem(parent) {
    // Qt's automatic item always renders at unconstrainedPosition(), even
    // after a compositor sends a different xdg_popup.configure. Marathon owns
    // the popup tree so configured geometry, client scale and input policy are
    // shared with the parent surface.
    setAutoCreatePopupItems(false);
    connect(this, &QWaylandQuickShellSurfaceItem::shellSurfaceChanged, this,
            &NativeSurfaceItem::setupShellSurface);
}

QStringList NativeSurfaceItem::applicationTerms() const {
    return m_applicationTerms;
}

void NativeSurfaceItem::setApplicationTerms(const QStringList &terms) {
    if (m_applicationTerms == terms)
        return;
    m_applicationTerms  = terms;
    const bool fallback = NativeInput::needsPointerFallback(terms);
    if (m_pointerFallback && !fallback)
        releasePointer();
    m_pointerFallback = fallback;
    emit applicationTermsChanged();
}

void NativeSurfaceItem::touchEvent(QTouchEvent *event) {
    if (!m_pointerFallback) {
        QWaylandQuickShellSurfaceItem::touchEvent(event);
        return;
    }

    QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
    if (!seat || !inputEventsEnabled()) {
        event->ignore();
        return;
    }

    for (const QEventPoint &point : event->points()) {
        if (point.state() == QEventPoint::State::Pressed && m_pointerTouchId < 0 &&
            inputRegionContains(point.position())) {
            m_pointerTouchId = point.id();
            sendMouseMoveEvent(point.position(), seat);
            if (focusOnClick())
                takeFocus(seat);
            seat->sendMousePressEvent(Qt::LeftButton);
        } else if (point.id() == m_pointerTouchId && point.state() == QEventPoint::State::Updated) {
            sendMouseMoveEvent(point.position(), seat);
        } else if (point.id() == m_pointerTouchId &&
                   point.state() == QEventPoint::State::Released) {
            sendMouseMoveEvent(point.position(), seat);
            releasePointer();
        }
    }
    event->accept();
}

void NativeSurfaceItem::touchUngrabEvent() {
    if (!m_pointerFallback) {
        QWaylandQuickShellSurfaceItem::touchUngrabEvent();
        return;
    }
    releasePointer();
}

void NativeSurfaceItem::releasePointer() {
    if (m_pointerTouchId < 0)
        return;
    if (QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr)
        seat->sendMouseReleaseEvent(Qt::LeftButton);
    m_pointerTouchId = -1;
}

void NativeSurfaceItem::setupShellSurface() {
    disconnect(m_popupCreatedConnection);
    m_popupCreatedConnection = {};
    m_popup.clear();

    auto *xdgSurface = qobject_cast<QWaylandXdgSurface *>(shellSurface());
    if (!xdgSurface)
        return;
    if (QWaylandXdgPopup *popup = xdgSurface->popup())
        attachPopup(popup);

    QWaylandXdgShell *shell = xdgSurface->shell();
    if (!shell)
        return;
    m_popupCreatedConnection =
        connect(shell, &QWaylandXdgShell::popupCreated, this,
                [this, xdgSurface](QWaylandXdgPopup *popup, QWaylandXdgSurface *child) {
                    if (popup && popup->parentXdgSurface() == xdgSurface)
                        createPopup(popup, child);
                });
}

void NativeSurfaceItem::createPopup(QWaylandXdgPopup *popup, QWaylandXdgSurface *xdgSurface) {
    if (!popup || !xdgSurface)
        return;
    auto *item = new NativeSurfaceItem(this);
    item->setApplicationTerms(applicationTerms());
    item->setOutput(output());
    item->setFocusOnClick(true);
    item->setShellSurface(xdgSurface);
    item->attachPopup(popup);
    connect(item, &QWaylandQuickItem::surfaceDestroyed, item, &QObject::deleteLater);
}

void NativeSurfaceItem::attachPopup(QWaylandXdgPopup *popup) {
    if (!popup || m_popup == popup)
        return;
    m_popup = popup;
    // Qt 6.11's private XdgPopupIntegration handles this signal too, but
    // always restores unconstrainedPosition(). Queue Marathon's policy update
    // so the compositor-provided configured geometry is the final position.
    connect(popup, &QWaylandXdgPopup::configuredGeometryChanged, this,
            &NativeSurfaceItem::updatePopupGeometry, Qt::QueuedConnection);
    if (QWaylandXdgSurface *surface = popup->xdgSurface()) {
        connect(surface, &QWaylandXdgSurface::windowGeometryChanged, this,
                &NativeSurfaceItem::updatePopupGeometry, Qt::QueuedConnection);
    }
    QMetaObject::invokeMethod(this, &NativeSurfaceItem::updatePopupGeometry, Qt::QueuedConnection);
    raise();
}

void NativeSurfaceItem::updatePopupGeometry() {
    if (!m_popup)
        return;
    QRect geometry = m_popup->configuredGeometry();
    if (!geometry.isValid())
        geometry = QRect(m_popup->unconstrainedPosition(), m_popup->positionerSize());
    QWaylandXdgSurface *parent       = m_popup->parentXdgSurface();
    QWaylandXdgSurface *popupSurface = m_popup->xdgSurface();
    if (!parent || !popupSurface)
        return;
    const QPoint surfacePosition = parent->windowGeometry().topLeft() + geometry.topLeft() -
        popupSurface->windowGeometry().topLeft();
    auto *parentSurfaceItem = qobject_cast<QWaylandQuickItem *>(parentItem());
    setPosition(parentSurfaceItem ? parentSurfaceItem->mapFromSurface(surfacePosition) :
                                    mapFromSurface(surfacePosition));
}
