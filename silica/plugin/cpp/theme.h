// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Theme singleton of Sailfish.Silica, in C++ (it was qml/Theme.qml). API
// (names, types, methods) from the Silica public documentation;
// implementation clean-room, values unchanged from the QML version.
// Colours come from Keel.Ambience (Rust, plugin/src/ambience.rs), which
// resolves keel-shell's forwarded ambience, KEEL_THEME_* overrides and Keel's
// dark default. Sizes are base values at pixelRatio 1.0 scaled by pixelRatio,
// except the page margin and the button widths, which follow the screen
// width; at pixelRatio 1.5 (the Jolla Phone's z1.5 theme) Silica's own values
// read on the phone. The measurements are in keel/silica/tests/screenshots/
// reference/SOURCES.md.
//
// In C++ because every Silica component reads it: its helpers (rgba() alone
// about 58 times per page) ran as JavaScript in the QML version, and typed
// C++ properties let qmlcachegen compile the bindings that read them.
#ifndef KEEL_THEME_H
#define KEEL_THEME_H

#include <cmath>

#include <QColor>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QString>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;
class QScreen;

class KeelTheme : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Theme)
    QML_SINGLETON

    // Ambience colours
    Q_PROPERTY(int colorScheme READ colorScheme NOTIFY colorSchemeChanged FINAL)
    Q_PROPERTY(QColor highlightColor READ highlightColor NOTIFY highlightColorChanged FINAL)
    Q_PROPERTY(QColor primaryColor READ primaryColor NOTIFY primaryColorChanged FINAL)
    Q_PROPERTY(QColor secondaryColor READ secondaryColor NOTIFY secondaryColorChanged FINAL)
    Q_PROPERTY(QColor secondaryHighlightColor READ secondaryHighlightColor NOTIFY secondaryHighlightColorChanged FINAL)
    Q_PROPERTY(QColor highlightBackgroundColor READ highlightBackgroundColor NOTIFY highlightBackgroundColorChanged FINAL)
    Q_PROPERTY(QColor highlightDimmerColor READ highlightDimmerColor NOTIFY highlightDimmerColorChanged FINAL)
    Q_PROPERTY(QColor overlayBackgroundColor READ overlayBackgroundColor NOTIFY overlayBackgroundColorChanged FINAL)
    Q_PROPERTY(QColor errorColor READ errorColor NOTIFY errorColorChanged FINAL)
    // Documented as "color" but used as an opacity (see the Theme docs example).
    Q_PROPERTY(qreal highlightBackgroundOpacity READ highlightBackgroundOpacity NOTIFY highlightBackgroundOpacityChanged FINAL)
    Q_PROPERTY(QColor lightPrimaryColor READ lightPrimaryColor CONSTANT FINAL)
    // Measured on the Jolla Phone (Sailfish OS 5, dark and light ambiences):
    // opaque, not white at opacityHigh.
    Q_PROPERTY(QColor lightSecondaryColor READ lightSecondaryColor CONSTANT FINAL)
    Q_PROPERTY(QColor darkPrimaryColor READ darkPrimaryColor CONSTANT FINAL)
    Q_PROPERTY(QColor darkSecondaryColor READ darkSecondaryColor CONSTANT FINAL)

    // Fonts
    Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY fontFamilyChanged FINAL)
    Q_PROPERTY(QString fontFamilyHeading READ fontFamilyHeading NOTIFY fontFamilyHeadingChanged FINAL)
    // User font-size scaling is not forwarded yet; the *Base values equal the
    // scaled ones until it is.
    Q_PROPERTY(qreal _fontScale READ fontScale CONSTANT FINAL)
    Q_PROPERTY(int fontSizeTinyBase READ fontSizeTinyBase NOTIFY fontSizeTinyBaseChanged FINAL)
    Q_PROPERTY(int fontSizeExtraSmallBase READ fontSizeExtraSmallBase NOTIFY fontSizeExtraSmallBaseChanged FINAL)
    Q_PROPERTY(int fontSizeSmallBase READ fontSizeSmallBase NOTIFY fontSizeSmallBaseChanged FINAL)
    Q_PROPERTY(int fontSizeMediumBase READ fontSizeMediumBase NOTIFY fontSizeMediumBaseChanged FINAL)
    Q_PROPERTY(int fontSizeLargeBase READ fontSizeLargeBase NOTIFY fontSizeLargeBaseChanged FINAL)
    Q_PROPERTY(int fontSizeExtraLargeBase READ fontSizeExtraLargeBase NOTIFY fontSizeExtraLargeBaseChanged FINAL)
    Q_PROPERTY(int fontSizeHugeBase READ fontSizeHugeBase NOTIFY fontSizeHugeBaseChanged FINAL)
    Q_PROPERTY(int fontSizeTiny READ fontSizeTinyBase NOTIFY fontSizeTinyChanged FINAL)
    Q_PROPERTY(int fontSizeExtraSmall READ fontSizeExtraSmallBase NOTIFY fontSizeExtraSmallChanged FINAL)
    Q_PROPERTY(int fontSizeSmall READ fontSizeSmallBase NOTIFY fontSizeSmallChanged FINAL)
    Q_PROPERTY(int fontSizeMedium READ fontSizeMediumBase NOTIFY fontSizeMediumChanged FINAL)
    Q_PROPERTY(int fontSizeLarge READ fontSizeLargeBase NOTIFY fontSizeLargeChanged FINAL)
    Q_PROPERTY(int fontSizeExtraLarge READ fontSizeExtraLargeBase NOTIFY fontSizeExtraLargeChanged FINAL)
    Q_PROPERTY(int fontSizeHuge READ fontSizeHugeBase NOTIFY fontSizeHugeChanged FINAL)

    // Geometry
    Q_PROPERTY(qreal pixelRatio READ pixelRatio NOTIFY pixelRatioChanged FINAL)
    Q_PROPERTY(qreal paddingSmall READ paddingSmall NOTIFY paddingSmallChanged FINAL)
    Q_PROPERTY(qreal paddingMedium READ paddingMedium NOTIFY paddingMediumChanged FINAL)
    Q_PROPERTY(qreal paddingLarge READ paddingLarge NOTIFY paddingLargeChanged FINAL)
    Q_PROPERTY(bool _phoneScreen READ phoneScreen NOTIFY _phoneScreenChanged FINAL)
    Q_PROPERTY(qreal _widthScale READ widthScale NOTIFY _widthScaleChanged FINAL)
    Q_PROPERTY(qreal horizontalPageMargin READ horizontalPageMargin NOTIFY horizontalPageMarginChanged FINAL)
    Q_PROPERTY(qreal itemSizeExtraSmall READ itemSizeExtraSmall NOTIFY itemSizeExtraSmallChanged FINAL)
    Q_PROPERTY(qreal itemSizeSmall READ itemSizeSmall NOTIFY itemSizeSmallChanged FINAL)
    Q_PROPERTY(qreal itemSizeMedium READ itemSizeMedium NOTIFY itemSizeMediumChanged FINAL)
    Q_PROPERTY(qreal itemSizeLarge READ itemSizeLarge NOTIFY itemSizeLargeChanged FINAL)
    Q_PROPERTY(qreal itemSizeExtraLarge READ itemSizeExtraLarge NOTIFY itemSizeExtraLargeChanged FINAL)
    Q_PROPERTY(qreal itemSizeHuge READ itemSizeHuge NOTIFY itemSizeHugeChanged FINAL)
    Q_PROPERTY(qreal iconSizeExtraSmall READ iconSizeExtraSmall NOTIFY iconSizeExtraSmallChanged FINAL)
    Q_PROPERTY(qreal iconSizeSmall READ iconSizeSmall NOTIFY iconSizeSmallChanged FINAL)
    Q_PROPERTY(qreal iconSizeSmallPlus READ iconSizeSmallPlus NOTIFY iconSizeSmallPlusChanged FINAL)
    Q_PROPERTY(qreal iconSizeMedium READ iconSizeMedium NOTIFY iconSizeMediumChanged FINAL)
    Q_PROPERTY(qreal iconSizeLarge READ iconSizeLarge NOTIFY iconSizeLargeChanged FINAL)
    Q_PROPERTY(qreal iconSizeExtraLarge READ iconSizeExtraLarge NOTIFY iconSizeExtraLargeChanged FINAL)
    Q_PROPERTY(qreal iconSizeLauncher READ iconSizeLauncher NOTIFY iconSizeLauncherChanged FINAL)
    // Follow the screen width on phones, like the page margin (measured: a
    // default Button is 316 px wide on a Jolla C2, 473 px on an Xperia XA2).
    Q_PROPERTY(qreal buttonWidthTiny READ buttonWidthTiny NOTIFY buttonWidthTinyChanged FINAL)
    Q_PROPERTY(qreal buttonWidthExtraSmall READ buttonWidthExtraSmall NOTIFY buttonWidthExtraSmallChanged FINAL)
    Q_PROPERTY(qreal buttonWidthSmall READ buttonWidthSmall NOTIFY buttonWidthSmallChanged FINAL)
    Q_PROPERTY(qreal buttonWidthMedium READ buttonWidthMedium NOTIFY buttonWidthMediumChanged FINAL)
    Q_PROPERTY(qreal buttonWidthLarge READ buttonWidthLarge NOTIFY buttonWidthLargeChanged FINAL)
    Q_PROPERTY(QSize coverSizeLarge READ coverSizeLarge NOTIFY coverSizeLargeChanged FINAL)
    Q_PROPERTY(QSize coverSizeSmall READ coverSizeSmall NOTIFY coverSizeSmallChanged FINAL)

    // Interaction
    Q_PROPERTY(qreal flickDeceleration READ flickDeceleration NOTIFY flickDecelerationChanged FINAL)
    Q_PROPERTY(qreal maximumFlickVelocity READ maximumFlickVelocity NOTIFY maximumFlickVelocityChanged FINAL)
    Q_PROPERTY(int startDragDistance READ startDragDistance NOTIFY startDragDistanceChanged FINAL)
    // Used by Silica's BSD QML (names from that QML; values are Keel's).
    Q_PROPERTY(int minimumPressHighlightTime READ minimumPressHighlightTime CONSTANT FINAL)
    Q_PROPERTY(qreal pageStackIndicatorWidth READ pageStackIndicatorWidth NOTIFY pageStackIndicatorWidthChanged FINAL)
    Q_PROPERTY(qreal _lineWidth READ lineWidth NOTIFY _lineWidthChanged FINAL)

    Q_PROPERTY(qreal opacityFaint READ opacityFaint CONSTANT FINAL)
    Q_PROPERTY(qreal opacityLow READ opacityLow CONSTANT FINAL)
    Q_PROPERTY(qreal opacityHigh READ opacityHigh CONSTANT FINAL)
    Q_PROPERTY(qreal opacityOverlay READ opacityOverlay CONSTANT FINAL)

    // Keel extension: the wallpaper the ambience uses, when forwarded.
    Q_PROPERTY(QString _backgroundImage READ backgroundImage NOTIFY _backgroundImageChanged FINAL)

