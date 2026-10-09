// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The "theme" image provider and theme icons in a light ambience, on an icon
// directory the test writes (KEEL_THEME_ICON_DIRS):
//   - a name the theme has only as colour scheme variants
//     (icon-m-file-pdf-dark / -light) resolves to the ambience's variant;
//   - a missing icon falls back to a substitute (icon-l-video ->
//     icon-m-video, scaled to the icon-l size);
//   - "?mono=<color>" recolours monochrome icons only;
//   - in a light ambience, IconTextSwitch's (HighlightImage's) white
//     monochrome icon is drawn in the primary colour, not white.

#include <QDir>
#include <QImage>
#include <QPainter>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTemporaryDir>
#include <QtTest>

#include "themeimageprovider.h"

namespace {

QImage glyph(const QColor &c, int size = 64)
{
    QImage img(size, size, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.fillRect(QRect(size / 4, size / 4, size / 2, size / 2), c);
    return img;
}

} // namespace

class tst_ThemeIcons : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        const QString d = m_dir.path();
        QVERIFY(glyph(Qt::white).save(d + QStringLiteral("/icon-m-file-pdf-dark.png")));
        QVERIFY(glyph(QColor(40, 40, 40)).save(d + QStringLiteral("/icon-m-file-pdf-light.png")));
        QVERIFY(glyph(Qt::white).save(d + QStringLiteral("/icon-m-video.png")));
        QVERIFY(glyph(Qt::white).save(d + QStringLiteral("/icon-m-keeltest-mono.png")));
        QVERIFY(glyph(QColor(220, 30, 30)).save(d + QStringLiteral("/icon-m-keeltest-colour.png")));
        qputenv("KEEL_THEME_ICON_DIRS", d.toLocal8Bit());
    }

    void schemeVariants()
    {
        KeelThemeImageProvider provider;
        provider.setLightScheme(false);
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-m-file-pdf")), QStringLiteral("icon-m-file-pdf-dark"));
        provider.setLightScheme(true);
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-m-file-pdf")), QStringLiteral("icon-m-file-pdf-light"));
        QSize size;
        const QImage img = provider.requestImage(QStringLiteral("icon-m-file-pdf"), &size, QSize());
        QCOMPARE(size, QSize(64, 64));
        QCOMPARE(QColor(img.pixel(32, 32)), QColor(40, 40, 40));
        // An icon the theme has as it is is not replaced.
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-m-video")), QStringLiteral("icon-m-video"));
    }

    void ratioDirectories()
    {
        // The Sailfish theme's z<ratio> directories follow the pixel ratio
        // (dconf's theme_pixel_ratio, through Keel.Ambience), and its
        // monochrome icons (icon-m-search, graphic-busyindicator-*) live in
        // icons-monochrome.
        KeelThemeImageProvider provider;
        provider.setPixelRatio(1.5);
        const QStringList dirs = provider.searchDirectories();
        QVERIFY(dirs.contains(QStringLiteral("/usr/share/themes/sailfish-default/silica/z1.5/icons")));
        QVERIFY(dirs.contains(QStringLiteral("/usr/share/themes/sailfish-default/silica/z1.5/icons-monochrome")));
        provider.setPixelRatio(2.0);
        QVERIFY(provider.searchDirectories().contains(
                QStringLiteral("/usr/share/themes/sailfish-default/silica/z2.0/icons-monochrome")));
        provider.setPixelRatio(1.75);
        QVERIFY(provider.searchDirectories().contains(
                QStringLiteral("/usr/share/themes/sailfish-default/silica/z1.75/icons")));
        // Stand-ins are drawn at the ratio too.
        QSize size;
        provider.setPixelRatio(1.5);
        QCOMPARE(provider.requestImage(QStringLiteral("icon-m-nothing-like-this"), &size, QSize()).size(),
                 QSize(96, 96));
    }

    void substitutes()
    {
        KeelThemeImageProvider provider;
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-l-video")), QStringLiteral("icon-m-video"));
        QSize size;
        const QImage img = provider.requestImage(QStringLiteral("icon-l-video"), &size, QSize());
        QCOMPARE(size, QSize(96, 96)); // the icon-l size class
        QCOMPARE(QColor(img.pixel(48, 48)), QColor(Qt::white));
        // A file type icon the theme lacks altogether ends at one it has
        // (icon-m-file-spreadsheet -> -document -> -other -> icon-m-document
        // here missing too, so the name is kept and the stand-in drawn).
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-m-file-image")), QStringLiteral("icon-m-file-image"));
        QCOMPARE(provider.resolveAlias(QStringLiteral("icon-m-nothing-like-this")), QStringLiteral("icon-m-nothing-like-this"));
    }

    void monochromeTint()
    {
        KeelThemeImageProvider provider;
        QSize size;
        QImage mono = provider.requestImage(QStringLiteral("icon-m-keeltest-mono?mono=#202020"), &size, QSize());
        QCOMPARE(QColor(mono.pixel(32, 32)).name(), QStringLiteral("#202020"));
        QImage colour = provider.requestImage(QStringLiteral("icon-m-keeltest-colour?mono=#202020"), &size, QSize());
        QCOMPARE(QColor(colour.pixel(32, 32)), QColor(220, 30, 30));
        // A plain tint recolours any icon.
        colour = provider.requestImage(QStringLiteral("icon-m-keeltest-colour?#202020"), &size, QSize());
        QCOMPARE(QColor(colour.pixel(32, 32)).name(), QStringLiteral("#202020"));
    }

    void iconTextSwitchInLightAmbience()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
        QQmlComponent component(&engine);
        component.setData(
            "import QtQuick\n"
            "import Sailfish.Silica 1.0\n"
            "import Keel 1.0\n"
            "Item {\n"
            "    width: 540; height: 200\n"
            "    property bool light: false\n"
            "    Component.onCompleted: {\n"
            "        Ambience.applyForwarded(\"/desktop/jolla/theme/color_scheme=darkonlight\\n/desktop/jolla/theme/color/highlight=#0060a8\\n\")\n"
            "        light = Theme.colorScheme === Theme.DarkOnLight\n"
            "    }\n"
            "    Rectangle { anchors.fill: parent; color: \"#d8dee4\" }\n"
            "    IconTextSwitch {\n"
            "        objectName: \"switch\"\n"
            "        width: parent.width\n"
            "        text: \"Wi-Fi\"\n"
            "        icon.source: \"image://theme/icon-m-keeltest-mono\"\n"
            "    }\n"
            "}\n",
            QUrl(QStringLiteral("file:///tst_themeicons.qml")));
        QScopedPointer<QObject> obj(component.create());
        QVERIFY2(obj, qPrintable(component.errorString()));
        QVERIFY(obj->property("light").toBool());
        QQuickWindow window;
        window.resize(540, 200);
        auto *root = qobject_cast<QQuickItem *>(obj.data());
        root->setParentItem(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        auto *sw = root->findChild<QQuickItem *>(QStringLiteral("switch"));
        QVERIFY(sw);
        auto *icon = qvariant_cast<QQuickItem *>(sw->property("icon"));
        QVERIFY(icon);
        QTRY_COMPARE(icon->property("status").toInt(), 1 /* Image.Ready */);
        // The glyph's centre, in window coordinates.
        const QPointF c = icon->mapToScene(QPointF(icon->width() / 2, icon->height() / 2));
        QTRY_VERIFY_WITH_TIMEOUT(qGray(window.grabWindow().pixel(c.toPoint())) < 100, 5000);
    }

private:
    QTemporaryDir m_dir;
};

QTEST_MAIN(tst_ThemeIcons)
#include "tst_themeicons.moc"
