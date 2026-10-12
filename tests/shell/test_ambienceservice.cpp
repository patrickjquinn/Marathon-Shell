#include <QtTest>
#include <QImage>
#include <QTemporaryDir>

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

    void pixelRatioFollowsDensityAndUserScale() {
        QCOMPARE(AmbienceService::sailfishPixelRatio(235, 1.0), 1.0);
        QCOMPARE(AmbienceService::sailfishPixelRatio(294, 1.0), 1.25); // Jolla C
        QCOMPARE(AmbienceService::sailfishPixelRatio(268, 1.0), 1.25); // PinePhone, Librem 5
        QCOMPARE(AmbienceService::sailfishPixelRatio(268, 1.1), 1.25);
        QCOMPARE(AmbienceService::sailfishPixelRatio(268, 1.5), 1.75);
        QCOMPARE(AmbienceService::sailfishPixelRatio(268, 0.85), 1.0);
        QCOMPARE(AmbienceService::sailfishPixelRatio(470, 1.0), 2.0);
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
};

QTEST_MAIN(TestAmbienceService)
#include "test_ambienceservice.moc"
