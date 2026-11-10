// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Share on a private session bus. ShareAction.trigger() falls back
// to the clipboard while no system share dialog is on the bus, and calls
// org.sailfishos.share.share(a{sv}) with its configuration once a fake
// dialog is there (file URLs as paths). A ShareProvider is the app's share
// target: the dialog's share() call on /share/<method> reaches onTriggered
// with ShareResource objects (file paths, data, a file handed over as a
// descriptor), the bus name is registered with registerName, and content
// outside the provider's capabilities is refused.

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusUnixFileDescriptor>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QTemporaryFile>
#include <QTest>
#include <memory>

namespace {

class FakeShareDialog : public QDBusVirtualObject
{
public:
    FakeShareDialog()
        : m_bus(QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("dialog")))
    {
    }
    ~FakeShareDialog() override
    {
        m_bus.unregisterService(QStringLiteral("org.sailfishos.share"));
        m_bus.unregisterObject(QStringLiteral("/"));
    }
    bool start()
    {
        return m_bus.registerVirtualObject(QStringLiteral("/"), this)
            && m_bus.registerService(QStringLiteral("org.sailfishos.share"));
    }
    QString introspect(const QString &) const override { return QString(); }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &) override
    {
        if (message.interface() != QLatin1String("org.sailfishos.share") || message.member() != QLatin1String("share"))
            return false;
        calls.append(message);
        if (message.isReplyRequired())
            m_bus.send(message.createReply());
        return true;
    }
    QList<QDBusMessage> calls;

private:
    QDBusConnection m_bus;
};

QVariant unwrap(const QVariant &value)
{
    return value.metaType() == QMetaType::fromType<QDBusVariant>() ? qvariant_cast<QDBusVariant>(value).variant()
                                                                  : value;
}

QVariantMap toMap(const QVariant &value)
{
    QVariantMap map;
    qvariant_cast<QDBusArgument>(value) >> map;
    return map;
}

} // namespace

class tst_Share : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void actionFallsBackToClipboard();
    void actionOpensSystemDialog();
    void providerReceivesShares();

private:
    QDBusMessage callApp(const QString &method, const QVariantMap &configuration);
    std::unique_ptr<QQmlEngine> m_engine;
    QTemporaryDir m_dir;
};

