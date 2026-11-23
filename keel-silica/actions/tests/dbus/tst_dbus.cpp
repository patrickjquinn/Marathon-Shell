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
#include <QProcess>
#include <QStandardPaths>
#include <QtTest>

namespace {

const QString Service = QStringLiteral("org.example.notes");
const QString Path = QStringLiteral("/org/shipwright/Keel/Actions");
const QString Interface = QStringLiteral("org.shipwright.Keel.Actions");
const QJsonObject Yes{{QStringLiteral("result"), true}};
const QJsonObject No{{QStringLiteral("result"), false}};

QJsonObject object(const QString &json)
{
    return QJsonDocument::fromJson(json.toUtf8()).object();
}

} // namespace

// The shell's Permissions1.SpeaksForPerson, vouching for the bus names in
// `vouched`.
class FakeShell : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Permissions1")

public:
    using QObject::QObject;

    QStringList vouched;
    QStringList asked;

public Q_SLOTS:
    bool SpeaksForPerson(const QString &sender)
    {
        asked << sender;
        return vouched.contains(sender);
    }
};

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

    FakeShell *m_shell = nullptr;

    FakeShell *shell()
    {
        if (!m_shell) {
            m_shell = new FakeShell(this);
            QDBusConnection bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("shell"));
            bus.registerObject(QStringLiteral("/org/marathonos/Shell/Permissions"), m_shell,
                               QDBusConnection::ExportAllSlots);
            bus.registerService(QStringLiteral("org.marathonos.Shell"));
        }
        return m_shell;
    }

    // The test app serving `service`; in a PID namespace of its own, as apps
    // run in bubblewrap on the phone, when `sandboxed`.
    void startInitiatedHost(QProcess &host, const QString &service, bool sandboxed)
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("KEEL_ACTIONS_DBUS"), QStringLiteral("1"));
        env.insert(QStringLiteral("KEEL_ACTIONS_APP_ID"), service);
        host.setProcessEnvironment(env);
        host.setProcessChannelMode(QProcess::ForwardedChannels);
        QString program = QStringLiteral(KEEL_ACTIONS_TEST_HOST);
        QStringList args{QStringLiteral("--no-env-manifest"), QStringLiteral(KEEL_ACTIONS_INITIATED_APP)};
        if (sandboxed) {
            args = QStringList{QStringLiteral("--dev-bind"), QStringLiteral("/"), QStringLiteral("/"),
                               QStringLiteral("--unshare-pid"), QStringLiteral("--proc"), QStringLiteral("/proc"),
                               QStringLiteral("--die-with-parent"), QStringLiteral("--"), program}
                + args;
            program = QStandardPaths::findExecutable(QStringLiteral("bwrap"));
        }
        host.start(program, args);
        QVERIFY(host.waitForStarted());
        QTRY_VERIFY_WITH_TIMEOUT(QDBusConnection::sessionBus().interface()->isServiceRegistered(service), 10000);
    }

    // What the test app heard about a call from `bus` that claims
    // `claimed`: {"result": <whether the person started it>}.
    QJsonObject heard(const QString &service, const QDBusConnection &bus, bool claimed)
    {
        QDBusInterface probe(service, Path, Interface, bus);
        probe.setTimeout(10000);
        // With an event loop: the stand-in shell answers from this thread.
        const QDBusMessage reply = probe.call(QDBus::BlockWithGui, QStringLiteral("Invoke"),
                                              QStringLiteral("probe.initiated"), QStringLiteral("{}"),
                                              QVariantMap{{QStringLiteral("userInitiated"), claimed}});
        return object(reply.arguments().value(0).toString());
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
        // Six declared actions, the note's find tool and the built-in app.show.
        QCOMPARE(manifest.value(QLatin1String("tools")).toArray().size(), 8);
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

    // userInitiated is the sender's to prove, not to claim: this test process
    // is neither Pilot, keel-mcp nor the app, so the app hears false
    // (keel/actions/plugin/keelcallertrust.h; the trusted side is covered by
    // tst_keel_actions_callertrust). An app outside a sandbox sees the
    // caller's process itself and does not take the shell's word for it.
    void userInitiatedFromAnUntrustedCaller()
    {
        const QString service = QStringLiteral("org.example.initiated");
        shell()->vouched = {QDBusConnection::sessionBus().baseService()};
        QProcess host;
        startInitiatedHost(host, service, false);
        for (const bool claimed : {true, false})
            QCOMPARE(heard(service, QDBusConnection::sessionBus(), claimed), No);
        host.terminate();
        if (!host.waitForFinished(5000))
            host.kill();
    }

    // A sandboxed app cannot see the caller's process (another PID
    // namespace), so it asks the shell, and believes whom the shell vouches
    // for: Pilot and keel-mcp on the phone, here this test's own name.
    void userInitiatedInASandboxIsTheShellsToVouch()
    {
        if (QStandardPaths::findExecutable(QStringLiteral("bwrap")).isEmpty())
            QSKIP("bubblewrap is not installed");
        const QString service = QStringLiteral("org.example.initiated.sandboxed");
        const QString me = QDBusConnection::sessionBus().baseService();
        QDBusConnection stranger = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("stranger"));
        shell()->vouched = {me};
        shell()->asked.clear();
        QProcess host;
        startInitiatedHost(host, service, true);
        QCOMPARE(heard(service, QDBusConnection::sessionBus(), true), Yes);
        QCOMPARE(heard(service, QDBusConnection::sessionBus(), false), No);
        QCOMPARE(heard(service, stranger, true), No);
        // Asked once per caller: the answer is kept while the name lives.
        QCOMPARE(heard(service, QDBusConnection::sessionBus(), true), Yes);
        QCOMPARE(shell()->asked, QStringList({me, stranger.baseService()}));
        // Without a shell to ask (Sailfish OS), nobody else is believed.
        QVERIFY(QDBusConnection(QStringLiteral("shell")).unregisterService(QStringLiteral("org.marathonos.Shell")));
        QDBusConnection other = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("other"));
        shell()->vouched << other.baseService();
        QCOMPARE(heard(service, other, true), No);
        host.terminate();
        if (!host.waitForFinished(5000))
            host.kill();
    }

    void quitsWhenIdle()
    {
        // KEEL_ACTIONS_IDLE_MS is 1500 in this test.
        QTRY_VERIFY_WITH_TIMEOUT(!QDBusConnection::sessionBus().interface()->isServiceRegistered(Service), 8000);
    }
};

QTEST_GUILESS_MAIN(TestDBus)
#include "tst_dbus.moc"
