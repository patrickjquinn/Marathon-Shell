// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Rust actions (#[keel::action], #[keel::entity]) served over D-Bus: the
// runtime finds the native table and the compiled-in manifest in a library
// loaded RTLD_LOCAL, validates against that manifest and dispatches
// synchronous, async and failing actions and entity reads.

#include <QDBusConnection>
#include <QDBusInterface>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtTest>

namespace {

QJsonObject object(const QDBusMessage &reply)
{
    return QJsonDocument::fromJson(reply.arguments().value(0).toString().toUtf8()).object();
}

} // namespace

class TestNative : public QObject
{
    Q_OBJECT

    QDBusInterface *m_iface = nullptr;

    QDBusMessage invoke(const QString &action, const QString &args)
    {
        return m_iface->call(QStringLiteral("Invoke"), action, args, QVariantMap());
    }

private Q_SLOTS:
    void initTestCase()
    {
        m_iface = new QDBusInterface(QStringLiteral("org.example.rustnotes"), QStringLiteral("/org/shipwright/Keel/Actions"),
                                     QStringLiteral("org.shipwright.Keel.Actions"), QDBusConnection::sessionBus(), this);
        m_iface->setTimeout(10000);
    }

    void compiledManifest()
    {
        const QDBusMessage reply = m_iface->call(QStringLiteral("Describe"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(object(reply).value(QLatin1String("appId")).toString(), QStringLiteral("org.example.rustnotes"));
    }

    void synchronous()
    {
        const QDBusMessage reply = invoke(QStringLiteral("math.add"), QStringLiteral(R"({"a":2,"b":3})"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(object(reply).value(QLatin1String("result")).toInt(), 5);
        QCOMPARE(invoke(QStringLiteral("math.add"), QStringLiteral(R"({"a":1001})")).errorName(),
                 QStringLiteral("org.shipwright.Keel.Actions.Error.InvalidArguments"));
    }

    void asynchronous()
    {
        const QDBusMessage reply = invoke(QStringLiteral("notes.titles"), QStringLiteral("{}"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(object(reply).value(QLatin1String("result")).toArray(),
                 QJsonArray({QStringLiteral("Rust note"), QStringLiteral("Second")}));
    }

    void failure()
    {
        const QDBusMessage reply = invoke(QStringLiteral("notes.fail"), QStringLiteral("{}"));
        QCOMPARE(reply.errorName(), QStringLiteral("org.shipwright.Keel.Actions.Error.NotAvailable"));
        QCOMPARE(reply.errorMessage(), QStringLiteral("the vault is locked"));
    }

    void entities()
    {
        QDBusMessage reply = m_iface->call(QStringLiteral("GetEntity"), QStringLiteral("note"), QStringLiteral("r1"));
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(object(reply).value(QLatin1String("uri")).toString(), QStringLiteral("keel://org.example.rustnotes/note/r1"));
        QCOMPARE(object(reply).value(QLatin1String("body")).toString(), QStringLiteral("Body one"));
        reply = m_iface->call(QStringLiteral("GetEntity"), QStringLiteral("note"), QStringLiteral("zz"));
        QCOMPARE(reply.errorName(), QStringLiteral("org.shipwright.Keel.Actions.Error.NotAvailable"));
        reply = m_iface->call(QStringLiteral("FindEntities"), QStringLiteral("note"), QString(), 1U);
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        const QJsonArray items = object(reply).value(QLatin1String("items")).toArray();
        QCOMPARE(items.size(), 1);
        QCOMPARE(items.at(0).toObject().value(QLatin1String("created")).toString(), QStringLiteral("2026-10-02"));
        QVERIFY(!items.at(0).toObject().contains(QLatin1String("body")));
    }
};

QTEST_GUILESS_MAIN(TestNative)
#include "tst_native.moc"
