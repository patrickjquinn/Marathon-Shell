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

    // Sailfish's dark ambiences highlight in a light pastel of their hue
    // (water #7ff0fe, sailfish5 #ffad80), however dark the wallpaper.
    void darkWallpaperGivesAVividLightHighlight() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(10, 40, 120)));
        QVERIFY(s.base.valueF() >= 0.95);
        QVERIFY(s.base.hsvSaturationF() >= 0.4 && s.base.hsvSaturationF() <= 0.65);
    }

    // ...and their light ones in a deep, saturated one (airy #004c99).
    void lightWallpaperGivesADeepHighlight() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(170, 210, 250)));
        QVERIFY(s.light);
        QVERIFY(s.base.valueF() <= 0.65);
        QVERIFY(s.base.hsvSaturationF() >= 0.9);
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
