#include <QTest>

#include "../../shell/src/wayland/hiddenframethrottle.h"

class TestHiddenFrameThrottle : public QObject {
    Q_OBJECT

    const int a = 0, b = 0;

  private slots:
    void shownSurfacesAreNeverHeld() {
        HiddenFrameThrottle t(1000);
        for (qint64 now = 0; now < 100; now += 16)
            QVERIFY(t.allow(&a, true, now));
    }

    void hiddenSurfaceGetsOneCallbackASecond() {
        HiddenFrameThrottle t(1000);
        int                 sent = 0;
        for (qint64 now = 0; now < 3100; now += 16)
            sent += t.allow(&a, false, now);
        QCOMPARE(sent, 4); // 0, 1008, 2016, 3024
    }

    void hidingWaitsAnIntervalFromTheLastShownFrame() {
        HiddenFrameThrottle t(1000);
        QVERIFY(t.allow(&a, true, 500));
        QVERIFY(!t.allow(&a, false, 516));
        QVERIFY(!t.allow(&a, false, 1499));
        QVERIFY(t.allow(&a, false, 1500));
    }

    void showingReleasesAtOnce() {
        HiddenFrameThrottle t(1000);
        QVERIFY(t.allow(&a, false, 0));
        QVERIFY(!t.allow(&a, false, 16));
        QVERIFY(t.allow(&a, true, 32));
    }

    void surfacesArePacedApart() {
        HiddenFrameThrottle t(1000);
        QVERIFY(t.allow(&a, false, 0));
        QVERIFY(t.allow(&b, false, 16));
        QVERIFY(!t.allow(&a, false, 32));
    }

    void aForgottenSurfaceStartsFresh() {
        HiddenFrameThrottle t(1000);
        QVERIFY(t.allow(&a, false, 0));
        t.forget(&a);
        QVERIFY(t.allow(&a, false, 16));
    }
};

QTEST_GUILESS_MAIN(TestHiddenFrameThrottle)
#include "test_hiddenframethrottle.moc"
