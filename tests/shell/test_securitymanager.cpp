#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include "marathon-shell-native/src/security.cxxqt.h"

class TestSecurityManager : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    // A stand-in for marathon-data-key: logs "<command> <stdin>", exits with code.
    QString fakeHelper(const QString &log, int code) {
        QString path = m_dir.filePath(QStringLiteral("helper-%1").arg(code));
        QFile   f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return {};
        f.write(QStringLiteral("#!/bin/sh\nprintf '%s %s' \"$1\" \"$(cat)\" > \"$0.tmp\"\n"
                               "mv \"$0.tmp\" '%1'\nexit %2\n")
                    .arg(log, QString::number(code))
                    .toUtf8());
        f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        return path;
    }

    static QByteArray readFile(const QString &path) {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }

    static void removePin() {
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                      "/marathon/quickpin.conf");
    }

  private slots:
    void initTestCase() {
        // Its own config, not Qt's shared test-mode one: other tests that
        // set a PIN run in parallel.
        qputenv("XDG_CONFIG_HOME", m_dir.filePath("config").toLocal8Bit());
        qputenv("XDG_DATA_HOME", m_dir.filePath("data").toLocal8Bit());
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                      "/marathon/quickpin.conf");
    }

    void firstRunPinBecomesTheStartupPin() {
        const QString log = m_dir.filePath("helper.log");
        qputenv("MARATHON_DATA_KEY_HELPER", fakeHelper(log, 0).toLocal8Bit());
        Security security;
        QVERIFY(security.setQuickPINFirstRun("246813"));
        QTRY_COMPARE(readFile(log), QByteArray("set 246813"));
        QVERIFY(security.getHasQuickPIN());
        removePin();
    }

    void aFailedStartupPinKeepsTheQuickPin() {
        const QString log = m_dir.filePath("failed.log");
        qputenv("MARATHON_DATA_KEY_HELPER", fakeHelper(log, 1).toLocal8Bit());
        Security security;
        QVERIFY(security.setQuickPINFirstRun("246813"));
        QTRY_COMPARE(readFile(log), QByteArray("set 246813"));
        QVERIFY(security.getHasQuickPIN());
        removePin();
    }

    void aWrongPasswordLeavesTheStartupPinAlone() {
        const QString log = m_dir.filePath("password.log");
        qputenv("MARATHON_DATA_KEY_HELPER", fakeHelper(log, 0).toLocal8Bit());
        Security security;
        QSignalSpy      failed(&security, &Security::authenticationFailed);
        security.setQuickPIN("111111", "not the password");
        QTRY_COMPARE(failed.count(), 1);
        security.removeQuickPIN("not the password");
        QTRY_COMPARE(failed.count(), 2);
        QTest::qWait(200);
        QVERIFY(!QFile::exists(log));
    }

    void theRightPinUnlocksAndClearsTheCount() {
        qunsetenv("MARATHON_DATA_KEY_HELPER");
        Security security;
        QVERIFY(security.setQuickPINFirstRun("975310"));
        QSignalSpy failed(&security, &Security::authenticationFailed);
        QSignalSpy unlocked(&security, &Security::authenticationSuccess);
        security.authenticateQuickPIN("000000");
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(security.getFailedAttempts(), 1);
        security.authenticateQuickPIN("975310");
        QTRY_COMPARE(unlocked.count(), 1);
        QCOMPARE(security.getFailedAttempts(), 0);
        removePin();
    }

    void wrongQuickPinsLockOut() {
        qunsetenv("MARATHON_DATA_KEY_HELPER");
        Security security;
        QVERIFY(security.setQuickPINFirstRun("135724"));
        QSignalSpy failed(&security, &Security::authenticationFailed);
        for (int i = 1; i <= 5; ++i) {
            security.authenticateQuickPIN("000000");
            QTRY_COMPARE(failed.count(), i);
            QCOMPARE(security.getFailedAttempts(), i);
        }
        QVERIFY(security.isLockedOut());
    }
};

QTEST_MAIN(TestSecurityManager)
#include "test_securitymanager.moc"
