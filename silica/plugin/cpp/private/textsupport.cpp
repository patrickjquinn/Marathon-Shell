// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see textsupport.h.

#include "textsupport.h"

#include <QTimer>

// --- ProxyValidator ----------------------------------------------------------

KeelProxyValidator::KeelProxyValidator(QObject *parent)
    : QValidator(parent)
{
}

void KeelProxyValidator::setValidator(QValidator *validator)
{
    if (validator == m_validator)
        return;
    if (m_validator)
        disconnect(m_validator, nullptr, this, nullptr);
    m_validator = validator;
    if (validator)
        connect(validator, &QValidator::changed, this, &QValidator::changed);
    emit validatorChanged();
    emit changed();
}

void KeelProxyValidator::setStrictValidation(bool strict)
{
    if (strict == m_strict)
        return;
    m_strict = strict;
    emit strictValidationChanged();
    emit changed();
}

QValidator::State KeelProxyValidator::validate(QString &input, int &pos) const
{
    if (!m_validator)
        return Acceptable;
    const State state = m_validator->validate(input, pos);
    if (state == Invalid && !m_strict)
        return Intermediate;
    return state;
}

void KeelProxyValidator::fixup(QString &input) const
{
    if (m_validator)
        m_validator->fixup(input);
}

// --- PreeditText -------------------------------------------------------------

KeelPreeditText::KeelPreeditText(QObject *parent)
    : QObject(parent)
{
}

// The editor is the parent.
void KeelPreeditText::classBegin()
{
    ensureConnected();
}

void KeelPreeditText::componentComplete()
{
    // Not connected before: bindings may have read a stale text.
    if (ensureConnected())
        emit textChanged();
}

// Returns true when it connected now.
bool KeelPreeditText::ensureConnected()
{
    QObject *e = editor();
    if (!e || m_connected == e)
        return false;
    if (m_connected)
        QObject::disconnect(m_connected, nullptr, this, nullptr);
    m_connected = e;
    m_last = text();
    const char *const signalNames[] = { SIGNAL(textChanged()), SIGNAL(preeditTextChanged()),
                                        SIGNAL(cursorPositionChanged()) };
    for (const char *signal : signalNames) {
        if (e->metaObject()->indexOfSignal(QMetaObject::normalizedSignature(signal + 1)) >= 0)
            QObject::connect(e, signal, this, SLOT(editorChanged()));
    }
    return true;
}

QString KeelPreeditText::text() const
{
    QObject *e = editor();
    if (!e)
        return QString();
    QString t = e->property("text").toString();
    const QString preedit = e->property("preeditText").toString();
    if (!preedit.isEmpty()) {
        const int cursor = qBound(0, e->property("cursorPosition").toInt(), static_cast<int>(t.size()));
        t.insert(cursor, preedit);
    }
    return t;
}

void KeelPreeditText::setText(const QString &text)
{
    if (QObject *e = editor()) {
        ensureConnected();
        if (e->property("text").toString() != text)
            e->setProperty("text", text);
    }
}

void KeelPreeditText::editorChanged()
{
    const QString t = text();
    if (t == m_last)
        return;
    m_last = t;
    emit textChanged();
}

// --- AutoScroll ----------------------------------------------------------------

KeelAutoScrollAttached::KeelAutoScrollAttached(QObject *attachee, Qt::Orientation orientation)
    : QObject(attachee)
    , m_item(qobject_cast<QQuickItem *>(attachee))
    , m_orientation(orientation)
{
    if (m_item) {
        connect(m_item, &QQuickItem::heightChanged, this, &KeelAutoScrollAttached::scheduleFixup);
        connect(m_item, &QQuickItem::widthChanged, this, &KeelAutoScrollAttached::scheduleFixup);
    }
}

void KeelAutoScrollAttached::setKeepVisible(bool keep)
{
    if (keep == m_keepVisible)
        return;
    m_keepVisible = keep;
    QQuickItem *flick = findFlickable();
    const char *prop = m_orientation == Qt::Vertical ? "contentY" : "contentX";
    if (flick && m_restore) {
        if (keep) {
            m_restoreFlickable = flick;
            m_restoreValue = flick->property(prop).toReal();
        } else if (m_restoreFlickable == flick) {
            flick->setProperty(prop, m_restoreValue);
            m_restoreFlickable = nullptr;
        }
    }
    emit keepVisibleChanged();
    scheduleFixup();
}

void KeelAutoScrollAttached::setCursorRectangle(const QVariant &rect)
{
    const bool set = rect.isValid() && !rect.isNull() && rect.canConvert<QRectF>();
    const QRectF r = set ? rect.toRectF() : QRectF();
    if (set == m_rectSet && r == m_rect)
        return;
    m_rectSet = set;
    m_rect = r;
    emit cursorRectangleChanged();
    scheduleFixup();
}

QQuickItem *KeelAutoScrollAttached::findFlickable() const
{
    for (QQuickItem *p = m_item ? m_item->parentItem() : nullptr; p; p = p->parentItem()) {
        if (p->inherits("QQuickFlickable"))
            return p;
    }
    return nullptr;
}

void KeelAutoScrollAttached::scheduleFixup()
{
    if (m_pending)
        return;
    m_pending = true;
    QTimer::singleShot(0, this, [this] {
        m_pending = false;
        fixup();
    });
}

void KeelAutoScrollAttached::fixup()
{
    if (!m_item || !m_rectSet || !m_keepVisible)
        return;
    QQuickItem *flick = findFlickable();
    if (!flick || !flick->isVisible())
        return;
    const bool vertical = m_orientation == Qt::Vertical;
    const QRectF r = m_item->mapRectToItem(flick, m_rect);
    const char *prop = vertical ? "contentY" : "contentX";
    const qreal pos = flick->property(prop).toReal();
    const qreal viewSize = vertical ? flick->height() : flick->width();
    const qreal lead = vertical ? m_margins[0] : m_margins[2];
    const qreal trail = vertical ? m_margins[1] : m_margins[3];
    const qreal start = vertical ? r.top() : r.left();
    const qreal end = vertical ? r.bottom() : r.right();

    qreal target = pos;
    if (end > viewSize - trail)
        target = pos + end - (viewSize - trail);
    if (start - (target - pos) < lead)
        target = pos + start - lead;

    const qreal origin = flick->property(vertical ? "originY" : "originX").toReal();
    const qreal content = flick->property(vertical ? "contentHeight" : "contentWidth").toReal();
    const qreal minPos = origin - flick->property(vertical ? "topMargin" : "leftMargin").toReal();
    const qreal maxPos = origin + content + flick->property(vertical ? "bottomMargin" : "rightMargin").toReal()
                         - viewSize;
    target = qBound(minPos, target, qMax(minPos, maxPos));
    if (qAbs(target - pos) < 0.5)
        return;
    if (m_animated) {
        if (!m_animation)
            m_animation = new QPropertyAnimation(this);
        m_animation->stop();
        m_animation->setTargetObject(flick);
        m_animation->setPropertyName(prop);
        m_animation->setStartValue(pos);
        m_animation->setEndValue(target);
        m_animation->setDuration(150);
        m_animation->setEasingCurve(QEasingCurve::InOutQuad);
        m_animation->start();
    } else {
        flick->setProperty(prop, target);
    }
}
