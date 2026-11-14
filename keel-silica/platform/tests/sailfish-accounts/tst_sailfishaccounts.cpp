// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Accounts (sailfish-components-accounts for Qt 6) on a private
// accounts database and bus, with a fake signond on its peer-to-peer socket
// ($XDG_RUNTIME_DIR/signond/socket, as Sailfish's libsignon uses it):
//   - AccountManager lists the providers and services, creates an account,
//     and the account is in the database for the C++ API;
//   - an Account loads it, writes its display name, configuration and
//     service state back;
//   - createSignInCredentials() stores an identity in signond (store), runs
//     its authentication session (process) and records the credentials for
//     the application; signIn() runs the session again and returns signond's
//     reply;
//   - AccountModel lists the account; AccountSyncManager (Buteo profiles)
//     loads with no profiles.

#include <Accounts/Account>
#include <Accounts/Manager>

#include <QAbstractItemModel>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusMessage>
#include <QDBusServer>
#include <QDBusVirtualObject>
#include <QDir>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <memory>

namespace {

const QString SsoPrefix = QStringLiteral("com.google.code.AccountsSSO.SingleSignOn");
const QString DaemonPath = QStringLiteral("/com/google/code/AccountsSSO/SingleSignOn");

struct Call
{
    QString path;
    QString member;
    QVariantList args;
};

QVariantMap toMap(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QDBusArgument>())
        return qdbus_cast<QVariantMap>(value.value<QDBusArgument>());
    return value.toMap();
}

// Answers libsignon's AuthService, Identity and AuthSession calls.
class FakeSignond : public QDBusVirtualObject
{
public:
    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        calls.append({ message.path(), message.member(), message.arguments() });
        const QString iface = message.interface();
        const QString member = message.member();
        QVariantList reply;
        if (iface == SsoPrefix + QLatin1String(".AuthService")) {
            if (member == QLatin1String("registerNewIdentity")) {
                reply << QVariant::fromValue(QDBusObjectPath(DaemonPath + QStringLiteral("/Identity_new")));
            } else if (member == QLatin1String("getIdentity")) {
                const quint32 id = message.arguments().value(0).toUInt();
                reply << QVariant::fromValue(QDBusObjectPath(DaemonPath + QStringLiteral("/Identity_%1").arg(id)))
                      << QVariant::fromValue(identities.value(id));
            } else if (member == QLatin1String("getAuthSessionObjectPath")) {
                reply << QVariant::fromValue(QDBusObjectPath(
                    DaemonPath + QStringLiteral("/AuthSession_%1").arg(message.arguments().value(0).toUInt())));
            } else if (member == QLatin1String("queryMethods") || member == QLatin1String("queryMechanisms")) {
                reply << QStringList { QStringLiteral("password") };
            }
        } else if (iface == SsoPrefix + QLatin1String(".Identity")) {
            if (member == QLatin1String("store")) {
                QVariantMap info = toMap(message.arguments().value(0));
                quint32 id = info.value(QStringLiteral("Id")).toUInt();
                if (id == 0)
                    id = nextId++;
                info.insert(QStringLiteral("Id"), id);
                info.remove(QStringLiteral("Secret"));
                identities.insert(id, info);
                reply << id;
            } else if (member == QLatin1String("getInfo")) {
                const quint32 id = message.path().section(QLatin1Char('_'), -1).toUInt();
                reply << QVariant::fromValue(identities.value(id));
            } else if (member == QLatin1String("addReference") || member == QLatin1String("removeReference")) {
                reply << 0;
            } else if (member == QLatin1String("remove") || member == QLatin1String("signOut")) {
                if (member == QLatin1String("signOut"))
                    reply << true;
            }
        } else if (iface == SsoPrefix + QLatin1String(".AuthSession")) {
            if (member == QLatin1String("process")) {
                QVariantMap data = toMap(message.arguments().value(0));
                data.insert(QStringLiteral("Token"), QStringLiteral("token-from-fake-signond"));
                reply << QVariant::fromValue(data);
            } else if (member == QLatin1String("queryAvailableMechanisms")) {
                reply << QStringList { QStringLiteral("password") };
            }
        } else {
            return false;
        }
        connection.send(message.createReply(reply));
        return true;
    }

    QList<Call> callsTo(const QString &member) const
    {
        QList<Call> found;
        for (const Call &c : calls) {
            if (c.member == member)
                found.append(c);
        }
        return found;
    }

    QList<Call> calls;
    QHash<quint32, QVariantMap> identities;
    quint32 nextId = 7;
};

} // namespace

