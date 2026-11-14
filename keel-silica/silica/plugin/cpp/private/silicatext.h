// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// SilicaText (Sailfish.Silica.private): Text with the SilicaItem
// `highlighted` and `palette`, the base of Label and LinkedLabel. Keel's
// stand-in; API inferred from Silica's BSD Label.qml and LinkedLabel.qml:
//
//   __keel_silica_style    true (palette.h: marks a Silica item)
//   highlighted            the Silica ancestor's, until set
//   palette                this item's Palette (palette.h)
//   _defaultLabelFormat    the window's _defaultLabelFormat
//                          (__silica_applicationwindow_instance), else
//                          Text.AutoText
//
// and, as defaults an app may override, font.family from Theme.fontFamily
// and linkColor from palette.highlightColor.
//
// Native rather than QML (it was qml/private/SilicaText.qml): every Label is
// one, a page has dozens, and the QML version added a component layer, a
// script binding and two property bindings to each.
#ifndef KEEL_SILICATEXT_H
#define KEEL_SILICATEXT_H

#include <QtQuick/private/qquicktext_p.h>

#include <QMetaObject>
#include <QPointer>
#include <QtQml/qqmlregistration.h>

class KeelPalette;

class KeelSilicaText : public QQuickText
{
    Q_OBJECT
    QML_NAMED_ELEMENT(SilicaText)
    Q_PROPERTY(bool __keel_silica_style READ silicaStyle CONSTANT FINAL)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted RESET resetHighlighted
                       NOTIFY highlightedChanged FINAL)
    Q_PROPERTY(KeelPalette *palette READ silicaPalette CONSTANT FINAL)
    Q_PROPERTY(int _defaultLabelFormat READ defaultLabelFormat NOTIFY defaultLabelFormatChanged FINAL)

public:
    explicit KeelSilicaText(QQuickItem *parent = nullptr);

    bool silicaStyle() const { return true; }
    bool highlighted() const;
    void setHighlighted(bool highlighted);
    void resetHighlighted();
    KeelPalette *silicaPalette() const { return m_palette; }
    int defaultLabelFormat() const { return m_defaultLabelFormat; }

signals:
    void highlightedChanged();
    void defaultLabelFormatChanged();

protected:
    void classBegin() override;
    void componentComplete() override;

private Q_SLOTS:
    void followThemeFont();
    void readDefaultLabelFormat();

private:
    void followPalette();

    KeelPalette *m_palette;
    bool m_highlightedSet = false;
    bool m_highlighted = false;
    // The defaults this item last applied: replaced on a change only while
    // the app has not set a value of its own.
    QString m_themeFamily;
    QColor m_paletteLinkColor;
    QPointer<QObject> m_theme;
    QPointer<QObject> m_window;
    QMetaObject::Connection m_windowConnection;
    int m_defaultLabelFormat = QQuickText::AutoText;
};

#endif // KEEL_SILICATEXT_H
