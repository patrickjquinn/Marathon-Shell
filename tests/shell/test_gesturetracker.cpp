#include <QSignalSpy>
#include <QTest>

#include "../../shell/src/services/gesturetracker.h"

using Sample = GestureTracker::Sample;

class TestGestureTracker : public QObject {
    Q_OBJECT

  private slots:
    void velocityOfSteadyDrag() {
        QList<Sample> s;
        for (int i = 0; i <= 10; ++i)
            s.append({i * 8.0, i * 8.0 * 1.5}); // 1.5 px/ms
        QCOMPARE(qRound(GestureTracker::estimateVelocity(s, 80)), 1500);
    }

    void velocityUsesOnlyTheRecentWindow() {
        QList<Sample> s;
        // Slow for 200 ms, then fast for the last 60 ms.
        for (int t = 0; t <= 200; t += 10)
            s.append({qreal(t), t * 0.1});
        for (int t = 210; t <= 260; t += 10)
            s.append({qreal(t), 20 + (t - 200) * 2.0});
        QCOMPARE(qRound(GestureTracker::estimateVelocity(s, 260)), 2000);
    }

    void velocitySmoothsArrivalJitter() {
        QList<Sample> s;
        const qreal   jitter[] = {0, 3, -3, 2, -2, 3, -1, 0};
        for (int i = 0; i < 8; ++i) {
            const qreal t = i * 8.0 + jitter[i];
            s.append({t, i * 8.0}); // 1 px per nominal ms
        }
        const qreal v = GestureTracker::estimateVelocity(s, s.last().t);
        QVERIFY2(v > 800 && v < 1250, qPrintable(QString::number(v)));
    }

    void velocityIsZeroWhenTheFingerStopped() {
        QList<Sample> s = {{0, 0}, {8, 10}, {16, 20}};
        QCOMPARE(GestureTracker::estimateVelocity(s, 16 + GestureTracker::kStaleMs + 1), 0.0);
        QVERIFY(GestureTracker::estimateVelocity(s, 30) > 0);
    }

    void velocityNeedsTwoSamples() {
        QCOMPARE(GestureTracker::estimateVelocity({}, 0), 0.0);
        QCOMPARE(GestureTracker::estimateVelocity({{5, 40}}, 5), 0.0);
        QCOMPARE(GestureTracker::estimateVelocity({{0, 0}, {0, 40}}, 0), 0.0);
    }

    void velocityFallsBackToThePreviousSample() {
        // A single move inside the window still pairs with the press.
        QList<Sample> s = {{0, 0}, {100, 50}};
        QCOMPARE(qRound(GestureTracker::estimateVelocity(s, 100)), 500);
    }

    void commitByDistance() {
        QVERIFY(GestureTracker::shouldCommit(100, 0, 81, 500));
        QVERIFY(!GestureTracker::shouldCommit(60, 0, 81, 500));
    }

    void commitByProjectedVelocity() {
        // 60 px + 300 px/s * 0.1 s = 90 px past an 81 px threshold.
        QVERIFY(GestureTracker::shouldCommit(60, 300, 81, 500));
        // Moving back: 100 px - 300 px/s * 0.1 s = 70 px.
        QVERIFY(!GestureTracker::shouldCommit(100, -300, 81, 500));
    }

    void flingOverridesDistance() {
        QVERIFY(GestureTracker::shouldCommit(10, 900, 81, 500));
        QVERIFY(!GestureTracker::shouldCommit(300, -900, 81, 500));
        QVERIFY(!GestureTracker::shouldCommit(0, 900, 81, 500));
    }

    void releaseDecidesAlongTheRange() {
        GestureTracker g;
        g.setFrom(0);
        g.setTo(-400); // a gesture that runs towards negative values
        g.setCommitDistance(80);
        g.press();
        for (int i = 1; i <= 6; ++i)
            g.move(-i * 20.0, i * 10.0);
        QVERIFY(g.willCommit());
        QVERIFY(g.velocity() < -1500);
        QVERIFY(g.release(65));
        QVERIFY(!g.active());
    }

    void willCommitTracksDistanceBothWays() {
        GestureTracker g;
        g.setFrom(0);
        g.setTo(500);
        g.setCommitDistance(100);
        QSignalSpy spy(&g, &GestureTracker::willCommitChanged);
        g.press();
        g.move(50, 10);
        g.move(120, 20);
        g.move(130, 30);
        g.move(90, 40);
        QCOMPARE(spy.count(), 2);
        QVERIFY(!g.willCommit());
    }

    void criticalSpringNeverOvershoots() {
        // Released 200 px short of the target at 8000 px/s towards it.
        const qreal omega0 = 6.64 / 0.3;
        const qreal omega  = GestureTracker::settleOmega(-200, 8000, omega0, 1);
        QCOMPARE(omega, 40.0);
        QCOMPARE(GestureTracker::settleOmega(-200, 1000, omega0, 1), omega0);
        QCOMPARE(GestureTracker::settleOmega(-200, -8000, omega0, 1), omega0);
        for (int ms = 0; ms <= 600; ms += 4) {
            const auto s = GestureTracker::spring(-200, 8000, omega, 1, ms / 1000.0);
            QVERIFY2(s.offset <= 0.0001, qPrintable(QString::number(ms)));
        }
    }

    void springStartsAtTheFingersVelocity() {
        const auto s0 = GestureTracker::spring(-200, 1200, 30, 1, 0);
        QCOMPARE(s0.offset, -200.0);
        QCOMPARE(s0.velocity, 1200.0);
        const auto u0 = GestureTracker::spring(-200, 1200, 30, 0.6, 0);
        QCOMPARE(u0.offset, -200.0);
        QVERIFY(qAbs(u0.velocity - 1200) < 1e-9);
    }

    void underdampedSpringOvershoots() {
        qreal maxOffset = -1;
        for (int ms = 0; ms <= 800; ms += 4)
            maxOffset = qMax(maxOffset, GestureTracker::spring(-200, 0, 22, 0.5, ms / 1000.0).offset);
        QVERIFY(maxOffset > 5);
    }

    void settleReachesTheTarget() {
        GestureTracker g;
        g.setSettleDuration(200);
        g.setValue(300);
        QSignalSpy done(&g, &GestureTracker::settled);
        g.settleTo(0, -800);
        QVERIFY(g.settling());
        QVERIFY(done.wait(2000));
        QCOMPARE(g.value(), 0.0);
        QCOMPARE(g.velocity(), 0.0);
        QVERIFY(!g.settling());
    }

    void pressInterruptsTheSettle() {
        GestureTracker g;
        g.setSettleDuration(400);
        g.setValue(300);
        g.settleTo(0, 0);
        QTRY_VERIFY(g.value() < 250);
        g.press();
        const qreal caught = g.value();
        QVERIFY(!g.settling());
        QVERIFY(caught > 0);
        QTest::qWait(50);
        QCOMPARE(g.value(), caught);
    }
};

QTEST_MAIN(TestGestureTracker)
#include "test_gesturetracker.moc"
