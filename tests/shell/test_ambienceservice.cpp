#include <QTest>
#include <QSignalSpy>
#include <QImage>
#include <QTemporaryDir>
#include <QtMath>

#include "ambienceservice.h"

class TestAmbienceService : public QObject {
    Q_OBJECT

    QTemporaryDir dir;

    QString writeImage(const QString &name, const QColor &c) {
        QImage img(64, 64, QImage::Format_RGB32);
        img.fill(c);
        const QString path = dir.path() + "/" + name;
        img.save(path);
        return path;
    }

  private slots:
    void wallpaperSetsSeed() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::seedChanged);
        svc.setWallpaper(writeImage("blue.png", QColor(20, 40, 160)));
        QCOMPARE(spy.count(), 1);
        QVERIFY(svc.baseColor().blue() > svc.baseColor().red());
        QCOMPARE(svc.wallpaperUrl(), QUrl::fromLocalFile(dir.path() + "/blue.png").toString());
    }

    void bundledWallpaperUsesItsChosenHighlight() {
        QDir(dir.path()).mkpath("wallpapers");
        AmbienceService svc;
        svc.setWallpaper(writeImage("wallpapers/indigo-dusk.png", QColor(40, 30, 120)));
        QVERIFY(svc.baseColor().hsvHue() >= 155 && svc.baseColor().hsvHue() <= 185);
        QVERIFY(!svc.light());
    }

    void unreadableWallpaperKeepsPreviousSeed() {
        AmbienceService svc;
        svc.setWallpaper(writeImage("red.png", QColor(180, 20, 20)));
        const QColor before = svc.baseColor();
        QSignalSpy   spy(&svc, &AmbienceService::seedChanged);
        svc.setWallpaper(dir.path() + "/missing.png");
        QCOMPARE(spy.count(), 0);
        QCOMPARE(svc.baseColor(), before);
    }

    void publishIsDebounced() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::ambienceChanged);
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#111111"}});
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#222222"}});
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#333333"}});
        QCOMPARE(spy.count(), 0);
        QVERIFY(spy.wait(1000));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(svc.ambience().value("/desktop/jolla/theme/color/highlight").toString(),
                 QStringLiteral("#333333"));
    }

    void identicalPublishDoesNotSignal() {
        AmbienceService   svc;
        const QVariantMap m{{"/desktop/jolla/theme/color_scheme", "lightondark"}};
        QSignalSpy        spy(&svc, &AmbienceService::ambienceChanged);
        svc.publish(m);
        QVERIFY(spy.wait(1000));
        svc.publish(m);
        QVERIFY(!spy.wait(500));
        QCOMPARE(spy.count(), 1);
    }

    // Keel rounds Silica's base sizes (theme.h) like the shell rounds its
    // design px (Constants.qml): Math.round.
    static int px(qreal v) {
        return qFloor(v + 0.5);
    }

    void silicaTextMatchesShellText_data() {
        QTest::addColumn<qreal>("dpi");
        QTest::addColumn<qreal>("userScale");
        QTest::newRow("HackberryPi") << 254.0 << 1.0;
        QTest::newRow("HackberryPi 75%") << 254.0 << 0.75;
        QTest::newRow("HackberryPi 110%") << 254.0 << 1.1;
        QTest::newRow("PinePhone") << 270.0 << 1.0;
        QTest::newRow("Librem 5") << 287.0 << 1.0;
        QTest::newRow("Librem 5 120%") << 287.0 << 1.2;
        QTest::newRow("QEMU") << 296.0 << 1.0;
        QTest::newRow("OnePlus 6") << 402.0 << 1.0;
        QTest::newRow("design canvas") << 160.0 << 1.0;
    }

    // Silica fontSize{ExtraSmall,Small,Medium,Huge} (24/28/32/64 x ratio)
    // against the shell's XSmall 12, Small 14, Body 16 and XXLarge 32
    // (x scaleFactor).
    void silicaTextMatchesShellText() {
        QFETCH(qreal, dpi);
        QFETCH(qreal, userScale);
        const qreal scale = dpi / 160 * userScale;
        const qreal ratio = AmbienceService::silicaPixelRatio(dpi, userScale);
        for (int base : {12, 14, 16, 32})
            QCOMPARE(px(2 * base * ratio), px(base * scale));
    }

    void pixelRatioFollowsMarathonScale() {
        QCOMPARE(AmbienceService::silicaPixelRatio(160, 1.0), 0.5);
        QCOMPARE(AmbienceService::silicaPixelRatio(320, 1.0), 1.0);
        QCOMPARE(AmbienceService::silicaPixelRatio(254, 1.0), 0.79375);
        QCOMPARE(AmbienceService::silicaPixelRatio(254, 1.2), 0.9525);
        QCOMPARE(AmbienceService::silicaPixelRatio(0, 1.0), 0.0);
    }

    void pixelRatioIsPublishedForKeel() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::ambienceChanged);
        svc.setPixelRatio(1.25);
        svc.publish({{"/desktop/jolla/theme/color_scheme", "lightondark"}});
        QVERIFY(spy.wait(1000));
        QCOMPARE(svc.ambience().value("/desktop/sailfish/silica/theme_pixel_ratio").toReal(), 1.25);
        svc.setPixelRatio(1.5);
        QVERIFY(spy.wait(1000));
        QCOMPARE(svc.ambience().value("/desktop/sailfish/silica/theme_pixel_ratio").toReal(), 1.5);
        QCOMPARE(svc.ambience().value("/desktop/jolla/theme/color_scheme").toString(), QString("lightondark"));
    }

    void pixelRatioNotifiesTheShell() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::pixelRatioChanged);
        svc.setPixelRatio(1.25);
        svc.setPixelRatio(1.25);
        QCOMPARE(spy.count(), 1);
        QCOMPARE(svc.pixelRatio(), 1.25);
    }
};

QTEST_MAIN(TestAmbienceService)
#include "test_ambienceservice.moc"
