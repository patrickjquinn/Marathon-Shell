#include <QTest>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSoundEffect>
#include "alarmmanagercpp.h"
#include "mediarole.h"
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

    // An alarm rings at the alarm volume on the alarm role, which the
    // media volume does not scale.
    void ringsAtTheAlarmVolumeOnItsRole() {
        const bool roles = qEnvironmentVariableIsSet("MARATHON_MEDIA_ROLES");
        if (roles)
            QTRY_COMPARE_WITH_TIMEOUT(MediaRole::output("alarm").id(), MediaRole::sinkName("alarm"),
                                      10000);
        m_settings->setAlarmVolume(0.15);
        m_settings->setAlarmSound("/nonexistent/alarm.ogg");
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        alarms.triggerAlarmNow("Test");
        QSoundEffect *sound = alarms.findChild<QSoundEffect *>();
        QVERIFY(qFuzzyCompare(sound->volume(), 0.15f));
        if (roles)
            QCOMPARE(sound->audioDevice().id(), MediaRole::sinkName("alarm"));
        alarms.stopAll();
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

    void snoozeRingsAgainAfterItsDuration() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QSignalSpy triggered(&alarms, &AlarmManagerCpp::alarmTriggered);
        alarms.triggerAlarmNow("Wake");
        QCOMPARE(triggered.count(), 1);
        const QString id     = triggered.first().at(0).toString();
        const qint64  before = QDateTime::currentMSecsSinceEpoch();
        QVERIFY(alarms.snoozeAlarm(id));
        QVERIFY(!alarms.hasActiveAlarm());
        QVERIFY(alarms.alarms().isEmpty());

        const QJsonArray saved =
            QJsonDocument::fromJson(m_settings->get("alarms/data").toString().toUtf8()).array();
        QCOMPARE(saved.size(), 1);
        const QJsonObject again = saved.first().toObject();
        QCOMPARE(again["label"].toString(), QString("Wake"));
        QVERIFY(again["oneShot"].toBool());
        const qint64 at = again["at"].toInteger();
        QVERIFY(at >= before + 10 * 60000LL && at <= before + 10 * 60000LL + 1000);
        alarms.stopAll();
    }

    void theEarliestAlarmIsScheduledToWakeTheDevice() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QSignalSpy      scheduled(&alarms, &AlarmManagerCpp::nextAlarmScheduled);
        QTRY_COMPARE(scheduled.count(), 1);
        QCOMPARE(scheduled.takeLast().at(0).toLongLong(), 0);

        const qint64  soon  = QDateTime::currentMSecsSinceEpoch() + 3600000;
        const qint64  later = soon + 3600000;
        const QString late  = alarms.createAlarm(QString(), "Later", {}, timerOptions(later));
        QCOMPARE(scheduled.takeLast().at(0).toLongLong(), later / 1000);
        const QString first = alarms.createAlarm(QString(), "Soon", {}, timerOptions(soon));
        QCOMPARE(scheduled.takeLast().at(0).toLongLong(), soon / 1000);

        QVERIFY(alarms.deleteAlarm(first));
        QCOMPARE(scheduled.takeLast().at(0).toLongLong(), later / 1000);
        QVERIFY(alarms.disableAlarm(late));
        QCOMPARE(scheduled.takeLast().at(0).toLongLong(), 0);
    }

    void aOneOffAlarmTurnsOffOnceItRings() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QSignalSpy    triggered(&alarms, &AlarmManagerCpp::alarmTriggered);
        const QString nextMinute = QTime::currentTime().addSecs(60).toString("HH:mm");
        const QString once       = alarms.createAlarm(nextMinute, "Once", {}, {});
        const QString daily = alarms.createAlarm(nextMinute, "Daily", {0, 1, 2, 3, 4, 5, 6}, {});

        QTRY_COMPARE_WITH_TIMEOUT(triggered.count(), 2, 62000);
        QVERIFY(alarms.dismissAlarm(once));
        QVERIFY(alarms.dismissAlarm(daily));

        QVERIFY(listed(alarms.alarms(), once));
        const QJsonArray saved =
            QJsonDocument::fromJson(m_settings->get("alarms/data").toString().toUtf8()).array();
        QCOMPARE(saved.size(), 2);
        for (const auto &v : saved) {
            const QJsonObject a = v.toObject();
            QCOMPARE(a["enabled"].toBool(), a["id"].toString() == daily);
        }
        QVERIFY(alarms.hasEnabledAlarm());
    }

    void oneShotWithoutInstantIsRejected() {
        AlarmManagerCpp alarms(m_settings, nullptr, nullptr, nullptr);
        QTest::qWait(10);
        QVERIFY(alarms.createAlarm(QString(), "Timer", {}, {{"oneShot", true}}).isEmpty());
    }
};

QTEST_MAIN(TestAlarmManager)
#include "test_alarmmanager.moc"
