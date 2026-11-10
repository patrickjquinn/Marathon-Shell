// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see dragfilter.h.

#include "dragfilter.h"
#include "keeltheme.h"

#include <QGuiApplication>
#include <QMouseEvent>
#include <QStyleHints>
#include <QTouchEvent>

KeelDragFilterAttached::KeelDragFilterAttached(QObject *attachee)
    : QObject(attachee)
    , m_item(qobject_cast<QQuickItem *>(attachee))
{
}

void KeelDragFilterAttached::setScreenMargin(qreal margin)
{
    if (qFuzzyCompare(margin, m_screenMargin))
        return;
    m_screenMargin = margin;
    emit screenMarginChanged();
}

void KeelDragFilterAttached::setOrientations(int orientations)
{
    if (orientations == m_orientations)
        return;
    m_orientations = orientations;
    emit orientationsChanged();
}

void KeelDragFilterAttached::setCanceled(bool canceled)
{
    if (canceled == m_canceled)
        return;
    m_canceled = canceled;
    emit canceledChanged();
}

void KeelDragFilterAttached::begin(qreal x, qreal y)
{
    end();
    if (!m_item || !m_item->window())
        return;
    m_window = m_item->window();
    m_start = m_item->mapToScene(QPointF(x, y));
    m_edge = m_screenMargin > 0
             && (m_start.x() < m_screenMargin || m_start.x() > m_window->width() - m_screenMargin);
    m_active = true;
    m_window->installEventFilter(this);
}

void KeelDragFilterAttached::end()
{
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = nullptr;
    m_active = false;
    setCanceled(false);
}

void KeelDragFilterAttached::move(const QPointF &scenePos)
{
    if (!m_active || m_canceled)
        return;
    qreal threshold = keel::themeValue(m_item, "startDragDistance",
                                       QGuiApplication::styleHints()->startDragDistance());
    if (m_edge)
        threshold /= 2;
    const QPointF d = scenePos - m_start;
    if (((m_orientations & Qt::Horizontal) && qAbs(d.x()) > threshold)
        || ((m_orientations & Qt::Vertical) && qAbs(d.y()) > threshold))
        setCanceled(true);
}

bool KeelDragFilterAttached::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched)
    switch (event->type()) {
    case QEvent::MouseMove:
        move(static_cast<QMouseEvent *>(event)->scenePosition());
        break;
    case QEvent::TouchUpdate: {
        auto *te = static_cast<QTouchEvent *>(event);
        if (!te->points().isEmpty())
            move(te->points().first().scenePosition());
        break;
    }
    case QEvent::MouseButtonRelease:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel:
        // Stop watching; `canceled` resets with the next begin().
        if (m_window)
            m_window->removeEventFilter(this);
        m_window = nullptr;
        m_active = false;
        break;
    default:
        break;
    }
    return false;
}
