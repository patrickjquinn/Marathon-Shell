// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// org.shipwright.Keel.Actions round trip on a private session bus
// (dbus-run-session with session.conf): the test app is started by D-Bus
// activation, headless, serves Describe, Invoke, GetEntity, FindEntities
// and GetContext with validation, and quits when idle.

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtTest>

namespace {

const QString Service = QStringLiteral("org.example.notes");
const QString Path = QStringLiteral("/org/shipwright/Keel/Actions");
const QString Interface = QStringLiteral("org.shipwright.Keel.Actions");

QJsonObject object(const QString &json)
{
    return QJsonDocument::fromJson(json.toUtf8()).object();
}

} // namespace

class TestDBus : public QObject
{
    Q_OBJECT

    QDBusInterface *m_iface = nullptr;

    QDBusMessage call(const QString &method, const QVariantList &args = {})
    {
        return m_iface->callWithArgumentList(QDBus::Block, method, args);
    }

    QDBusMessage invoke(const QString &action, const QString &args)
    {
        return call(QStringLiteral("Invoke"), {action, args, QVariantMap{{QStringLiteral("userInitiated"), true}}});
    }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(QDBusConnection::sessionBus().isConnected());
        QVERIFY(!QDBusConnection::sessionBus().interface()->isServiceRegistered(Service));
        m_iface = new QDBusInterface(Service, Path, Interface, QDBusConnection::sessionBus(), this);
        m_iface->setTimeout(10000);
    }

    void activationAndDescribe()
    {
        // The first call activates the app (headless, through the .service file).
        const QDBusMessage reply = call(QStringLiteral("Describe"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonObject manifest = object(reply.arguments().value(0).toString());
        QCOMPARE(manifest.value(QLatin1String("appId")).toString(), Service);
        QCOMPARE(manifest.value(QLatin1String("tools")).toArray().size(), 7);
    }

    void invoke()
    {
        const QDBusMessage reply = invoke(QStringLiteral("notes.create"), QStringLiteral(R"({"title":"From D-Bus","body":"x"})"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonObject result = object(reply.arguments().value(0).toString());
        QCOMPARE(result.value(QLatin1String("id")).toString(), QStringLiteral("n3"));
        QCOMPARE(result.value(QLatin1String("note")).toString(), QStringLiteral("keel://org.example.notes/note/n3"));
    }

    void errors_data()
    {
        QTest::addColumn<QString>("action");
        QTest::addColumn<QString>("arguments");
        QTest::addColumn<QString>("error");
        QTest::newRow("missing required") << "notes.create" << R"({"title":"x"})" << "InvalidArguments";
        QTest::newRow("too long") << "notes.search" << QStringLiteral(R"({"query":"%1"})").arg(QString(300, QLatin1Char('q'))) << "InvalidArguments";
        QTest::newRow("not json") << "notes.create" << "{body" << "InvalidArguments";
        QTest::newRow("not an object") << "notes.create" << "[1]" << "InvalidArguments";
        QTest::newRow("entity pattern") << "notes.delete" << R"({"note":"n1"})" << "InvalidArguments";
        QTest::newRow("unknown") << "notes.fly" << "{}" << "UnknownAction";
        QTest::newRow("result schema") << "notes.broken" << "{}" << "Failed";
        QTest::newRow("timeout") << "notes.share"
                                 << R"({"note":"keel://org.example.notes/note/n1","to":"keel://org.example.contacts/contact/c1"})"
                                 << "Timeout";
    }

    void errors()
    {
        QFETCH(QString, action);
        QFETCH(QString, arguments);
        QFETCH(QString, error);
        const QDBusMessage reply = invoke(action, arguments);
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QCOMPARE(reply.errorName(), QStringLiteral("org.shipwright.Keel.Actions.Error.") + error);
        QVERIFY(!reply.errorMessage().isEmpty());
    }

    void asynchronous()
    {
        const QDBusMessage reply = invoke(QStringLiteral("notes.later"), QStringLiteral(R"({"text":"soon"})"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(object(reply.arguments().value(0).toString()).value(QLatin1String("result")).toString(), QStringLiteral("soon"));
    }

    void entities()
    {
        QDBusMessage reply = call(QStringLiteral("GetEntity"), {QStringLiteral("note"), QStringLiteral("n2")});
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonObject note = object(reply.arguments().value(0).toString());
        QCOMPARE(note.value(QLatin1String("title")).toString(), QStringLiteral("Trattoria Anna"));
        QVERIFY(note.contains(QLatin1String("body")));

        reply = call(QStringLiteral("GetEntity"), {QStringLiteral("note"), QStringLiteral("nope")});
        QCOMPARE(reply.errorName(), QStringLiteral("org.shipwright.Keel.Actions.Error.NotAvailable"));

        reply = call(QStringLiteral("FindEntities"), {QStringLiteral("note"), QStringLiteral("anna"), 5U});
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonArray items = object(reply.arguments().value(0).toString()).value(QLatin1String("items")).toArray();
        QCOMPARE(items.size(), 1);
        QCOMPARE(items.at(0).toObject().value(QLatin1String("uri")).toString(), QStringLiteral("keel://org.example.notes/note/n2"));
        QVERIFY(!items.at(0).toObject().contains(QLatin1String("body")));
    }

    void context()
    {
        const QDBusMessage reply = call(QStringLiteral("GetContext"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonObject context = object(reply.arguments().value(0).toString());
        QCOMPARE(context.value(QLatin1String("purpose")).toString(), QStringLiteral("reading a note"));
    }

    void quitsWhenIdle()
    {
        // KEEL_ACTIONS_IDLE_MS is 1500 in this test.
        QTRY_VERIFY_WITH_TIMEOUT(!QDBusConnection::sessionBus().interface()->isServiceRegistered(Service), 8000);
    }
};

QTEST_GUILESS_MAIN(TestDBus)
#include "tst_dbus.moc"
