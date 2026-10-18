#include <QAudioOutput>
#include <QFile>
#include <QMediaPlayer>
#include <QStandardPaths>
#include <QTest>

#include "audiomanagercpp.h"
#include "audiopolicycontroller.h"
#include "mediarole.h"
#include "settingsmanager.h"

class TestAudioPolicy : public QObject {
    Q_OBJECT

    SettingsManager *m_settings = nullptr;

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        m_settings = new SettingsManager(this);
    }

    void init() {
        m_settings->setDndEnabled(false);
        m_settings->setAudioProfile("normal");
    }

    void ringerFollowsTheProfile_data() {
        QTest::addColumn<QString>("profile");
        QTest::addColumn<bool>("dnd");
        QTest::addColumn<bool>("audible");
        QTest::newRow("normal") << "normal" << false << true;
        QTest::newRow("loud") << "loud" << false << true;
        QTest::newRow("silent") << "silent" << false << false;
        QTest::newRow("vibrate") << "vibrate" << false << false;
        QTest::newRow("dnd") << "normal" << true << false;
    }
    void ringerFollowsTheProfile() {
        QFETCH(QString, profile);
        QFETCH(bool, dnd);
        QFETCH(bool, audible);
        QCOMPARE(AudioPolicyController::ringerAudible(profile, dnd), audible);
    }

    // The media mute no longer silences them: they play outside its role.
    void silentProfileStartsNoRingtoneOrNotification() {
        AudioPolicyController policy(nullptr, m_settings, nullptr);
        for (const char *profile : {"silent", "vibrate"}) {
            m_settings->setAudioProfile(profile);
            policy.playRingtone();
            policy.playNotificationSound();
            QVERIFY2(policy.findChildren<QMediaPlayer *>().isEmpty(), profile);
        }
    }

    // The volume slider scales notification sounds; their own setting sets
    // their level under it.
    void notificationsFollowTheVolume() {
        AudioManagerCpp audio;
        audio.setVolume(0.5);
        m_settings->setNotificationVolume(0.8);
        m_settings->setNotificationSound("/nonexistent/notification.ogg");
        AudioPolicyController policy(&audio, m_settings, nullptr);
        policy.playNotificationSound();
        const QList<QAudioOutput *> outputs = policy.findChildren<QAudioOutput *>();
        QCOMPARE(outputs.size(), 1);
        QAudioOutput *output = outputs.first();
        QVERIFY(qAbs(output->volume() - 0.4f) < 0.01f);
        audio.setVolume(0.25);
        QVERIFY(qAbs(output->volume() - 0.2f) < 0.01f);
        m_settings->setNotificationVolume(0.4);
        QVERIFY(qAbs(output->volume() - 0.1f) < 0.01f);
        audio.setMuted(true);
        QCOMPARE(output->volume(), 0.0f);
    }

    // Alarms and ringtones play on their own role, not scaled by media's.
    void soundsPlayOnTheirRole() {
        if (!qEnvironmentVariableIsSet("MARATHON_MEDIA_ROLES"))
            QSKIP("needs PipeWire; run through with-media-roles.sh");
        QTRY_COMPARE_WITH_TIMEOUT(MediaRole::output("alarm").id(), MediaRole::sinkName("alarm"),
                                  10000);
        m_settings->setAlarmSound("/nonexistent/alarm.ogg");
        m_settings->setRingtone("/nonexistent/ringtone.ogg");
        AudioPolicyController policy(nullptr, m_settings, nullptr);
        policy.playAlarmSound();
        policy.playRingtone();
        QList<QByteArray> devices;
        const QList<QAudioOutput *> outputs = policy.findChildren<QAudioOutput *>();
        for (const QAudioOutput *output : outputs)
            devices << output->device().id();
        policy.stopAlarmSound();
        policy.stopRingtone();
        std::sort(devices.begin(), devices.end());
        QCOMPARE(
            devices,
            (QList<QByteArray>{MediaRole::sinkName("alarm"), MediaRole::sinkName("ringtone")}));
    }

    // module-loopback names a role's sink input.<node.name>; the shell's
    // sounds ask for loopbacks Marathon's WirePlumber config creates.
    void soundsUseShippedRoles() {
        QFile conf(MARATHON_SOURCE_DIR "/crates/marathon-audiod/data/wireplumber/"
                                       "wireplumber.conf.d/61-marathon-media-roles.conf");
        QVERIFY(conf.open(QIODevice::ReadOnly));
        const QByteArray text = conf.readAll();
        for (const char *role : {"alarm", "ringtone", "notification"}) {
            const QByteArray sink = MediaRole::sinkName(role);
            QVERIFY(sink.startsWith("input."));
            QVERIFY2(text.contains("node.name = \"" + sink.mid(6) + '"'), sink.constData());
        }
    }
};

QTEST_MAIN(TestAudioPolicy)
#include "test_audiopolicy.moc"
