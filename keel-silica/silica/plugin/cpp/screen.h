// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Screen singleton (Silica public API: width, height, widthRatio,
// sizeCategory, topCutout, hasCutouts, the four corners, and the
// Screen.Small .. Screen.ExtraLarge
// categories). Clean-room from the public documentation; the category
// thresholds are Keel's own.
//
// C++ rather than QML: Qt 6 searches the C++ types of a document's imports
// before composite (QML file) singletons, so a Screen.qml singleton never
// won. Among C++ types the document's first import that has the name wins
// (QQmlImports::populateCache), so an unqualified `Screen` is Qt Quick's
// attached Screen when QtQuick is imported before Sailfish.Silica. Keel's
// remedies: the same singleton in Keel.SilicaScreen, which keel/qt5compat's
// Qt Quick 2.x shims re-export after Qt Quick (so `import QtQuick 2.x` no
// longer brings Qt Quick's Screen first, as in Qt 5), and qualified access
// (`S.Screen`) in Qt 6 code. See keel/silica/COMPATIBILITY.md.
#ifndef KEEL_SCREEN_H
#define KEEL_SCREEN_H

#include <QObject>
#include <QList>
#include <QPointer>
#include <QRect>
#include <QScreen>
#include <QSize>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <cmath>

class KeelScreen : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Screen)
    QML_SINGLETON
    Q_PROPERTY(int width READ width NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int height READ height NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal widthRatio READ widthRatio NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int sizeCategory READ sizeCategory NOTIFY geometryChanged FINAL)
    // The display's cutouts and rounded corners, as Silica's BSD QML reads
    // them: topCutout is the rectangle of the cutout at the top edge in
    // portrait (its height is the clearance a notch needs; empty without
    // one), each corner a map with x, y (the centre of its arc, in portrait
    // screen coordinates) and radius. From the adaptation's dconf, where
    // Sailfish OS keeps them (/desktop/sailfish/silica/cutouts: [x, y,
    // width, height] each; rounded_corners: [x, y, radius] each, a negative
    // x or y counted from the right or bottom edge), in device pixels,
    // converted to Qt's logical pixels. KEEL_SCREEN_CUTOUTS and
    // KEEL_SCREEN_ROUNDED_CORNERS give the same text instead (tests, hosts).
    // Without them: no cutouts, square corners.
    Q_PROPERTY(QRect topCutout READ topCutout NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(bool hasCutouts READ hasCutouts NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(QVariantMap topLeftCorner READ topLeftCorner NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(QVariantMap topRightCorner READ topRightCorner NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(QVariantMap bottomLeftCorner READ bottomLeftCorner NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(QVariantMap bottomRightCorner READ bottomRightCorner NOTIFY cutoutsChanged FINAL)
    Q_PROPERTY(qreal diagonalInches READ diagonalInches NOTIFY geometryChanged FINAL)
    // Qt Quick's attached Screen members (QQuickScreenInfo), for the primary
    // screen: where Keel.SilicaScreen makes `Screen` Silica's (the Qt Quick
    // 2.x shims of keel/qt5compat), code written for Qt Quick's Screen keeps
    // working. width and height stay Silica's (portrait).
    Q_PROPERTY(QString name READ name NOTIFY screenInfoChanged FINAL)
    Q_PROPERTY(QString manufacturer READ manufacturer NOTIFY screenInfoChanged FINAL)
    Q_PROPERTY(QString model READ model NOTIFY screenInfoChanged FINAL)
    Q_PROPERTY(QString serialNumber READ serialNumber NOTIFY screenInfoChanged FINAL)
    Q_PROPERTY(qreal pixelDensity READ pixelDensity NOTIFY geometryChanged FINAL)
    Q_PROPERTY(qreal devicePixelRatio READ devicePixelRatio NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int desktopAvailableWidth READ desktopAvailableWidth NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int desktopAvailableHeight READ desktopAvailableHeight NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int virtualX READ virtualX NOTIFY geometryChanged FINAL)
    Q_PROPERTY(int virtualY READ virtualY NOTIFY geometryChanged FINAL)
    Q_PROPERTY(Qt::ScreenOrientation orientation READ orientation NOTIFY orientationChanged FINAL)
    Q_PROPERTY(Qt::ScreenOrientation primaryOrientation READ primaryOrientation NOTIFY orientationChanged FINAL)
    Q_PROPERTY(Qt::ScreenOrientations orientationUpdateMask READ orientationUpdateMask CONSTANT FINAL)

public:
    enum SizeCategory { Small, Medium, Large, ExtraLarge };
    Q_ENUM(SizeCategory)

    explicit KeelScreen(QObject *parent = nullptr);

    int width() const;
    int height() const;
    qreal widthRatio() const { return width() / 540.0; }
    int sizeCategory() const;
    QRect topCutout() const;
    bool hasCutouts() const { return !cutouts().isEmpty(); }
    QVariantMap topLeftCorner() const { return corner(false, false); }
    QVariantMap topRightCorner() const { return corner(true, false); }
    QVariantMap bottomLeftCorner() const { return corner(false, true); }
    QVariantMap bottomRightCorner() const { return corner(true, true); }
    qreal diagonalInches() const;

    QString name() const { return m_screen ? m_screen->name() : QString(); }
    QString manufacturer() const { return m_screen ? m_screen->manufacturer() : QString(); }
    QString model() const { return m_screen ? m_screen->model() : QString(); }
    QString serialNumber() const { return m_screen ? m_screen->serialNumber() : QString(); }
    // Pixels per millimetre (from KEEL_SCREEN_DIAGONAL when it is set).
    qreal pixelDensity() const
    {
        const qreal inches = qEnvironmentVariableIsSet("KEEL_SCREEN_DIAGONAL") ? diagonalInches() : 0;
        if (inches > 0)
            return std::hypot(static_cast<qreal>(width()), static_cast<qreal>(height())) / (inches * 25.4);
        return m_screen ? m_screen->physicalDotsPerInch() / 25.4 : 0;
    }
    qreal devicePixelRatio() const { return m_screen ? m_screen->devicePixelRatio() : 1; }
    int desktopAvailableWidth() const;
    int desktopAvailableHeight() const;
    int virtualX() const { return m_screen ? m_screen->geometry().x() : 0; }
    int virtualY() const { return m_screen ? m_screen->geometry().y() : 0; }
    Qt::ScreenOrientation orientation() const
    {
        return m_screen ? m_screen->orientation() : Qt::PrimaryOrientation;
    }
    Qt::ScreenOrientation primaryOrientation() const
    {
        return m_screen ? m_screen->primaryOrientation() : Qt::PortraitOrientation;
    }
    static Qt::ScreenOrientations orientationUpdateMask()
    {
        // Qt 6 reports every orientation change (the mask is gone).
        return Qt::PortraitOrientation | Qt::LandscapeOrientation | Qt::InvertedPortraitOrientation
            | Qt::InvertedLandscapeOrientation;
    }

    // Pure helpers, shared with tests.
    static int categoryForDiagonal(qreal inches);
    // "[[a, b, ...], [c, d, ...]]" (dconf's text for an array of int
    // arrays) -> the inner arrays; inner arrays of another length are left
    // out.
    static QList<QList<int>> parseIntArrays(const QString &text, int length);
    // The cutout at the top edge of a portrait screen of the given size, in
    // device pixels, from [x, y, width, height] rectangles: the union of
    // those that touch the top edge.
    static QRect topCutoutOf(const QList<QList<int>> &cutouts);
    // The rounded corner of a screen of the given size (device pixels) at
    // the right and/or bottom edge, from [x, y, radius] entries (negative x
    // or y count from the right or bottom edge): x, y of the arc's centre
    // and radius, scaled by 1 / ratio.
    static QVariantMap cornerOf(const QList<QList<int>> &corners, QSize size, bool right, bool bottom,
                                qreal ratio);

signals:
    void cutoutsChanged();
    void geometryChanged();
    void screenInfoChanged();
    void orientationChanged();

private:
    void track(QScreen *screen);
    QList<QList<int>> cutouts() const;
    QVariantMap corner(bool right, bool bottom) const;
    // Device pixels per logical pixel (the dconf values are device pixels).
    qreal ratio() const { return m_screen && m_screen->devicePixelRatio() > 0 ? m_screen->devicePixelRatio() : 1; }
    QPointer<QScreen> m_screen;
};

#endif // KEEL_SCREEN_H
