// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "pagedview.h"

#include <QtQml/qqml.h>

KeelPagedViewAttached::KeelPagedViewAttached(QObject *attachee)
    : QObject(attachee)
    , m_item(qobject_cast<QQuickItem *>(attachee))
{
    if (m_item) {
        connect(m_item, &QQuickItem::parentChanged, this, &KeelPagedViewAttached::findView);
        findView();
    }
}

QQuickItem *KeelPagedViewAttached::view() const
{
    return m_view;
}

qreal KeelPagedViewAttached::contentWidth() const
{
    return m_view ? m_view->contentWidth() : 0;
}

qreal KeelPagedViewAttached::contentHeight() const
{
    return m_view ? m_view->contentHeight() : 0;
}

void KeelPagedViewAttached::findView()
{
    if (m_explicit)
        return;
    KeelPagedViewBase *found = nullptr;
    for (QQuickItem *p = m_item ? m_item->parentItem() : nullptr; p && !found; p = p->parentItem())
        found = qobject_cast<KeelPagedViewBase *>(p);
    if (found != m_view) {
        if (m_view)
            disconnect(m_view, nullptr, this, nullptr);
        m_view = found;
        if (m_view)
            connect(m_view, &KeelPagedViewBase::contentSizeChanged, this, &KeelPagedViewAttached::contentSizeChanged);
        emit viewChanged();
        emit contentSizeChanged();
    }
}

void KeelPagedViewAttached::setView(KeelPagedViewBase *view)
{
    m_explicit = true;
    if (view == m_view)
        return;
    if (m_view)
        disconnect(m_view, nullptr, this, nullptr);
    m_view = view;
    if (m_view)
        connect(m_view, &KeelPagedViewBase::contentSizeChanged, this, &KeelPagedViewAttached::contentSizeChanged);
    emit viewChanged();
    emit contentSizeChanged();
}

void KeelPagedViewAttached::setState(bool current, bool exposed)
{
    if (current != m_current) {
        m_current = current;
        emit isCurrentItemChanged();
    }
    if (exposed != m_exposed) {
        m_exposed = exposed;
        emit exposedChanged();
    }
}

KeelPagedViewBase::KeelPagedViewBase(QQuickItem *parent)
    : QQuickItem(parent)
{
    setClip(true);
}

KeelPagedViewAttached *KeelPagedViewBase::qmlAttachedProperties(QObject *object)
{
    return new KeelPagedViewAttached(object);
}

void KeelPagedViewBase::setContentWidth(qreal width)
{
    if (qFuzzyCompare(width, m_contentWidth))
        return;
    m_contentWidth = width;
    emit contentSizeChanged();
}

void KeelPagedViewBase::setContentHeight(qreal height)
{
    if (qFuzzyCompare(height, m_contentHeight))
        return;
    m_contentHeight = height;
    emit contentSizeChanged();
}

void KeelPagedViewBase::_keelUpdate(QQuickItem *item, bool current, bool exposed)
{
    if (!item)
        return;
    auto *attached = qobject_cast<KeelPagedViewAttached *>(qmlAttachedPropertiesObject<KeelPagedViewBase>(item, true));
    if (!attached)
        return;
    attached->setView(this);
    attached->setState(current, exposed);
}
