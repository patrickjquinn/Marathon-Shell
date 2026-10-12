#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QDateTime>
#include "alarmmanagercpp.h"
#include "settingsmanager.h"

class TestAlarmManager : public QObject {
    Q_OBJECT

    SettingsManager *m_settings = nullptr;

    static bool listed(const QVariantList &alarms, const QString &id) {
        for (const QVariant &a : alarms)
            if (a.toMap().value("id").toString() == id)
                return true;
        return false;
    }

    QVariantMap timerOptions(qint64 at) {
        return {{"at", at}, {"oneShot", true}, {"hidden", true}, {"snoozeEnabled", false}};
    }

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        m_settings = new SettingsManager(this);
    }

    void init() {
        m_settings->set("alarms/data", "[]");
    }

    void oneShotRingsOnceAtItsInstantAndIsHidden() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QSignalSpy    changed(&alarms, &AlarmManagerCpp::alarmsChanged);
        QSignalSpy    triggered(&alarms, &AlarmManagerCpp::alarmTriggered);

        const qint64  at = QDateTime::currentMSecsSinceEpoch() + 1300;
        const QString id = alarms.createAlarm(QString(), "Timer", {}, timerOptions(at));
        QVERIFY(!id.isEmpty());
        QVERIFY(!listed(alarms.alarms(), id));
        QVERIFY(!alarms.hasEnabledAlarm());
        QCOMPARE(changed.count(), 0);
        QVERIFY(m_settings->get("alarms/data").toString().contains(id));

        QTRY_COMPARE_WITH_TIMEOUT(triggered.count(), 1, 3000);
        const qint64 firedAt = QDateTime::currentMSecsSinceEpoch();
        QVERIFY(firedAt >= at - 50);
        QVERIFY(firedAt < at + 500);
        QCOMPARE(triggered.first().at(0).toString(), id);
        QCOMPARE(triggered.first().at(1).toString(), QString("Timer"));

        QTest::qWait(500);
        QCOMPARE(triggered.count(), 1);
        QVERIFY(!m_settings->get("alarms/data").toString().contains(id));
        alarms.stopAll();
    }

    void deletingOneShotCancelsIt() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QSignalSpy    triggered(&alarms, &AlarmManagerCpp::alarmTriggered);
        const QString id = alarms.createAlarm(
            QString(), "Timer", {}, timerOptions(QDateTime::currentMSecsSinceEpoch() + 300));
        QVERIFY(alarms.deleteAlarm(id));
        QTest::qWait(700);
        QCOMPARE(triggered.count(), 0);
    }

    void oneShotDoesNotReringDailyAlarmOfTheSameMinute() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        const QString daily = alarms.createAlarm(QTime::currentTime().toString("HH:mm"), "Daily",
                                                 {}, {});
        QVERIFY(listed(alarms.alarms(), daily));
        QSignalSpy triggered(&alarms, &AlarmManagerCpp::alarmTriggered);
        alarms.createAlarm(QString(), "Timer", {},
                           timerOptions(QDateTime::currentMSecsSinceEpoch() + 200));
        QTRY_COMPARE_WITH_TIMEOUT(triggered.count(), 1, 2000);
        QTest::qWait(200);
        QCOMPARE(triggered.count(), 1);
        QCOMPARE(triggered.first().at(1).toString(), QString("Timer"));
        alarms.stopAll();
    }

    void oneShotWithoutInstantIsRejected() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QVERIFY(alarms.createAlarm(QString(), "Timer", {}, {{"oneShot", true}}).isEmpty());
    }
};

QTEST_MAIN(TestAlarmManager)
#include "test_alarmmanager.moc"