void tst_Share::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    QVERIFY(m_dir.isValid());
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_Share::actionFallsBackToClipboard()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(import QtQuick 2.0
import Sailfish.Share 1.0
ShareAction {
    property string sharedText: "unset"
    mimeType: "text/x-url"
    resources: [{ "type": "text/x-url", "linkTitle": "Keel", "status": "https://example.org/keel" }]
    on_Shared: function(text) { sharedText = text }
})QML",
              QUrl(QStringLiteral("fallback.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QVERIFY(QMetaObject::invokeMethod(o.get(), "trigger"));
    QCOMPARE(o->property("sharedText").toString(), QStringLiteral("https://example.org/keel"));
}

void tst_Share::actionOpensSystemDialog()
{
    FakeShareDialog dialog;
    QVERIFY(dialog.start());
    const QString image = m_dir.filePath(QStringLiteral("a.png"));
    QQmlComponent c(m_engine.get());
    c.setData(QStringLiteral(R"QML(import QtQuick 2.0
import Sailfish.Share 1.0
ShareAction {
    property string sharedText: "unset"
    title: "Share image"
    mimeType: "image/png"
    resources: [Qt.resolvedUrl("file://%1"), { "name": "note.txt", "data": "hello" }]
    on_Shared: function(text) { sharedText = text }
})QML").arg(image).toUtf8(),
              QUrl(QStringLiteral("dialog.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QVERIFY(QMetaObject::invokeMethod(o.get(), "trigger"));
    QTRY_COMPARE(dialog.calls.size(), 1);
    QCOMPARE(o->property("sharedText").toString(), QStringLiteral("unset")); // no fallback

    const QDBusMessage call = dialog.calls.first();
    QCOMPARE(call.path(), QStringLiteral("/"));
    QCOMPARE(call.signature(), QStringLiteral("a{sv}"));
    const QVariantMap config = toMap(call.arguments().value(0));
    QCOMPARE(config.value(QStringLiteral("mimeType")).toString(), QStringLiteral("image/png"));
    QCOMPARE(config.value(QStringLiteral("title")).toString(), QStringLiteral("Share image"));
    QVERIFY(config.contains(QStringLiteral("selectedTransferMethodInfo")));
    QVariantList resources;
    qvariant_cast<QDBusArgument>(config.value(QStringLiteral("resources"))) >> resources;
    QCOMPARE(resources.size(), 2);
    QCOMPARE(unwrap(resources.at(0)).toString(), image);
    const QVariantMap data = toMap(unwrap(resources.at(1)));
    QCOMPARE(data.value(QStringLiteral("name")).toString(), QStringLiteral("note.txt"));
    QCOMPARE(data.value(QStringLiteral("data")).toString(), QStringLiteral("hello"));
}

QDBusMessage tst_Share::callApp(const QString &method, const QVariantMap &configuration)
{
    // From another connection, as the system dialog calls the app; waited
    // for with this thread's event loop, which answers it.
    QDBusConnection dialog = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("dialog2"));
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.keel.sharetest"), QStringLiteral("/share/") + method,
                                                    QStringLiteral("org.sailfishos.share"), QStringLiteral("share"));
    m.setArguments({ configuration });
    QDBusPendingCall pending = dialog.asyncCall(m);
    QElapsedTimer timer;
    timer.start();
    while (!pending.isFinished() && timer.elapsed() < 5000)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return pending.isFinished() ? pending.reply() : QDBusMessage();
}

void tst_Share::providerReceivesShares()
{
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(import QtQuick 2.0
import Sailfish.Share 1.0
ShareProvider {
    property var received: []
    method: "images"
    registerName: true
    capabilities: ["image/*", "text/plain"]
    onTriggered: function(resources) {
        var out = []
        for (var i = 0; i < resources.length; ++i) {
            var r = resources[i]
            out.push({ "type": r.type, "name": r.name, "data": r.data, "filePath": r.filePath,
                       "isFile": r.type === ShareResource.FilePathType })
        }
        received = out
    }
})QML",
              QUrl(QStringLiteral("provider.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    QTRY_VERIFY(QDBusConnection::sessionBus().interface()->isServiceRegistered(QStringLiteral("org.keel.sharetest")).value());

    // A file path and a data resource.
    QDBusMessage reply = callApp(QStringLiteral("images"),
                                 { { QStringLiteral("mimeType"), QStringLiteral("image/png") },
                                   { QStringLiteral("resources"),
                                     QVariantList { QStringLiteral("/home/user/Pictures/a.png"),
                                                    QVariantMap { { QStringLiteral("name"), QStringLiteral("n.txt") },
                                                                  { QStringLiteral("data"), QStringLiteral("hi") } } } } });
    QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
    QVariantList received = o->property("received").toList();
    QCOMPARE(received.size(), 2);
    QVariantMap first = received.at(0).toMap();
    QVERIFY(first.value(QStringLiteral("isFile")).toBool());
    QCOMPARE(first.value(QStringLiteral("filePath")).toString(), QStringLiteral("/home/user/Pictures/a.png"));
    QCOMPARE(first.value(QStringLiteral("name")).toString(), QStringLiteral("a.png"));
    QVariantMap second = received.at(1).toMap();
    QCOMPARE(second.value(QStringLiteral("type")).toInt(), 1); // StringDataType
    QCOMPARE(second.value(QStringLiteral("data")).toString(), QStringLiteral("hi"));

    // A file handed over as a descriptor arrives as a copy the app can read.
    QTemporaryFile source;
    QVERIFY(source.open());
    source.write("picture bytes");
    source.flush();
    source.seek(0);
    reply = callApp(QStringLiteral("images"),
                    { { QStringLiteral("mimeType"), QStringLiteral("image/jpeg") },
                      { QStringLiteral("resources"),
                        QVariantList { QVariantMap {
                            { QStringLiteral("name"), QStringLiteral("photo.jpg") },
                            { QStringLiteral("fileDescriptor"),
                              QVariant::fromValue(QDBusUnixFileDescriptor(source.handle())) } } } } });
    QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
    received = o->property("received").toList();
    QCOMPARE(received.size(), 1);
    const QString copy = received.at(0).toMap().value(QStringLiteral("filePath")).toString();
    QVERIFY(copy.endsWith(QLatin1String("/photo.jpg")));
    QFile copied(copy);
    QVERIFY(copied.open(QIODevice::ReadOnly));
    QCOMPARE(copied.readAll(), QByteArray("picture bytes"));

    // Outside the capabilities, and an unknown method: refused.
    reply = callApp(QStringLiteral("images"), { { QStringLiteral("mimeType"), QStringLiteral("audio/ogg") },
                                                { QStringLiteral("resources"), QVariantList { QStringLiteral("/a.ogg") } } });
    QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
    QCOMPARE(reply.errorName(), QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs"));
    reply = callApp(QStringLiteral("video"), { { QStringLiteral("resources"), QVariantList { QStringLiteral("/a.mp4") } } });
    QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);

    // The copy goes with the provider.
    o.reset();
    QVERIFY(!QFile::exists(copy));
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("org.keel"));
    QCoreApplication::setApplicationName(QStringLiteral("sharetest"));
    tst_Share test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_share.moc"