public:
    enum ColorScheme { LightOnDark, DarkOnLight };
    Q_ENUM(ColorScheme)
    enum PresenceMode { PresenceAvailable, PresenceAway, PresenceBusy, PresenceOffline };
    Q_ENUM(PresenceMode)

    // Not default-constructible: QML creates it with create(), on its engine.
    explicit KeelTheme(QQmlEngine *engine, QObject *parent = nullptr);
    static KeelTheme *create(QQmlEngine *engine, QJSEngine *);

    int colorScheme() const { return m_colorScheme; }
    QColor highlightColor() const { return m_colors[0]; }
    QColor primaryColor() const { return m_colors[1]; }
    QColor secondaryColor() const { return m_colors[2]; }
    QColor secondaryHighlightColor() const { return m_colors[3]; }
    QColor highlightBackgroundColor() const { return m_colors[4]; }
    QColor highlightDimmerColor() const { return m_colors[5]; }
    QColor overlayBackgroundColor() const { return m_colors[6]; }
    QColor errorColor() const { return m_colors[7]; }
    qreal highlightBackgroundOpacity() const { return m_highlightBackgroundOpacity; }
    QColor lightPrimaryColor() const { return QColor(0xff, 0xff, 0xff, 0xff); }
    QColor lightSecondaryColor() const { return QColor(0xba, 0xba, 0xba); }
    QColor darkPrimaryColor() const { return QColor(0, 0, 0, 0xff); }
    QColor darkSecondaryColor() const { return QColor(0, 0, 0, 0x99); }

    QString fontFamily() const { return m_fontFamily; }
    QString fontFamilyHeading() const { return m_fontFamilyHeading; }
    qreal fontScale() const { return 1.0; }
    int fontSizeTinyBase() const { return jsRound(20 * m_pixelRatio); }
    int fontSizeExtraSmallBase() const { return jsRound(24 * m_pixelRatio); }
    int fontSizeSmallBase() const { return jsRound(28 * m_pixelRatio); }
    int fontSizeMediumBase() const { return jsRound(32 * m_pixelRatio); }
    int fontSizeLargeBase() const { return jsRound(40 * m_pixelRatio); }
    int fontSizeExtraLargeBase() const { return measured() ? 76 : jsRound(50 * m_pixelRatio); }
    int fontSizeHugeBase() const { return jsRound(64 * m_pixelRatio); }

    qreal pixelRatio() const { return m_pixelRatio; }
    qreal paddingSmall() const { return measured() ? 10 : jsRound(6 * m_pixelRatio); }
    qreal paddingMedium() const { return measured() ? 20 : jsRound(12 * m_pixelRatio); }
    qreal paddingLarge() const { return measured() ? 40 : jsRound(24 * m_pixelRatio); }
    bool phoneScreen() const { return m_phoneScreen; }
    qreal widthScale() const { return m_phoneScreen ? qMax(1.0, m_screenWidth / 540) : m_pixelRatio; }
    qreal horizontalPageMargin() const
    {
        return m_phoneScreen ? qMax(paddingLarge(), qreal(jsRound(24 * widthScale()))) : 2 * paddingLarge();
    }
    qreal itemSizeExtraSmall() const { return measured() ? 106 : jsRound(70 * m_pixelRatio); }
    qreal itemSizeSmall() const { return jsRound(80 * m_pixelRatio); }
    qreal itemSizeMedium() const { return jsRound(100 * m_pixelRatio); }
    qreal itemSizeLarge() const { return measured() ? 166 : jsRound(110 * m_pixelRatio); }
    qreal itemSizeExtraLarge() const { return measured() ? 202 : jsRound(135 * m_pixelRatio); }
    qreal itemSizeHuge() const { return jsRound(180 * m_pixelRatio); }
    qreal iconSizeExtraSmall() const { return jsRound(24 * m_pixelRatio); }
    qreal iconSizeSmall() const { return jsRound(32 * m_pixelRatio); }
    qreal iconSizeSmallPlus() const { return jsRound(48 * m_pixelRatio); }
    qreal iconSizeMedium() const { return jsRound(64 * m_pixelRatio); }
    qreal iconSizeLarge() const { return jsRound(96 * m_pixelRatio); }
    qreal iconSizeExtraLarge() const { return jsRound(128 * m_pixelRatio); }
    qreal iconSizeLauncher() const { return measured() ? 128 : jsRound(86 * m_pixelRatio); }
    qreal buttonWidthTiny() const { return jsRound(108 * widthScale()); }
    qreal buttonWidthExtraSmall() const { return jsRound(170 * widthScale()); }
    qreal buttonWidthSmall() const { return measured() ? 450 : jsRound(234 * widthScale()); }
    qreal buttonWidthMedium() const { return measured() ? 530 : jsRound(292 * widthScale()); }
    qreal buttonWidthLarge() const { return measured() ? 666 : jsRound(444 * widthScale()); }
    QSize coverSizeLarge() const { return QSize(jsRound(234 * m_pixelRatio), jsRound(374 * m_pixelRatio)); }
    QSize coverSizeSmall() const { return QSize(jsRound(148 * m_pixelRatio), jsRound(237 * m_pixelRatio)); }

    qreal flickDeceleration() const { return 1500 * m_pixelRatio; }
    qreal maximumFlickVelocity() const { return measured() ? 11250 : 5000 * m_pixelRatio; }
    int startDragDistance() const { return jsRound(20 * m_pixelRatio); }
    int minimumPressHighlightTime() const { return 64; }
    qreal pageStackIndicatorWidth() const { return jsRound(36 * m_pixelRatio); }
    qreal lineWidth() const { return measured() ? 4 : qMax(1, jsRound(m_pixelRatio)); }

    qreal opacityFaint() const { return 0.2; }
    qreal opacityLow() const { return 0.4; }
    qreal opacityHigh() const { return 0.6; }
    qreal opacityOverlay() const { return 0.8; }

    QString backgroundImage() const { return m_backgroundImage; }

    // Methods
    Q_INVOKABLE qreal dp(qreal size) const { return size * m_pixelRatio; }
    Q_INVOKABLE QColor _toColor(const QVariant &color) const { return toColor(color); }
    // Typed (QColor, qreal, int) so that compiled QML calls them directly;
    // QML converts colour strings ("#rrggbb", names) to QColor arguments.
    Q_INVOKABLE QColor rgba(const QColor &color, qreal opacity) const;
    Q_INVOKABLE QColor rgba(const QColor &color) const { return orTransparent(color); }
    Q_INVOKABLE QString _colorString(const QVariant &color) const;
    Q_INVOKABLE QColor highlightFromColor(const QColor &color, int scheme) const;
    Q_INVOKABLE QColor highlightFromColor(const QColor &color) const
    {
        return highlightFromColor(color, m_colorScheme);
    }
    Q_INVOKABLE QColor secondaryHighlightFromColor(const QColor &color, int scheme) const;
    Q_INVOKABLE QColor secondaryHighlightFromColor(const QColor &color) const
    {
        return secondaryHighlightFromColor(color, m_colorScheme);
    }
    Q_INVOKABLE QColor highlightBackgroundFromColor(const QColor &color, int scheme) const;
    Q_INVOKABLE QColor highlightBackgroundFromColor(const QColor &color) const
    {
        return highlightBackgroundFromColor(color, m_colorScheme);
    }
    Q_INVOKABLE QColor highlightDimmerFromColor(const QColor &color, int scheme) const;
    Q_INVOKABLE QColor highlightDimmerFromColor(const QColor &color) const
    {
        return highlightDimmerFromColor(color, m_colorScheme);
    }
    // Styled text with every case-insensitive match of pattern coloured, and
    // the rest of the text escaped.
    Q_INVOKABLE QString highlightText(const QVariant &text, const QVariant &pattern,
                                      const QVariant &color = QVariant()) const;
    Q_INVOKABLE QString iconForMimeType(const QVariant &mimeType) const;
    Q_INVOKABLE QString presenceColor(int presenceMode) const;

