// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see pagestackgesture.h.

#include "pagestackgesture.h"
#include "keeltheme.h"

#include <QFileInfo>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QTouchEvent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QStyleHints>

KeelPageStackGestureArea::KeelPageStackGestureArea(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFiltersChildMouseEvents(true);
    setAcceptedMouseButtons(Qt::LeftButton);
    setAcceptTouchEvents(true);
}

void KeelPageStackGestureArea::setBackNavigation(bool b)
{
    if (b == m_back)
        return;
    m_back = b;
    emit backNavigationChanged();
}

void KeelPageStackGestureArea::setForwardNavigation(bool f)
{
    if (f == m_forward)
        return;
    m_forward = f;
    emit forwardNavigationChanged();
}

void KeelPageStackGestureArea::setNavigationStyle(int style)
{
    if (style == m_style)
        return;
    m_style = style;
    emit navigationStyleChanged();
}

QUrl KeelPageStackGestureArea::resolveImportPage(const QString &source) const
{
    QQmlEngine *engine = qmlEngine(this);
    const int dot = source.lastIndexOf(QLatin1Char('.'));
    if (!engine || dot <= 0)
        return QUrl(source);
    const QString relative = source.left(dot).replace(QLatin1Char('.'), QLatin1Char('/'))
                             + QLatin1Char('/') + source.mid(dot + 1) + QStringLiteral(".qml");
    for (const QString &path : engine->importPathList()) {
        const QString file = path + QLatin1Char('/') + relative;
        if (QFileInfo::exists(file))
            return QUrl::fromLocalFile(file);
    }
    return QUrl(source);
}

bool KeelPageStackGestureArea::wantsDrag(const QPointF &delta) const
{
    const qreal threshold = keel::themeValue(this, "startDragDistance",
                                             QGuiApplication::styleHints()->startDragDistance());
    if (horizontalNavigationStyle()) {
        if (qAbs(delta.x()) <= threshold || qAbs(delta.x()) <= qAbs(delta.y()))
            return false;
        return delta.x() > 0 ? m_back : m_forward;
    }
    if (qAbs(delta.y()) <= threshold || qAbs(delta.y()) <= qAbs(delta.x()))
        return false;
    return delta.y() > 0 && m_back;
}

void KeelPageStackGestureArea::setDelta(const QPointF &delta)
{
    if (delta == m_delta)
        return;
    m_delta = delta;
    emit differencesChanged();
}

bool KeelPageStackGestureArea::childMouseEventFilter(QQuickItem *item, QEvent *event)
{
    Q_UNUSED(item)
    if (!isEnabled() || !isVisible())
        return false;
    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::TouchBegin: {
        auto *pe = static_cast<QPointerEvent *>(event);
        if (pe->pointCount() < 1 || m_pressed)
            return false;
        m_pressPos = mapFromScene(pe->point(0).scenePosition());
        m_pointId = pe->point(0).id();
        m_tracking = true;
        return false;
    }
    case QEvent::MouseMove:
    case QEvent::TouchUpdate: {
        if (!m_tracking || m_pressed)
            return false;
        auto *pe = static_cast<QPointerEvent *>(event);
        const QEventPoint *point = nullptr;
        for (int i = 0; i < pe->pointCount(); ++i) {
            if (event->type() == QEvent::MouseMove || pe->point(i).id() == m_pointId) {
                point = &pe->point(i);
                break;
            }
        }
        if (!point)
            return false;
        // A child that keeps its grab (preventStealing) keeps the drag.
        const QObject *grabber = pe->exclusiveGrabber(*point);
        if (auto *grabItem = qobject_cast<const QQuickItem *>(grabber); grabItem && grabItem != this
                && (grabItem->keepMouseGrab() || grabItem->keepTouchGrab()))
            return false;
        const QPointF delta = mapFromScene(point->scenePosition()) - m_pressPos;
        if (!wantsDrag(delta))
            return false;
        // Take the point the event carries (a touch point on a phone, also
        // when it reached the child as a synthesized mouse event).
        pe->setExclusiveGrabber(*point, this);
        setKeepMouseGrab(true);
        setKeepTouchGrab(true);
        m_pressed = true;
        emit pressedChanged();
        emit pressed();
        setDelta(delta);
        return true;
    }
    case QEvent::MouseButtonRelease:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel:
        if (!m_pressed)
            m_tracking = false;
        return false;
    default:
        return false;
    }
}

void KeelPageStackGestureArea::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_pressed) {
        event->ignore();
        return;
    }
    setDelta(mapFromScene(event->scenePosition()) - m_pressPos);
}

void KeelPageStackGestureArea::finish(bool release)
{
    if (!m_pressed)
        return;
    m_pressed = false;
    m_tracking = false;
    m_pointId = -1;
    setKeepMouseGrab(false);
    setKeepTouchGrab(false);
    emit pressedChanged();
    if (release)
        emit released();
    else
        emit canceled();
    setDelta(QPointF());
}

void KeelPageStackGestureArea::mouseReleaseEvent(QMouseEvent *event)
{
    if (!m_pressed) {
        event->ignore();
        return;
    }
    setDelta(mapFromScene(event->scenePosition()) - m_pressPos);
    finish(true);
    ungrabMouse();
}

void KeelPageStackGestureArea::mouseUngrabEvent()
{
    finish(false);
}

void KeelPageStackGestureArea::touchEvent(QTouchEvent *event)
{
    if (!m_pressed) {
        event->ignore();
        return;
    }
    for (const QEventPoint &point : event->points()) {
        if (point.id() != m_pointId)
            continue;
        setDelta(mapFromScene(point.scenePosition()) - m_pressPos);
        if (point.state() == QEventPoint::Released) {
            finish(true);
            ungrabTouchPoints();
        }
    }
    if (event->type() == QEvent::TouchCancel)
        finish(false);
    event->accept();
}

void KeelPageStackGestureArea::touchUngrabEvent()
{
    finish(false);
}
