#include "ipc/dbusnormalize.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusServer>
#include <QDBusVariant>
#include <QSignalSpy>
#include <QTest>

// Replies only carry QDBusArgument values after a real round trip, so the
// test serves them over an in-process peer-to-peer bus.
class Echo : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Test")

  public slots:
    QVariantMap State() {
        QVariantMap defaultApps{{"browser", "browser"}, {"music", "music"}};
        return {{"timeFormat", "24h"},
                {"defaultApps", defaultApps},
                {"recent", QVariantList{1, "two"}},
                {"names", QStringList{"a", "b"}}};
    }
};

class TestDbusNormalize : public QObject {
    Q_OBJECT

    QDBusServer *m_server = nullptr;
    Echo         m_echo;
    QString      m_name;

    QVariant callState() {
        QDBusConnection client = QDBusConnection::connectToPeer(m_server->address(), m_name);
        QDBusMessage    msg = QDBusMessage::createMethodCall({}, "/echo", "org.marathonos.Test", "State");
        // Async: the server shares this thread, so a blocking call would deadlock.
        QDBusPendingCallWatcher watcher(client.asyncCall(msg));
        QSignalSpy              done(&watcher, &QDBusPendingCallWatcher::finished);
        if (!done.wait(5000) || watcher.isError() || watcher.reply().arguments().isEmpty())
            return {};
        return watcher.reply().arguments().constFirst();
    }

  private slots:
    void initTestCase() {
        m_server = new QDBusServer(this);
        QVERIFY(m_server->isConnected());
        connect(m_server, &QDBusServer::newConnection, this, [this](const QDBusConnection &c) {
            QDBusConnection(c).registerObject("/echo", &m_echo, QDBusConnection::ExportAllSlots);
        });
        m_name = QStringLiteral("peer");
    }

    void nestedMapReplyNormalizes() {
        const QVariant raw = callState();
        QCOMPARE(raw.userType(), qMetaTypeId<QDBusArgument>());

        const QVariantMap state = normalizeDbusVariantDeep(raw).toMap();
        QCOMPARE(state.value("timeFormat").toString(), QStringLiteral("24h"));
        QCOMPARE(state.value("defaultApps").toMap().value("music").toString(), QStringLiteral("music"));
        QCOMPARE(state.value("recent").toList().size(), 2);
        QCOMPARE(state.value("names").toStringList(), (QStringList{"a", "b"}));
    }

    void nestedArgumentListUnwraps() {
        const QVariantMap state = normalizeDbusVariantDeep(callState()).toMap();
        QCOMPARE(unwrapDbusVariantList(state.value("recent")).size(), 2);
    }
};

QTEST_MAIN(TestDbusNormalize)
#include "test_dbusnormalize.moc"
