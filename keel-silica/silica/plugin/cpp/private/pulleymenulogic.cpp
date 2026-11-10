// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see pulleymenulogic.h.

#include "pulleymenulogic.h"
#include "keeltheme.h"

#include <QMouseEvent>
#include <QQuickWindow>
#include <QTouchEvent>
#include <QtMath>

KeelPulleyMenuLogic::KeelPulleyMenuLogic(QObject *parent)
    : QObject(parent)
{
}

void KeelPulleyMenuLogic::setFlickable(QQuickItem *flickable)
{
    if (flickable == m_flickable)
        return;
    for (const auto &c : std::as_const(m_connections))
        disconnect(c);
    m_connections.clear();
    m_flickable = flickable;
    if (flickable) {
        m_connections << connect(flickable, SIGNAL(contentYChanged()), this, SLOT(update()));
        m_connections << connect(flickable, SIGNAL(movingChanged()), this, SLOT(update()));
        m_connections << connect(flickable, SIGNAL(draggingChanged()), this, SLOT(draggingChanged()));
    }
    emit flickableChanged();
    update();
}

void KeelPulleyMenuLogic::setPullDownType(bool pullDown)
{
    if (pullDown == m_pullDown)
        return;
    m_pullDown = pullDown;
    emit pullDownTypeChanged();
    update();
}

qreal KeelPulleyMenuLogic::menuReal(const char *name) const
{
    return menu() ? menu()->property(name).toReal() : 0;
}

qreal KeelPulleyMenuLogic::contentY() const
{
    return m_flickable ? m_flickable->property("contentY").toReal() : 0;
}

void KeelPulleyMenuLogic::setActive(bool active)
{
    if (menu() && menu()->property("active").toBool() != active)
        menu()->setProperty("active", active);
}

bool KeelPulleyMenuLogic::outOfBounds() const
{
    if (!m_flickable)
        return false;
    const qreal y = contentY();
    const qreal finalPos = menuReal("_finalPosition");
    return m_pullDown ? y < finalPos - 0.5 : y > finalPos + 0.5;
}

void KeelPulleyMenuLogic::draggingChanged()
{
    if (m_flickable && m_flickable->property("dragging").toBool())
        m_permitted = menu() && menu()->property("_activationPermitted").toBool();
    update();
}

void KeelPulleyMenuLogic::update()
{
    if (!m_flickable || !menu())
        return;
    const qreal y = contentY();
    const qreal inactive = menuReal("_inactivePosition");
    const qreal d = qMax<qreal>(0.0, m_pullDown ? inactive - y : y - inactive);
    if (!qFuzzyCompare(d + 1, m_dragDistance + 1)) {
        m_dragDistance = d;
        emit dragDistanceChanged();
    }

    const bool dragging = m_flickable->property("dragging").toBool();
    const bool moving = m_flickable->property("moving").toBool();
    const bool active = menu()->property("active").toBool();
    if (!active && dragging && m_permitted && d > 0.5)
        setActive(true);
    else if (active && d < 0.5 && !dragging && !moving)
        setActive(false);

    const qreal finalPos = menuReal("_finalPosition");
    const bool atFinal = menu()->property("active").toBool()
                         && (m_pullDown ? y <= finalPos + 0.5 : y >= finalPos - 0.5);
    if (atFinal && !m_atFinal && dragging)
        emit finalPositionReached();
    m_atFinal = atFinal;
}

void KeelPulleyMenuLogic::monitorFlick()
{
    if (!m_flickable || !menu() || menu()->property("active").toBool())
        return;
    const qreal v = m_flickable->property("verticalVelocity").toReal();
    const qreal decel = qMax<qreal>(1.0, m_flickable->property("flickDeceleration").toReal());
    const qreal y = contentY();
    const qreal inactive = menuReal("_inactivePosition");
    const bool towards = m_pullDown ? v < 0 : v > 0;
    if (!towards)
        return;
    const qreal distance = qAbs(m_pullDown ? y - inactive : inactive - y);
    const qreal travel = v * v / (2 * decel);
    if (travel > distance && distance > 0) {
        // Time to cover `distance` while decelerating from |v|.
        const qreal speed = qAbs(v);
        const qreal disc = qMax<qreal>(0.0, speed * speed - 2 * decel * distance);
        const qreal t = (speed - qSqrt(disc)) / decel;
        emit animateFlick(qMax<qreal>(0.05, t), inactive);
    }
}