class tst_SailfishAccounts : public QObject
{
    Q_OBJECT

public:
    explicit tst_SailfishAccounts(QString runtimeDir);

private slots:
    void initTestCase();
    void managerCreatesAccount();
    void accountReadsAndWrites();
    void signInCredentials();
    void modelAndSyncManager();
    void viewsOnSilica();

private:
    QObject *create(const QByteArray &qml);
    std::unique_ptr<QQmlEngine> m_engine;
    std::unique_ptr<QDBusServer> m_server;
    FakeSignond m_signond;
    QString m_runtimeDir;
    int m_accountId = 0;
};

tst_SailfishAccounts::tst_SailfishAccounts(QString runtimeDir)
    : m_runtimeDir(std::move(runtimeDir))
{
}

QObject *tst_SailfishAccounts::create(const QByteArray &qml)
{
    QQmlComponent c(m_engine.get());
    c.setData("import QtQuick 2.0\nimport Sailfish.Accounts 1.0\n" + qml, QUrl(QStringLiteral("inline.qml")));
    QObject *o = c.create();
    if (!o)
        qWarning().noquote() << c.errorString();
    return o;
}

void tst_SailfishAccounts::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    // signond's peer-to-peer socket, where libsignon looks for it.
    QVERIFY(QDir().mkpath(m_runtimeDir + QStringLiteral("/signond")));
    m_server = std::make_unique<QDBusServer>(QStringLiteral("unix:path=%1/signond/socket").arg(m_runtimeDir));
    QVERIFY2(m_server->isConnected(), qPrintable(m_server->lastError().message()));
    connect(m_server.get(), &QDBusServer::newConnection, this, [this](const QDBusConnection &connection) {
        QDBusConnection peer(connection);
        peer.registerVirtualObject(DaemonPath, &m_signond, QDBusConnection::SubPath);
    });
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_SailfishAccounts::managerCreatesAccount()
{
    std::unique_ptr<QObject> manager(create("AccountManager {}"));
    QVERIFY(manager);
    QTRY_VERIFY(manager->property("providerNames").toStringList().contains(QStringLiteral("test-provider")));
    QVERIFY(manager->property("serviceNames").toStringList().contains(QStringLiteral("test-service2")));
    QVERIFY(manager->property("serviceTypeNames").toStringList().contains(QStringLiteral("test-service-type2")));

    QSignalSpy created(manager.get(), SIGNAL(accountCreated(int,QString)));
    bool ok = false;
    QVERIFY(QMetaObject::invokeMethod(manager.get(), "createAccount", Q_RETURN_ARG(bool, ok),
                                      Q_ARG(QString, QStringLiteral("test-provider"))));
    QVERIFY(ok);
    QTRY_COMPARE_WITH_TIMEOUT(created.size(), 1, 10000);
    m_accountId = created.first().first().toInt();
    QVERIFY(m_accountId > 0);
    QTRY_VERIFY(manager->property("accountIdentifiers").value<QList<int>>().contains(m_accountId));

    Accounts::Manager accounts;
    QVERIFY(accounts.accountList().contains(Accounts::AccountId(m_accountId)));
}

