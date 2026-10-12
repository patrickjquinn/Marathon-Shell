#include <QSignalSpy>
#include <QStandardPaths>
#include <QTest>
#include "securitymanager.h"

class TestSecurityManager : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase() {
        QStandardPaths::setTestModeEnabled(true);
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                      "/marathon/quickpin.conf");
    }

    void wrongQuickPinsLockOut() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun("135724"));
        QSignalSpy failed(&security, &SecurityManager::authenticationFailed);
        for (int i = 1; i <= 5; ++i) {
            security.authenticateQuickPIN("000000");
            QTRY_COMPARE(failed.count(), i);
            QCOMPARE(security.failedAttempts(), i);
        }
        QVERIFY(security.isLockedOut());
    }
};

QTEST_MAIN(TestSecurityManager)
#include "test_securitymanager.moc"