signals:
    // One per property, as Theme.qml had (apps connect to them).
    void colorSchemeChanged();
    void highlightColorChanged();
    void primaryColorChanged();
    void secondaryColorChanged();
    void secondaryHighlightColorChanged();
    void highlightBackgroundColorChanged();
    void highlightDimmerColorChanged();
    void overlayBackgroundColorChanged();
    void errorColorChanged();
    void highlightBackgroundOpacityChanged();
    void fontFamilyChanged();
    void fontFamilyHeadingChanged();
    void fontSizeTinyBaseChanged();
    void fontSizeExtraSmallBaseChanged();
    void fontSizeSmallBaseChanged();
    void fontSizeMediumBaseChanged();
    void fontSizeLargeBaseChanged();
    void fontSizeExtraLargeBaseChanged();
    void fontSizeHugeBaseChanged();
    void fontSizeTinyChanged();
    void fontSizeExtraSmallChanged();
    void fontSizeSmallChanged();
    void fontSizeMediumChanged();
    void fontSizeLargeChanged();
    void fontSizeExtraLargeChanged();
    void fontSizeHugeChanged();
    void pixelRatioChanged();
    void paddingSmallChanged();
    void paddingMediumChanged();
    void paddingLargeChanged();
    void _phoneScreenChanged();
    void _widthScaleChanged();
    void horizontalPageMarginChanged();
    void itemSizeExtraSmallChanged();
    void itemSizeSmallChanged();
    void itemSizeMediumChanged();
    void itemSizeLargeChanged();
    void itemSizeExtraLargeChanged();
    void itemSizeHugeChanged();
    void iconSizeExtraSmallChanged();
    void iconSizeSmallChanged();
    void iconSizeSmallPlusChanged();
    void iconSizeMediumChanged();
    void iconSizeLargeChanged();
    void iconSizeExtraLargeChanged();
    void iconSizeLauncherChanged();
    void buttonWidthTinyChanged();
    void buttonWidthExtraSmallChanged();
    void buttonWidthSmallChanged();
    void buttonWidthMediumChanged();
    void buttonWidthLargeChanged();
    void coverSizeLargeChanged();
    void coverSizeSmallChanged();
    void flickDecelerationChanged();
    void maximumFlickVelocityChanged();
    void startDragDistanceChanged();
    void pageStackIndicatorWidthChanged();
    void _lineWidthChanged();
    void _backgroundImageChanged();

