#include <QTest>

#include "ngfevents.h"

class TestNgfEvents : public QObject {
    Q_OBJECT

  private slots:
    void silicaPulleyEventsAreShortTicks() {
        const NgfEvents::Effect highlight = NgfEvents::effect(QStringLiteral("pulldown_highlight"));
        QVERIFY(highlight.known);
        QCOMPARE(highlight.pattern.size(), 1);
        QVERIFY(highlight.pattern.first() <= 20);
        QVERIFY(!highlight.repeat);
        QVERIFY(NgfEvents::effect(QStringLiteral("pulldown_lock")).pattern.first() >
                highlight.pattern.first());
    }
    void messagesBuzzTwice() {
        const NgfEvents::Effect sms = NgfEvents::effect(QStringLiteral("sms"));
        QCOMPARE(sms.pattern.size(), 3); // on, off, on
        QVERIFY(!sms.repeat);
    }
    void ringtoneAndAlarmRepeatUntilStopped() {
        QVERIFY(NgfEvents::effect(QStringLiteral("ringtone")).repeat);
        QVERIFY(NgfEvents::effect(QStringLiteral("alarm")).repeat);
    }
    void unknownEventFails() {
        QVERIFY(!NgfEvents::effect(QStringLiteral("no_such_event")).known);
    }
    void durationSumsThePattern() {
        QCOMPARE(NgfEvents::duration({200, 100, 200}), 500);
    }
};

QTEST_GUILESS_MAIN(TestNgfEvents)
#include "test_ngfevents.moc"
