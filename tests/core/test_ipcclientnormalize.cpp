#include <QDBusConnection>
#include <QDBusVariant>
#include <QProcess>
#include <QThread>
#include <QTest>

#include "ipc/shellipcclients.h"
#include "marathon-app-native/src/alarms.cxxqt.h"
#include "marathon-app-native/src/contacts.cxxqt.h"
#include "marathon-app-native/src/permissions.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/shell.cxxqt.h"

// Stand in for the shell's services. They live on their own thread because
// the clients make blocking calls.
class FakeContacts : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Contacts1")

  public slots:
    QVariantList GetContacts() {
        return {person()};
    }
    QVariantList SearchContacts(const QString &) {
        return {person()};
    }
    QVariantMap GetContact(int) {
        return person();
    }

  private:
    static QVariantMap person() {
        return {{"id", 7}, {"name", "Test Person"}, {"phones", QVariantList{QVariantMap{{"number", "555"}}}}};
    }
};

class FakeAlarms : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Alarm1")

  public slots:
    QVariantList GetAlarms() {
        return {QVariantMap{{"id", "a1"}, {"time", "09:07"}, {"label", "Wake"}, {"repeat", QVariantList{1, 5}}}};
    }
    QVariantList GetActiveAlarms() {
        return GetAlarms();
    }
};

class FakeCallHistory : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.CallHistory1")

  public slots:
    QVariantList GetHistory() {
        return {QVariantMap{{"id", 3}, {"number", "555"}}};
    }
};

class FakePermissions : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

  public slots:
    bool HasPermission(const QString &, const QString &) {
        return true;
    }
};

class FakeSettings : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Settings1")

  public slots:
    QVariantMap GetState() {
        return {};
    }
    QDBusVariant Get(const QString &, const QDBusVariant &) {
        return QDBusVariant(QVariantList{QVariantMap{{"id", 1}, {"title", "Lunch"}}});
    }
};

class TestIpcClientNormalize : public QObject {
    Q_OBJECT

    QProcess        daemon;
    QThread         serviceThread;
    FakeContacts    contacts;
    FakeAlarms      alarms;
    FakeCallHistory history;
    FakePermissions permissions;
    FakeSettings    settings;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        qputenv("DBUS_SESSION_BUS_ADDRESS", address.toUtf8());

        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        for (QObject *o : {static_cast<QObject *>(&contacts), static_cast<QObject *>(&alarms),
                           static_cast<QObject *>(&history), static_cast<QObject *>(&permissions),
                           static_cast<QObject *>(&settings)})
            o->moveToThread(&serviceThread);
        serviceThread.start();
        const auto all = QDBusConnection::ExportAllSlots;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Contacts", &contacts, all));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Alarm", &alarms, all));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/CallHistory", &history, all));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Permissions", &permissions, all));
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Settings", &settings, all));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
    }
    void cleanupTestCase() {
        serviceThread.quit();
        serviceThread.wait();
        daemon.kill();
        daemon.waitForFinished();
    }

    void permissionWordsComeFromTheVocabulary() {
        marathon::platform::Permissions client;
        const QVariantMap phone = client.describe(QStringLiteral("phone"));
        QCOMPARE(phone.value("label").toString(), QStringLiteral("Phone"));
        QCOMPARE(phone.value("description").toString(),
                 client.describe(QStringLiteral("telephony")).value("description"));
        QVERIFY(!client.describe(QStringLiteral("secret-service")).value("description").toString().isEmpty());
        QCOMPARE(client.describe(QStringLiteral("root")).value("label").toString(), QStringLiteral("root"));
        QVERIFY(client.describe(QStringLiteral("system")).value("restricted").toBool());
        QVERIFY(!phone.value("restricted").toBool());
    }

    void contactFieldsReachQml() {
        marathon::platform::Contacts client;
        QTRY_COMPARE(client.getCount(), 1);
        const QVariantMap c = client.getContacts().constFirst().toMap();
        QCOMPARE(c.value("name").toString(), QString("Test Person"));
        QCOMPARE(c.value("id").toInt(), 7);
        QCOMPARE(c.value("phones").toList().constFirst().toMap().value("number").toString(), QString("555"));
        QCOMPARE(client.searchContacts(QStringLiteral("t")).constFirst().toMap().value("name").toString(), QString("Test Person"));
        QCOMPARE(client.getContact(7).value("phones").toList().size(), 1);
    }

    void alarmFieldsReachQml() {
        marathon::platform::Alarms client;
        QTRY_COMPARE(client.getAlarms().size(), 1);
        const QVariantMap a = client.getAlarms().constFirst().toMap();
        QCOMPARE(a.value("time").toString(), QString("09:07"));
        QCOMPARE(a.value("label").toString(), QString("Wake"));
        QCOMPARE(a.value("repeat").toList().size(), 2);
        QTRY_COMPARE(client.getActiveAlarms().size(), 1);
        QCOMPARE(client.getActiveAlarms().constFirst().toMap().value("id").toString(), QString("a1"));
    }

    void callHistoryFieldsReachQml() {
        CallHistoryClient client;
        QCOMPARE(client.history().constFirst().toMap().value("number").toString(), QString("555"));
    }

    void settingsGetReturnsPlainLists() {
        marathon::platform::set_app_id("calendar");
        marathon::platform::Settings client;
        const QVariantList events =
            client.get(QStringLiteral("calendar/events"), QVariant(QVariantList())).toList();
        QCOMPARE(events.size(), 1);
        QCOMPARE(events.first().toMap().value("title").toString(), QString("Lunch"));
    }
};

QTEST_MAIN(TestIpcClientNormalize)
#include "test_ipcclientnormalize.moc"
