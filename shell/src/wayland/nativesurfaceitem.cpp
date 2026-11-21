#include "src/wayland/nativesurfaceitem.h"

#include "src/wayland/nativeinput.h"

#include <QGuiApplication>
#include <QLineF>
#include <QStyleHints>
#include <QTouchEvent>
#include <QWheelEvent>
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
    m_holdTimer.setSingleShot(true);
    connect(&m_holdTimer, &QTimer::timeout, this, [this] {
        QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
        if (seat && m_pointerTouchId >= 0 && m_touchPointer == TouchPointer::Pending) {
            m_touchPointer = TouchPointer::Held;
            seat->sendMousePressEvent(Qt::LeftButton);
        }
    });
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
        // Qt moves the pointer onto the surface with a touch; left there, it
        // reads as a hover to GTK, which opens tooltips under the finger.
        if (event->type() == QEvent::TouchEnd || event->type() == QEvent::TouchCancel) {
            QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
            if (seat && seat->mouseFocus() == view())
                seat->setMouseFocus(nullptr);
        }
        return;
    }

    QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
    if (!seat || !inputEventsEnabled()) {
        event->ignore();
        return;
    }

    for (const QEventPoint &point : event->points()) {
        const QPointF surfacePos = mapToSurface(point.position());
        if (point.state() == QEventPoint::State::Pressed && m_pointerTouchId < 0 &&
            inputRegionContains(point.position())) {
            m_pointerTouchId = point.id();
            m_touchPointer   = TouchPointer::Pending;
            m_touchStart     = surfacePos;
            sendMouseMoveEvent(point.position(), seat);
            if (focusOnClick())
                takeFocus(seat);
            m_holdTimer.start(QGuiApplication::styleHints()->mousePressAndHoldInterval());
        } else if (point.id() == m_pointerTouchId && point.state() == QEventPoint::State::Updated) {
            if (m_touchPointer == TouchPointer::Pending &&
                QLineF(mapFromSurface(m_touchStart), point.position()).length() >
                    QGuiApplication::styleHints()->startDragDistance()) {
                m_holdTimer.stop();
                m_touchPointer = TouchPointer::Dragging;
                seat->sendTouchPointEvent(surface(), 0, m_touchStart, Qt::TouchPointPressed);
                seat->sendTouchFrameEvent(surface()->client());
            }
            if (m_touchPointer == TouchPointer::Dragging) {
                seat->sendTouchPointEvent(surface(), 0, surfacePos, Qt::TouchPointMoved);
                seat->sendTouchFrameEvent(surface()->client());
            } else if (m_touchPointer == TouchPointer::Held) {
                sendMouseMoveEvent(point.position(), seat);
            }
        } else if (point.id() == m_pointerTouchId &&
                   point.state() == QEventPoint::State::Released) {
            m_holdTimer.stop();
            if (m_touchPointer == TouchPointer::Dragging) {
                seat->sendTouchPointEvent(surface(), 0, surfacePos, Qt::TouchPointReleased);
                seat->sendTouchFrameEvent(surface()->client());
                m_pointerTouchId = -1;
                continue;
            }
            sendMouseMoveEvent(point.position(), seat);
            if (m_touchPointer == TouchPointer::Pending) {
                seat->sendMousePressEvent(Qt::LeftButton);
                m_touchPointer = TouchPointer::Held;
            }
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

// Wheel axis events go to the pointer's surface; nothing may have entered
// this one yet (the trackpad scrolls without moving the pointer).
void NativeSurfaceItem::wheelEvent(QWheelEvent *event) {
    QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
    if (seat && inputEventsEnabled() && seat->mouseFocus() != view() &&
        inputRegionContains(event->position()))
        sendMouseMoveEvent(event->position(), seat);
    QWaylandQuickShellSurfaceItem::wheelEvent(event);
}

void NativeSurfaceItem::releasePointer() {
    m_holdTimer.stop();
    if (m_pointerTouchId < 0)
        return;
    QWaylandSeat *seat = compositor() ? compositor()->defaultSeat() : nullptr;
    if (seat && m_touchPointer == TouchPointer::Held)
        seat->sendMouseReleaseEvent(Qt::LeftButton);
    if (seat && m_touchPointer == TouchPointer::Dragging && surface() && surface()->client())
        seat->sendTouchCancelEvent(surface()->client());
    m_pointerTouchId = -1;
}

void NativeSurfaceItem::setupShellSurface() {
    disconnect(m_popupCreatedConnection);
    m_popupCreatedConnection = {};
    m_popup.clear();

    auto *xdgSurface = qobject_cast<QWaylandXdgSurface *>(shellSurface());
    if (!xdgSurface)
        return;
    // Qt's integration drags and resizes the window when a client asks
    // (GTK does from its header bar); phone windows stay where they are.
    if (QWaylandXdgToplevel *toplevel = xdgSurface->toplevel()) {
        disconnect(toplevel, &QWaylandXdgToplevel::startMove, nullptr, nullptr);
        disconnect(toplevel, &QWaylandXdgToplevel::startResize, nullptr, nullptr);
    }
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