void tst_SailfishAccounts::accountReadsAndWrites()
{
    QVERIFY(m_accountId > 0);
    std::unique_ptr<QObject> account(create(QByteArray("Account { identifier: ") + QByteArray::number(m_accountId) + " }"));
    QVERIFY(account);
    QTRY_COMPARE(account->property("providerName").toString(), QStringLiteral("test-provider"));
    QVERIFY(account->property("supportedServiceNames").toStringList().contains(QStringLiteral("test-service2")));
    account->setProperty("displayName", QStringLiteral("Keel account"));
    account->setProperty("enabled", true);
    QVERIFY(QMetaObject::invokeMethod(account.get(), "setConfigurationValue", Q_ARG(QString, QString()),
                                      Q_ARG(QString, QStringLiteral("keel/answer")), Q_ARG(QVariant, 42)));
    QVERIFY(QMetaObject::invokeMethod(account.get(), "setConfigurationValue", Q_ARG(QString, QStringLiteral("test-service2")),
                                      Q_ARG(QString, QStringLiteral("keel/server")), Q_ARG(QVariant, QStringLiteral("example.org"))));
    QVERIFY(QMetaObject::invokeMethod(account.get(), "enableWithService", Q_ARG(QString, QStringLiteral("test-service2"))));
    QVERIFY(QMetaObject::invokeMethod(account.get(), "sync"));
    QTRY_COMPARE_WITH_TIMEOUT(account->property("status").toInt(), 2 /* Synced */, 10000);

    Accounts::Manager accounts;
    std::unique_ptr<Accounts::Account> a(accounts.account(static_cast<Accounts::AccountId>(m_accountId)));
    QVERIFY(a);
    QCOMPARE(a->displayName(), QStringLiteral("Keel account"));
    QVERIFY(a->enabled());
    QCOMPARE(a->value(QStringLiteral("keel/answer")).toInt(), 42);
    a->selectService(accounts.service(QStringLiteral("test-service2")));
    QVERIFY(a->enabled());
    QCOMPARE(a->value(QStringLiteral("keel/server")).toString(), QStringLiteral("example.org"));

    // Read back by a fresh Account.
    std::unique_ptr<QObject> again(create(QByteArray("Account { identifier: ") + QByteArray::number(m_accountId) + " }"));
    QVERIFY(again);
    QTRY_COMPARE(again->property("status").toInt(), 0 /* Initialized */);
    QCOMPARE(again->property("displayName").toString(), QStringLiteral("Keel account"));
    QVariant server;
    QVERIFY(QMetaObject::invokeMethod(again.get(), "configurationValue", Q_RETURN_ARG(QVariant, server),
                                      Q_ARG(QString, QStringLiteral("test-service2")),
                                      Q_ARG(QString, QStringLiteral("keel/server"))));
    QCOMPARE(server.toString(), QStringLiteral("example.org"));
    bool enabledWithService = false;
    QVERIFY(QMetaObject::invokeMethod(again.get(), "isEnabledWithService", Q_RETURN_ARG(bool, enabledWithService),
                                      Q_ARG(QString, QStringLiteral("test-service2"))));
    QVERIFY(enabledWithService);
}

void tst_SailfishAccounts::signInCredentials()
{
    QVERIFY(m_accountId > 0);
    // As an app's QML does it.
    std::unique_ptr<QObject> account(create(QByteArray("Account {\n    identifier: ") + QByteArray::number(m_accountId) + R"QML(
    property var created
    property var response
    property string failure
    property string method
    onSignInCredentialsCreated: function(data) { created = data }
    onSignInResponse: function(data) { response = data }
    onSignInError: function(message, errorType) { failure = message }
    function createCredentials() {
        var parameters = signInParameters("test-service2", "ada", "secret")
        method = parameters.method
        createSignInCredentials("keeltest", "", parameters)
    }
    function login() {
        signIn("keeltest", "", signInParameters("test-service2", "ada", "secret"))
    }
})QML"));
    QVERIFY(account);
    QTRY_COMPARE(account->property("status").toInt(), 0 /* Initialized */);

    QVERIFY(QMetaObject::invokeMethod(account.get(), "createCredentials"));
    QCOMPARE(account->property("method").toString(), QStringLiteral("password"));
    QTRY_VERIFY_WITH_TIMEOUT(account->property("created").isValid() || !account->property("failure").toString().isEmpty(),
                             10000);
    QVERIFY2(account->property("failure").toString().isEmpty(), qPrintable(account->property("failure").toString()));

    // signond stored the identity (without the secret here) and ran the session.
    const QList<Call> stores = m_signond.callsTo(QStringLiteral("store"));
    QVERIFY(!stores.isEmpty());
    QCOMPARE(toMap(stores.first().args.value(0)).value(QStringLiteral("UserName")).toString(), QStringLiteral("ada"));
    QVERIFY(!m_signond.callsTo(QStringLiteral("process")).isEmpty());
    QCOMPARE(account->property("created").toMap().value(QStringLiteral("Token")).toString(),
             QStringLiteral("token-from-fake-signond"));
    bool has = false;
    QVERIFY(QMetaObject::invokeMethod(account.get(), "hasSignInCredentials", Q_RETURN_ARG(bool, has),
                                      Q_ARG(QString, QStringLiteral("keeltest")), Q_ARG(QString, QString())));
    QVERIFY(has);

    // Signing in runs the session again.
    QVERIFY(QMetaObject::invokeMethod(account.get(), "login"));
    QTRY_VERIFY_WITH_TIMEOUT(account->property("response").isValid() || !account->property("failure").toString().isEmpty(),
                             10000);
    QVERIFY2(account->property("failure").toString().isEmpty(), qPrintable(account->property("failure").toString()));
    QCOMPARE(account->property("response").toMap().value(QStringLiteral("Token")).toString(),
             QStringLiteral("token-from-fake-signond"));
}

