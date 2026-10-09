// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The native bases of Silica's items (Sailfish.Silica.private): a Qt Quick
// type with the SilicaItem `highlighted` and `palette` (palette.h), Keel's
// stand-ins for Silica's own native types. Names and API inferred from
// Silica's BSD QML:
//
//   SilicaItemBase    Item       (Keel's name; Sailfish.Silica's SilicaItem
//                                 and SilicaControl derive from it)
//   SilicaMouseArea   MouseArea  (BackgroundItem, Button, Page, ...)
//   SilicaRectangle   Rectangle
//
// Each has
//   __keel_silica_style   true (palette.h: marks a Silica item)
//   highlighted           the Silica ancestor's, until set
//   palette               the item's own Palette
//
// Native rather than QML (they were qml/SilicaItem.qml,
// qml/private/SilicaMouseArea.qml and SilicaRectangle.qml): they are in
// every list row and button, and each QML one added a component layer, a
// binding and a palette made by the QML engine.
#ifndef KEEL_SILICAITEMS_H
#define KEEL_SILICAITEMS_H

#include <QtQuick/private/qquickmousearea_p.h>
#include <QtQuick/private/qquickrectangle_p.h>

#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class KeelPalette;

// What the item bases share: the palette, and `highlighted` following the
// palette's Silica ancestor until set.
class KeelSilicaStyle
{
public:
    explicit KeelSilicaStyle(QQuickItem *owner);

    KeelPalette *palette() const { return m_palette; }
    bool highlighted() const;
    // These return whether highlighted() changed.
    bool setHighlighted(bool highlighted);
    bool resetHighlighted();
    // The parent's highlight changed: does highlighted() follow it?
    bool followsParent() const { return !m_set; }

    void classBegin();
    void componentComplete();

private:
    KeelPalette *m_palette;
    bool m_set = false;
    bool m_value = false;
};

#define KEEL_SILICA_STYLE_ACCESSORS(Class)                                                         \
public:                                                                                            \
    bool silicaStyle() const { return true; }                                                      \
    bool highlighted() const { return m_style.highlighted(); }                                     \
    void setHighlighted(bool h)                                                                    \
    {                                                                                              \
        if (m_style.setHighlighted(h))                                                             \
            emit highlightedChanged();                                                             \
    }                                                                                              \
    void resetHighlighted()                                                                        \
    {                                                                                              \
        if (m_style.resetHighlighted())                                                            \
            emit highlightedChanged();                                                             \
    }                                                                                              \
    KeelPalette *silicaPalette() const { return m_style.palette(); }                               \
                                                                                                   \
private:                                                                                           \
    KeelSilicaStyle m_style{this};

class KeelSilicaItemBase : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(SilicaItemBase)
    Q_PROPERTY(bool __keel_silica_style READ silicaStyle CONSTANT FINAL)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted RESET resetHighlighted
                       NOTIFY highlightedChanged FINAL)
    Q_PROPERTY(KeelPalette *palette READ silicaPalette CONSTANT FINAL)
    KEEL_SILICA_STYLE_ACCESSORS(KeelSilicaItemBase)

public:
    explicit KeelSilicaItemBase(QQuickItem *parent = nullptr);

signals:
    void highlightedChanged();

protected:
    void classBegin() override;
    void componentComplete() override;
};

class KeelSilicaMouseArea : public QQuickMouseArea
{
    Q_OBJECT
    QML_NAMED_ELEMENT(SilicaMouseArea)
    Q_PROPERTY(bool __keel_silica_style READ silicaStyle CONSTANT FINAL)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted RESET resetHighlighted
                       NOTIFY highlightedChanged FINAL)
    Q_PROPERTY(KeelPalette *palette READ silicaPalette CONSTANT FINAL)
    KEEL_SILICA_STYLE_ACCESSORS(KeelSilicaMouseArea)

public:
    explicit KeelSilicaMouseArea(QQuickItem *parent = nullptr);

signals:
    void highlightedChanged();

protected:
    void classBegin() override;
    void componentComplete() override;
};

class KeelSilicaRectangle : public QQuickRectangle
{
    Q_OBJECT
    QML_NAMED_ELEMENT(SilicaRectangle)
    Q_PROPERTY(bool __keel_silica_style READ silicaStyle CONSTANT FINAL)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted RESET resetHighlighted
                       NOTIFY highlightedChanged FINAL)
    Q_PROPERTY(KeelPalette *palette READ silicaPalette CONSTANT FINAL)
    KEEL_SILICA_STYLE_ACCESSORS(KeelSilicaRectangle)

public:
    explicit KeelSilicaRectangle(QQuickItem *parent = nullptr);

signals:
    void highlightedChanged();

protected:
    void classBegin() override;
    void componentComplete() override;
};

#endif // KEEL_SILICAITEMS_H
