// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see silicaitems.h.

#include "silicaitems.h"

#include "palette.h"

KeelSilicaStyle::KeelSilicaStyle(QQuickItem *owner)
    : m_palette(new KeelPalette(owner))
{
}

bool KeelSilicaStyle::highlighted() const
{
    return m_set ? m_value : m_palette->parentHighlighted();
}

bool KeelSilicaStyle::setHighlighted(bool highlighted)
{
    const bool old = this->highlighted();
    m_set = true;
    m_value = highlighted;
    return old != highlighted;
}

bool KeelSilicaStyle::resetHighlighted()
{
    const bool old = highlighted();
    m_set = false;
    return old != highlighted();
}

void KeelSilicaStyle::classBegin()
{
    m_palette->classBegin();
}

void KeelSilicaStyle::componentComplete()
{
    m_palette->componentComplete();
}

// The item's `highlighted` follows its Silica ancestor's until it is set.
template <typename Item>
static void followParentHighlight(Item *item, KeelPalette *palette, const KeelSilicaStyle *style)
{
    QObject::connect(palette, &KeelPalette::parentHighlightedChanged, item, [item, style] {
        if (style->followsParent())
            emit item->highlightedChanged();
    });
}

KeelSilicaItemBase::KeelSilicaItemBase(QQuickItem *parent)
    : QQuickItem(parent)
{
    followParentHighlight(this, m_style.palette(), &m_style);
}

void KeelSilicaItemBase::classBegin()
{
    QQuickItem::classBegin();
    m_style.classBegin();
}

void KeelSilicaItemBase::componentComplete()
{
    m_style.componentComplete();
    QQuickItem::componentComplete();
}

KeelSilicaMouseArea::KeelSilicaMouseArea(QQuickItem *parent)
    : QQuickMouseArea(parent)
{
    followParentHighlight(this, m_style.palette(), &m_style);
}

void KeelSilicaMouseArea::classBegin()
{
    QQuickMouseArea::classBegin();
    m_style.classBegin();
}

void KeelSilicaMouseArea::componentComplete()
{
    m_style.componentComplete();
    QQuickMouseArea::componentComplete();
}

KeelSilicaRectangle::KeelSilicaRectangle(QQuickItem *parent)
    : QQuickRectangle(parent)
{
    followParentHighlight(this, m_style.palette(), &m_style);
}

void KeelSilicaRectangle::classBegin()
{
    QQuickRectangle::classBegin();
    m_style.classBegin();
}

void KeelSilicaRectangle::componentComplete()
{
    m_style.componentComplete();
    QQuickRectangle::componentComplete();
}