// ---------------------------------------------------------------------------

KeelBounceEffect::KeelBounceEffect(QObject *parent)
    : QObject(parent)
{
}

KeelBounceEffect::~KeelBounceEffect()
{
    if (m_window)
        m_window->removeEventFilter(this);
}

void KeelBounceEffect::setFlickable(QQuickItem *flickable)
{
    if (flickable == m_flickable)
        return;
    if (m_flickable)
        disconnect(m_flickable, nullptr, this, nullptr);
    m_flickable = flickable;
    if (flickable)
        connect(flickable, &QQuickItem::windowChanged, this, &KeelBounceEffect::watchWindow);
    watchWindow();
    emit flickableChanged();
}

void KeelBounceEffect::watchWindow()
{
    QQuickWindow *w = m_flickable ? m_flickable->window() : nullptr;
    if (w == m_window)
        return;
    if (m_window)
        m_window->removeEventFilter(this);
    m_window = w;
    if (m_window)
        m_window->installEventFilter(this);
}

void KeelBounceEffect::setDifference(qreal difference)
{
    const bool wasActive = active();
    if (qFuzzyCompare(difference + 1, m_difference + 1))
        return;
    m_difference = difference;
    emit differenceChanged();
    if (wasActive != active())
        emit activeChanged();
}

// The flickable stops at its bounds; the effect measures how far the
// pointer keeps going past the point where the bound was reached.
void KeelBounceEffect::track(const QPointF &scenePos)
{
    // Only views that stop at their bounds bounce; with DragOverBounds (a
    // pulley menu can open) the content itself follows the pointer.
    if (!m_flickable || !m_flickable->property("interactive").toBool()
        || m_flickable->property("boundsBehavior").toInt() != 0)
        return;
    const QPointF local = m_flickable->mapFromScene(scenePos);
    const qreal y = m_flickable->property("contentY").toReal();
    const qreal originY = m_flickable->property("originY").toReal();
    const qreal top = originY - m_flickable->property("topMargin").toReal();
    const qreal bottom = originY + m_flickable->property("contentHeight").toReal()
                         + m_flickable->property("bottomMargin").toReal() - m_flickable->height();
    const int edge = y <= top + 0.5 ? -1 : (y >= qMax(top, bottom) - 0.5 ? 1 : 0);
    if (edge == 0) {
        m_hasEdge = false;
        setDifference(0);
        return;
    }
    if (!m_hasEdge || edge != m_edge) {
        m_hasEdge = true;
        m_edge = edge;
        m_edgeY = local.y();
    }
    const qreal past = edge < 0 ? local.y() - m_edgeY : m_edgeY - local.y();
    if (past < 0)
        m_edgeY = local.y();
    setDifference(qMax<qreal>(0.0, past));
}

bool KeelBounceEffect::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched)
    if (!m_flickable)
        return false;
    QPointF pos;
    switch (event->type()) {
    case QEvent::MouseButtonPress: {
        pos = static_cast<QMouseEvent *>(event)->scenePosition();
        const QPointF local = m_flickable->mapFromScene(pos);
        m_pressed = m_flickable->isVisible() && m_flickable->contains(local);
        m_hasEdge = false;
        return false;
    }
    case QEvent::MouseMove:
        if (m_pressed)
            track(static_cast<QMouseEvent *>(event)->scenePosition());
        return false;
    case QEvent::MouseButtonRelease:
    case QEvent::TouchEnd:
    case QEvent::TouchCancel:
    case QEvent::UngrabMouse:
        m_pressed = false;
        m_hasEdge = false;
        setDifference(0);
        return false;
    default:
        return false;
    }
}
