#include <QtTest>
#include <QImage>
#include <QPainter>

#include "ambiencederivation.h"

class TestAmbienceDerivation : public QObject {
    Q_OBJECT

    static QImage solid(const QColor &c) {
        QImage img(200, 400, QImage::Format_RGB32);
        img.fill(c);
        return img;
    }

  private slots:
    void darkSaturatedWallpaperGivesItsHueAndDarkScheme() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(10, 40, 120)));
        QVERIFY(qAbs(s.base.hslHue() - QColor(10, 40, 120).hslHue()) <= 15);
        QVERIFY(!s.light);
    }

    void brightWallpaperGivesLightScheme() {
        QVERIFY(deriveAmbienceSeed(solid(QColor(235, 240, 245))).light);
    }

    // A wallpaper of the user's own gives a light, restrained pastel of its
    // hue on a dark ambience, so one saturated corner cannot take over.
    void darkWallpaperGivesARestrainedLightHighlight() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(10, 40, 120)));
        QVERIFY(s.base.valueF() >= 0.95);
        QVERIFY(s.base.hsvSaturationF() >= 0.25 && s.base.hsvSaturationF() <= 0.4);
    }

    // ...and a deep, quiet one on a light ambience.
    void lightWallpaperGivesADeepHighlight() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(170, 210, 250)));
        QVERIFY(s.light);
        QVERIFY(s.base.valueF() <= 0.6);
        QVERIFY(s.base.hsvSaturationF() >= 0.5 && s.base.hsvSaturationF() <= 0.8);
    }

    // Marathon's own wallpapers carry a chosen highlight, as Sailfish's
    // ambiences do: Indigo Dusk's accent is its teal glow, not its indigo.
    void bundledWallpaperHasAChosenHighlight() {
        const QColor c = bundledHighlight(QStringLiteral("/usr/share/marathon-shell/wallpapers/indigo-dusk.svg"));
        QVERIFY(c.isValid());
        QVERIFY(c.hsvHue() >= 155 && c.hsvHue() <= 185);
        QVERIFY(bundledHighlight(QStringLiteral("qrc:/wallpapers/slate-aurora.svg")).isValid());
        QVERIFY(bundledHighlight(QStringLiteral("qrc:/wallpapers/aurora-myvatn.jpg")).isValid());
    }

    void ownWallpaperHasNoChosenHighlight() {
        QVERIFY(!bundledHighlight(QStringLiteral("/home/user/Pictures/beach.jpg")).isValid());
    }

    void greyWallpaperGivesANeutralHighlight() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(90, 90, 90)));
        QVERIFY(s.base.hsvSaturationF() <= 0.15);
        QVERIFY(s.base.valueF() >= 0.95);
        QVERIFY(!s.light);
    }

    void saturatedRegionWinsOverLargerGreyArea() {
        QImage   img = solid(QColor(60, 60, 60));
        QPainter p(&img);
        p.fillRect(0, 0, 200, 120, QColor(200, 30, 30));
        p.end();
        const AmbienceSeed s = deriveAmbienceSeed(img);
        QVERIFY(s.base.hslHue() <= 15 || s.base.hslHue() >= 345);
    }

    void nullImageGivesDefault() {
        const AmbienceSeed s = deriveAmbienceSeed(QImage());
        QVERIFY(!s.base.isValid());
    }
};

QTEST_GUILESS_MAIN(TestAmbienceDerivation)
#include "test_ambiencederivation.moc"
