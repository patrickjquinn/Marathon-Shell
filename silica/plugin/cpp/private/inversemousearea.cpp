// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see inversemousearea.h.

#include "inversemousearea.h"

#include <QGuiApplication>
#include <QMouseEvent>
#include <QStyleHints>
#include <QTimer>
#include <QTouchEvent>

KeelInverseMouseArea::KeelInverseMouseArea(QQuickItem *parent)
    : QQuickItem(parent)
{
    connect(this, &QQuickItem::enabledChanged, this, &KeelInverseMouseArea::updateFilter);
    connect(this, &QQuickItem::visibleChanged, this, &KeelInverseMouseArea::updateFilter);
}

KeelInverseMouseArea::~KeelInverseMouseArea()
{
    if (m_window)
        m_window->removeEventFilter(this);
}

void KeelInverseMouseArea::setStealPress(bool steal)
{
    if (steal == m_stealPress)
        return;
    m_stealPress = steal;
    emit stealPressChanged();
}

void KeelInverseMouseArea::itemChange(ItemChange change, const ItemChangeData &data)
{
    QQuickItem::itemChange(change, data);
    if (change == ItemSceneChange)
        updateFilter();
}

void KeelInverseMouseArea::updateFilter()
{
    QQuickWindow *w = (isEnabled() && isVisible()) ? window() : nullptr;
    if (w == m_window)
        return;
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = w;
    if (m_window)
        m_window->installEventFilter(this);
    if (!m_window) {
        m_stealing = false;
        setPressed(false);
    }
}

void KeelInverseMouseArea::setPressed(bool pressed)
{
    if (pressed == m_pressed)
        return;
    m_pressed = pressed;
    emit pressedChanged();
}

bool KeelInverseMouseArea::outside(const QPointF &scenePos) const
{
    const QPointF p = mapFromScene(scenePos);
    return !QRectF(0, 0, width(), height()).contains(p);
}

void KeelInverseMouseArea::cancelTouch()
{
    m_cancel = true;
    // The press is delivered after the signal returns: take it away then.
    QPointer<QQuickWindow> w = m_window;
    QTimer::singleShot(0, this, [this, w] {
        if (!m_cancel || !w)
            return;
        m_cancel = false;
        if (QQuickItem *grabber = w->mouseGrabberItem())
            grabber->ungrabMouse();
    });
}

bool KeelInverseMouseArea::handlePress(const QPointF &scenePos)
{
    if (!outside(scenePos))
        return false;
    m_pressPos = scenePos;
    setPressed(true);
    m_stealing = m_stealPress;
    emit pressedOutside();
    return m_stealing;
}

bool KeelInverseMouseArea::handleRelease(const QPointF &scenePos)
{
    if (!m_pressed)
        return false;
    const bool stolen = m_stealing;
    m_stealing = false;
    setPressed(false);
    const qreal threshold = QGuiApplication::styleHints()->startDragDistance();
    if (outside(scenePos) && (scenePos - m_pressPos).manhattanLength() < 2 * threshold)
        emit clickedOutside();
    return stolen;
}

bool KeelInverseMouseArea::eventFilter(QObject *watched, QEvent *event)
{
    if (watched != m_window)
        return false;
    switch (event->type()) {
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonDblClick:
        return handlePress(static_cast<QMouseEvent *>(event)->scenePosition());
    case QEvent::MouseMove:
        return m_stealing;
    case QEvent::MouseButtonRelease:
        return handleRelease(static_cast<QMouseEvent *>(event)->scenePosition());
    case QEvent::TouchBegin: {
        auto *te = static_cast<QTouchEvent *>(event);
        return !te->points().isEmpty() && handlePress(te->points().first().scenePosition());
    }
    case QEvent::TouchUpdate:
        return m_stealing;
    case QEvent::TouchEnd: {
        auto *te = static_cast<QTouchEvent *>(event);
        return !te->points().isEmpty() && handleRelease(te->points().first().scenePosition());
    }
    case QEvent::TouchCancel:
        m_stealing = false;
        setPressed(false);
        return false;
    default:
        return false;
    }
}
