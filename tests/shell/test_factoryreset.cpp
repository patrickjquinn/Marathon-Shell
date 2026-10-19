#include <QFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include "factoryreset.h"
#include "securitymanager.h"

namespace {

    // The root marathon-factory-reset service: reads one request line,
    // answers with `reply` and hangs up.
    class FakeService : public QObject {
        Q_OBJECT

      public:
        explicit FakeService(const QString &path, QByteArray reply) : m_reply(std::move(reply)) {
            QVERIFY(m_server.listen(path));
            connect(&m_server, &QLocalServer::newConnection, this, [this] {
                QLocalSocket *client = m_server.nextPendingConnection();
                connect(client, &QLocalSocket::readyRead, client, [this, client] {
                    if (!client->canReadLine())
                        return;
                    requests.append(client->readLine());
                    client->write(m_reply);
                    client->flush();
                    client->disconnectFromServer();
                });
            });
        }

        QList<QByteArray> requests;

      private:
        QLocalServer m_server;
        QByteArray   m_reply;
    };

    // NOLINTNEXTLINE(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString PIN = QStringLiteral("135724");

} // namespace

class TestFactoryReset : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    QString       socketPath() const {
        return m_dir.filePath(QStringLiteral("factory-reset.sock"));
    }

  private slots:
    void initTestCase() {
        // Its own config, not Qt's shared test-mode one: other tests that
        // set a PIN run in parallel.
        qputenv("XDG_CONFIG_HOME", m_dir.filePath("config").toLocal8Bit());
        qputenv("XDG_DATA_HOME", m_dir.filePath("data").toLocal8Bit());
        QVERIFY(m_dir.isValid());
    }

    void init() {
        QFile::remove(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
                      "/marathon/quickpin.conf");
    }

    void withoutTheServiceItIsUnsupported() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FactoryReset reset(&security, socketPath());
        QVERIFY(!reset.supported());
        QSignalSpy failed(&reset, &FactoryReset::failed);
        reset.erase(PIN);
        QCOMPARE(failed.count(), 1);
        QCOMPARE(failed.at(0).at(0).toString(), QStringLiteral("This device can't erase itself"));
    }

    void theRightPinAsksTheService() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FakeService  service(socketPath(), "ok\n");
        FactoryReset reset(&security, socketPath());
        QVERIFY(reset.supported());
        QSignalSpy failed(&reset, &FactoryReset::failed);
        reset.erase(PIN);
        QTRY_COMPARE(service.requests, QList<QByteArray>{"erase\n"});
        QTest::qWait(100);
        QCOMPARE(failed.count(), 0);
    }

    void aWrongPinNeverReachesTheService() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FakeService  service(socketPath(), "ok\n");
        FactoryReset reset(&security, socketPath());
        QSignalSpy   failed(&reset, &FactoryReset::failed);
        reset.erase(QStringLiteral("000000"));
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(failed.at(0).at(0).toString(), QStringLiteral("Incorrect PIN"));
        QCOMPARE(security.failedAttempts(), 1);
        QTest::qWait(100);
        QVERIFY(service.requests.isEmpty());
    }

    void lockedOutEvenTheRightPinIsRefused() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FakeService  service(socketPath(), "ok\n");
        FactoryReset reset(&security, socketPath());
        QSignalSpy   failed(&reset, &FactoryReset::failed);
        for (int i = 0; i < 5; ++i)
            reset.erase(QStringLiteral("000000"));
        QTRY_VERIFY(security.isLockedOut());
        reset.erase(PIN);
        QTRY_COMPARE(failed.count(), 6);
        QVERIFY(failed.last().at(0).toString().startsWith(QStringLiteral("Too many failed attempts")));
        QTest::qWait(100);
        QVERIFY(service.requests.isEmpty());
    }

    void withoutAPinTheSystemPasswordIsAsked() {
        SecurityManager security;
        QVERIFY(!security.hasQuickPIN());
        FakeService  service(socketPath(), "ok\n");
        FactoryReset reset(&security, socketPath());
        QSignalSpy   failed(&reset, &FactoryReset::failed);
        reset.erase(QStringLiteral("not the password"));
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(failed.at(0).at(0).toString(), QStringLiteral("Incorrect password"));
        QVERIFY(service.requests.isEmpty());
    }

    void theServicesRefusalIsPassedOn() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FakeService  service(socketPath(), "this device has no data partition to erase\n");
        FactoryReset reset(&security, socketPath());
        QSignalSpy   failed(&reset, &FactoryReset::failed);
        reset.erase(PIN);
        QTRY_COMPARE(failed.count(), 1);
        QCOMPARE(failed.at(0).at(0).toString(),
                 QStringLiteral("this device has no data partition to erase"));
    }

    void aServiceThatHangsUpSilentlyIsAFailure() {
        SecurityManager security;
        QVERIFY(security.setQuickPINFirstRun(PIN));
        FakeService  service(socketPath(), "");
        FactoryReset reset(&security, socketPath());
        QSignalSpy   failed(&reset, &FactoryReset::failed);
        reset.erase(PIN);
        QTRY_COMPARE(failed.count(), 1);
        QVERIFY(failed.at(0).at(0).toString().startsWith(
            QStringLiteral("Couldn't reach the erase service")));
    }
};

QTEST_MAIN(TestFactoryReset)
#include "test_factoryreset.moc"
