#include <QFile>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

#include "managers/settingsmanager.h"

// autoLockTimeout became the lock delay; the old autoLock switch decides
// where an existing device starts.
class TestLockDelayMigration : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    void          writeOld(const QVariant &autoLock) {
        QSettings s("marathon-os", "Marathon Shell");
        s.clear();
        if (autoLock.isValid())
            s.setValue("system/autoLock", autoLock);
        s.setValue("system/autoLockTimeout", 300);
        s.sync();
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
        QVERIFY(QSettings("marathon-os", "Marathon Shell").fileName().startsWith(m_dir.path()));
    }

    void freshDeviceLocksImmediately() {
        {
            QSettings s("marathon-os", "Marathon Shell");
            s.clear();
            s.sync();
        }
        SettingsManager m;
        QCOMPARE(m.autoLockTimeout(), 0);
    }

    void autoLockOnBecomesImmediately() {
        writeOld(true);
        SettingsManager m;
        QCOMPARE(m.autoLockTimeout(), 0);
    }

    void autoLockOffBecomesLongestDelay() {
        writeOld(false);
        SettingsManager m;
        QCOMPARE(m.autoLockTimeout(), 300);
    }

    void chosenDelaySurvivesRestart() {
        writeOld(true);
        {
            SettingsManager m;
            m.setAutoLockTimeout(30);
        }
        SettingsManager m;
        QCOMPARE(m.autoLockTimeout(), 30);
    }
};

QTEST_GUILESS_MAIN(TestLockDelayMigration)
#include "test_lockdelaymigration.moc"