private:
    // JavaScript's Math.round for the values Theme.qml computed with it.
    static int jsRound(qreal v) { return int(std::floor(v + 0.5)); }
    static QColor toColor(const QVariant &color);
    bool measured() const { return m_pixelRatio == 1.5; }
    // An unset colour (QML's undefined or null) as transparent, as before.
    static QColor orTransparent(const QColor &c) { return c.isValid() ? c : QColor(Qt::transparent); }
    QColor fromColor(const char *method, const QColor &color, int scheme) const;
    // Finds Keel.Ambience and Keel.Shell.
    void attach();
    // Reads the ambience and the screen into the members; emits every
    // property's change signal when anything differs (an ambience or screen
    // change, both rare).
    Q_SLOT void update();
    void emitChanged();

    QPointer<QQmlEngine> m_engine;
    QPointer<QObject> m_ambience;
    // The primary screen (KeelScreen's metrics: short side, size category).
    void trackScreen(QScreen *screen);
    static int screenWidth(const QScreen *screen);
    static bool phoneSized(const QScreen *screen);
    QPointer<QScreen> m_screen;
    bool m_shellPhone = false;

    QColor m_colors[8];
    int m_colorScheme = LightOnDark;
    qreal m_highlightBackgroundOpacity = 0;
    QString m_fontFamily;
    QString m_fontFamilyHeading;
    QString m_backgroundImage;
    qreal m_pixelRatio = 1.0;
    bool m_phoneScreen = true;
    qreal m_screenWidth = 540;
};

#endif