void tst_SailfishAccounts::modelAndSyncManager()
{
    std::unique_ptr<QObject> model(create("AccountModel {}"));
    QVERIFY(model);
    auto *items = qobject_cast<QAbstractItemModel *>(model.get());
    QVERIFY(items);
    QTRY_VERIFY(items->rowCount() >= 1);
    std::unique_ptr<QObject> sync(create("AccountSyncManager {}"));
    QVERIFY(sync);
    QStringList ids;
    QVERIFY(QMetaObject::invokeMethod(sync.get(), "profileIds", Q_RETURN_ARG(QStringList, ids), Q_ARG(int, m_accountId),
                                      Q_ARG(QString, QString())));
    QVERIFY(ids.isEmpty());
}

void tst_SailfishAccounts::viewsOnSilica()
{
    // The module's Silica views, as the Settings app and account-aware apps
    // use them: a list of the accounts and the provider picker.
    QQmlComponent c(m_engine.get());
    c.setData(R"QML(import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Accounts 1.0
Item {
    width: 540; height: 960
    property alias list: list
    property alias picker: picker
    AccountsListView { id: list; anchors.fill: parent; entriesInteractive: true }
    AccountProviderPicker { id: picker; width: parent.width }
})QML",
              QUrl(QStringLiteral("views.qml")));
    std::unique_ptr<QObject> o(c.create());
    QVERIFY2(o, qPrintable(c.errorString()));
    auto *list = o->property("list").value<QObject *>();
    QTRY_VERIFY(list->property("count").toInt() >= 1);
}

int main(int argc, char **argv)
{
    // A private accounts database and runtime directory.
    QTemporaryDir dir;
    if (!dir.isValid())
        return 1;
    QFile::setPermissions(dir.path(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    qputenv("ACCOUNTS", QFile::encodeName(dir.path()));
    qputenv("AG_PROVIDERS", KEEL_ACCOUNTS_DATA);
    qputenv("AG_SERVICES", KEEL_ACCOUNTS_DATA);
    qputenv("AG_SERVICE_TYPES", KEEL_ACCOUNTS_DATA);
    qputenv("AG_APPLICATIONS", KEEL_ACCOUNTS_DATA);
    qputenv("XDG_RUNTIME_DIR", QFile::encodeName(dir.path()));
    qputenv("XDG_CONFIG_HOME", QFile::encodeName(dir.path() + QStringLiteral("/config")));
    qputenv("XDG_CACHE_HOME", QFile::encodeName(dir.path() + QStringLiteral("/cache")));
    qputenv("HOME", QFile::encodeName(dir.path()));
    QGuiApplication app(argc, argv);
    tst_SailfishAccounts test(dir.path());
    return QTest::qExec(&test, argc, argv);
}

#include "tst_sailfishaccounts.moc"
