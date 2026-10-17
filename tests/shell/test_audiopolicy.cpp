#include <QMediaPlayer>
#include <QStandardPaths>
#include <QTest>

#include "audiopolicycontroller.h"
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
};

QTEST_MAIN(TestAudioPolicy)
#include "test_audiopolicy.moc"
