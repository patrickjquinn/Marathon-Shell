// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "buttonlayout.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QTimer>
#include <QtMath>

void KeelButtonLayoutAttached::setNewLine(bool v)
{
    if (v == m_newLine)
        return;
    m_newLine = v;
    emit newLineChanged();
    if (auto *item = qobject_cast<QQuickItem *>(parent()))
        if (auto *layout = qobject_cast<KeelButtonLayout *>(item->parentItem()))
            layout->relayout();
}

KeelButtonLayout::KeelButtonLayout(QQuickItem *parent)
    : QQuickItem(parent)
{
}

KeelButtonLayoutAttached *KeelButtonLayout::qmlAttachedProperties(QObject *object)
{
    return new KeelButtonLayoutAttached(object);
}

void KeelButtonLayout::setColumnSpacing(qreal v)
{
    if (qFuzzyCompare(v, m_columnSpacing))
        return;
    m_columnSpacing = v;
    emit columnSpacingChanged();
    scheduleRelayout();
}

void KeelButtonLayout::setRowSpacing(qreal v)
{
    if (qFuzzyCompare(v, m_rowSpacing))
        return;
    m_rowSpacing = v;
    emit rowSpacingChanged();
    scheduleRelayout();
}

void KeelButtonLayout::setPreferredWidth(qreal v)
{
    if (qFuzzyCompare(v, m_preferredWidth))
        return;
    m_preferredWidth = v;
    emit preferredWidthChanged();
    scheduleRelayout();
}

void KeelButtonLayout::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemChildAddedChange && data.item) {
        QQuickItem *child = data.item;
        connect(child, &QQuickItem::visibleChanged, this, &KeelButtonLayout::scheduleRelayout);
        connect(child, &QQuickItem::implicitWidthChanged, this, &KeelButtonLayout::scheduleRelayout);
        connect(child, &QQuickItem::implicitHeightChanged, this, &KeelButtonLayout::scheduleRelayout);
        scheduleRelayout();
    } else if (change == ItemChildRemovedChange && data.item) {
        disconnect(data.item, nullptr, this, nullptr);
        scheduleRelayout();
    }
    QQuickItem::itemChange(change, data);
}

void KeelButtonLayout::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!qFuzzyCompare(newGeometry.width(), oldGeometry.width()))
        scheduleRelayout();
}

// Unset properties default to Theme values, read in the context of the file
// that declares the layout (which imports Sailfish.Silica).
static qreal themeValue(QObject *scope, const char *expr, qreal fallback)
{
    QQmlContext *ctx = qmlContext(scope);
    if (!ctx)
        return fallback;
    QQmlExpression e(ctx, scope, QString::fromLatin1(expr));
    bool undefined = false;
    const QVariant v = e.evaluate(&undefined);
    return (!undefined && !e.hasError() && v.canConvert<qreal>()) ? v.toReal() : fallback;
}

void KeelButtonLayout::componentComplete()
{
    QQuickItem::componentComplete();
    if (m_columnSpacing < 0)
        setColumnSpacing(themeValue(this, "Theme.paddingMedium", 12));
    if (m_rowSpacing < 0)
        setRowSpacing(themeValue(this, "Theme.paddingMedium", 12));
    if (m_preferredWidth < 0)
        setPreferredWidth(themeValue(this, "Theme.buttonWidthSmall", 234));
    if (implicitWidth() <= 0 && parentItem())
        setImplicitWidth(parentItem()->width());
    relayout();
}

void KeelButtonLayout::scheduleRelayout()
{
    if (m_pending || !isComponentComplete())
        return;
    m_pending = true;
    QTimer::singleShot(0, this, [this]() {
        m_pending = false;
        relayout();
    });
}

static qreal itemPreferred(QQuickItem *item)
{
    const QVariant v = item->property("preferredWidth");
    return v.isValid() ? v.toReal() : 0;
}

static bool itemNewLine(QQuickItem *item)
{
    auto *a = qobject_cast<KeelButtonLayoutAttached *>(qmlAttachedPropertiesObject<KeelButtonLayout>(item, false));
    return a && a->newLine();
}

void KeelButtonLayout::relayout()
{
    if (m_inLayout)
        return;
    m_inLayout = true;
    const qreal colSpacing = qMax<qreal>(0, m_columnSpacing);
    const qreal rowSpacing = qMax<qreal>(0, m_rowSpacing);
    const qreal available = width() > 0 ? width() : implicitWidth();

    QList<QQuickItem *> items;
    const auto children = childItems();
    for (QQuickItem *c : children)
        if (c->isVisible())
            items.append(c);

    // Break into rows.
    QList<QList<QQuickItem *>> rows;
    QList<qreal> rowWidths;
    QList<QQuickItem *> row;
    qreal rowWidth = 0;
    for (QQuickItem *item : items) {
        const qreal w = qMax(qMax(item->implicitWidth(), itemPreferred(item)), m_preferredWidth);
        const qreal candidate = qMax(rowWidth, w);
        const bool fits = (row.size() + 1) * candidate + row.size() * colSpacing <= available + 0.5;
        if (!row.isEmpty() && (itemNewLine(item) || !fits)) {
            rows.append(row);
            rowWidths.append(rowWidth);
            row.clear();
            rowWidth = 0;
        }
        row.append(item);
        rowWidth = qMax(rowWidth, w);
    }
    if (!row.isEmpty()) {
        rows.append(row);
        rowWidths.append(rowWidth);
    }
    // Adjacent rows with the same number of buttons share one width.
    for (int i = 0; i < rows.size();) {
        int j = i;
        qreal w = 0;
        while (j < rows.size() && rows.at(j).size() == rows.at(i).size())
            w = qMax(w, rowWidths.at(j++));
        for (int k = i; k < j; ++k)
            rowWidths[k] = w;
        i = j;
    }

    qreal y = 0;
    qreal widest = 0;
    for (int r = 0; r < rows.size(); ++r) {
        const QList<QQuickItem *> &rr = rows.at(r);
        const qreal bw = qMin(rowWidths.at(r), available);
        const qreal total = rr.size() * bw + (rr.size() - 1) * colSpacing;
        widest = qMax(widest, total);
        qreal x = qMax<qreal>(0, (available - total) / 2);
        qreal rowHeight = 0;
        for (QQuickItem *item : rr) {
            item->setWidth(bw);
            item->setX(x);
            item->setY(y);
            x += bw + colSpacing;
            rowHeight = qMax(rowHeight, item->height() > 0 ? item->height() : item->implicitHeight());
        }
        y += rowHeight + (r + 1 < rows.size() ? rowSpacing : 0);
    }
    setImplicitHeight(y);
    setImplicitWidth(widest);
    m_inLayout = false;
}
