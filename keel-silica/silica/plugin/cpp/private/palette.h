// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Palette: the colour set of a Silica item (`palette` of SilicaItem,
// SilicaControl, SilicaMouseArea, Label, ...). Property names are from the
// public Silica documentation and from how Silica's BSD QML reads them
// (palette.highlightColor, palette.colorScheme, palette.backgroundGlowColor,
// ...). Clean-room implementation: a colour that is not set on a palette is
// inherited from the palette of the nearest Silica ancestor, else taken from
// the ambience (Keel.Ambience). When highlightColor or colorScheme is set on
// a palette, the colours derived from them (secondary highlight, highlight
// background, highlight dimmer; primary and secondary) are derived again with
// Keel.Ambience's functions unless set too. The derivation rules are Keel's.
//
// Keel's Silica item bases (SilicaItem, SilicaControl and the private
// SilicaMouseArea, SilicaText, ...) declare
//
//     readonly property bool __keel_silica_style: true
//     readonly property Palette palette: Palette {}
//     property bool highlighted: palette._parentHighlighted
//
// A palette created that way belongs to its parent item; the nearest visual
// ancestor that declares `__keel_silica_style` is its Silica ancestor, whose
// palette it inherits from and whose `highlighted` it reports as
// `_parentHighlighted` (Silica items are highlighted with their ancestor
// until they set `highlighted`).
#ifndef KEEL_PALETTE_H
#define KEEL_PALETTE_H

#include <QColor>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QQmlParserStatus>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;

class KeelPalette : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_NAMED_ELEMENT(Palette)
    Q_PROPERTY(bool _parentHighlighted READ parentHighlighted NOTIFY parentHighlightedChanged FINAL)

    Q_PROPERTY(int colorScheme READ colorScheme WRITE setColorScheme RESET resetColorScheme NOTIFY changed FINAL)
    Q_PROPERTY(QColor primaryColor READ primaryColor WRITE setPrimaryColor RESET resetPrimaryColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor secondaryColor READ secondaryColor WRITE setSecondaryColor RESET resetSecondaryColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor highlightColor READ highlightColor WRITE setHighlightColor RESET resetHighlightColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor secondaryHighlightColor READ secondaryHighlightColor WRITE setSecondaryHighlightColor RESET resetSecondaryHighlightColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor highlightBackgroundColor READ highlightBackgroundColor WRITE setHighlightBackgroundColor RESET resetHighlightBackgroundColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor highlightDimmerColor READ highlightDimmerColor WRITE setHighlightDimmerColor RESET resetHighlightDimmerColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor overlayBackgroundColor READ overlayBackgroundColor WRITE setOverlayBackgroundColor RESET resetOverlayBackgroundColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor backgroundGlowColor READ backgroundGlowColor WRITE setBackgroundGlowColor RESET resetBackgroundGlowColor NOTIFY changed FINAL)
    Q_PROPERTY(QColor errorColor READ errorColor WRITE setErrorColor RESET resetErrorColor NOTIFY changed FINAL)

public:
    enum Role {
        PrimaryColor,
        SecondaryColor,
        HighlightColor,
        SecondaryHighlightColor,
        HighlightBackgroundColor,
        HighlightDimmerColor,
        OverlayBackgroundColor,
        BackgroundGlowColor,
        ErrorColor,
        RoleCount
    };

    explicit KeelPalette(QObject *parent = nullptr);

    void classBegin() override;
    void componentComplete() override;
    bool parentHighlighted() const { return m_parentHighlighted; }

    // The palette this one inherits from (null: the ambience).
    void setParentPalette(KeelPalette *parent);
    KeelPalette *parentPalette() const { return m_parent; }
    // The engine whose Keel.Ambience provides the defaults.
    void setEngine(QQmlEngine *engine);

    int colorScheme() const;
    void setColorScheme(int scheme);
    void resetColorScheme();

    QColor color(Role role) const;
    void setColor(Role role, const QColor &color);
    void resetColor(Role role);

#define KEEL_PALETTE_ACCESSORS(name, Name, role)                                                   \
    QColor name() const { return color(role); }                                                    \
    void set##Name(const QColor &c) { setColor(role, c); }                                         \
    void reset##Name() { resetColor(role); }
    KEEL_PALETTE_ACCESSORS(primaryColor, PrimaryColor, PrimaryColor)
    KEEL_PALETTE_ACCESSORS(secondaryColor, SecondaryColor, SecondaryColor)
    KEEL_PALETTE_ACCESSORS(highlightColor, HighlightColor, HighlightColor)
    KEEL_PALETTE_ACCESSORS(secondaryHighlightColor, SecondaryHighlightColor, SecondaryHighlightColor)
    KEEL_PALETTE_ACCESSORS(highlightBackgroundColor, HighlightBackgroundColor, HighlightBackgroundColor)
    KEEL_PALETTE_ACCESSORS(highlightDimmerColor, HighlightDimmerColor, HighlightDimmerColor)
    KEEL_PALETTE_ACCESSORS(overlayBackgroundColor, OverlayBackgroundColor, OverlayBackgroundColor)
    KEEL_PALETTE_ACCESSORS(backgroundGlowColor, BackgroundGlowColor, BackgroundGlowColor)
    KEEL_PALETTE_ACCESSORS(errorColor, ErrorColor, ErrorColor)
#undef KEEL_PALETTE_ACCESSORS

signals:
    void changed();
    void parentHighlightedChanged();

private slots:
    void resolve();
    void readParentHighlighted();

private:
    QObject *ambience() const;
    QColor ambienceColor(Role role) const;
    int ambienceScheme() const;
    QColor derive(const char *function, const QColor &highlight, int scheme) const;
    // True when this palette re-derives colours of its own (an explicit
    // highlight colour or colour scheme) instead of inheriting them.
    bool derivesHighlight() const;
    bool derivesScheme() const;

    QPointer<QQuickItem> m_owner;
    QPointer<QQuickItem> m_silicaParent;
    QList<QMetaObject::Connection> m_chain;
    QMetaObject::Connection m_highlightConnection;
    bool m_parentHighlighted = false;
    QPointer<KeelPalette> m_parent;
    QPointer<QQmlEngine> m_engine;
    mutable QPointer<QObject> m_ambience;
    // The engine's shared ambience colours (palette.cpp).
    mutable QPointer<QObject> m_cache;
    // Set while completing: changes are announced once, if any.
    bool m_quiet = false;
    QMetaObject::Connection m_parentConnection;
    QMetaObject::Connection m_ambienceConnection;
    bool m_schemeSet = false;
    int m_scheme = 0;
    bool m_set[RoleCount] = {};
    QColor m_colors[RoleCount];
};

#endif // KEEL_PALETTE_H
