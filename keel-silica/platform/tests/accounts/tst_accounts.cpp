// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// libaccounts-qt6 and org.nemomobile.accounts on a private accounts database
// (ACCOUNTS, AG_PROVIDERS, AG_SERVICES, AG_SERVICE_TYPES point at the test
// data; run under dbus-run-session, where libaccounts-glib sends its change
// notifications): an account created from QML is in the database for the
// C++ API, and an account another client (the Settings app, here a second
// Accounts::Manager) adds shows up in the QML model.

#include <Accounts/Account>
#include <Accounts/Manager>
#include <Accounts/Provider>

#include <QGuiApplication>
#include <QAbstractItemModel>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QTest>
#include <memory>

class tst_Accounts : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void createFromQml();
    void modelSeesOtherClients();
    void providers();

private:
    QObject *create(const QByteArray &qml);
    std::unique_ptr<QQmlEngine> m_engine;
    int m_qmlAccount = 0;
};

QObject *tst_Accounts::create(const QByteArray &qml)
{
    QQmlComponent c(m_engine.get());
    c.setData("import QtQuick 2.0\nimport org.nemomobile.accounts 1.0\n" + qml, QUrl(QStringLiteral("inline.qml")));
    QObject *o = c.create();
    if (!o)
        qWarning().noquote() << c.errorString();
    return o;
}

void tst_Accounts::initTestCase()
{
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS"))
        QSKIP("needs a private session bus (dbus-run-session)");
    m_engine = std::make_unique<QQmlEngine>();
    m_engine->addImportPath(QStringLiteral(KEEL_QML_DIR));
}

void tst_Accounts::createFromQml()
{
    std::unique_ptr<QObject> account(create(R"QML(
Account {
    providerName: "test-provider"
    displayName: "Keel test account"
    Component.onCompleted: sync()
})QML"));
    QVERIFY(account);
    QTRY_COMPARE_WITH_TIMEOUT(account->property("status").toInt(), 2 /* Synced */, 10000);
    m_qmlAccount = account->property("identifier").toInt();
    QVERIFY(m_qmlAccount > 0);

    // In the database, for the Qt 6 C++ API.
    Accounts::Manager manager;
    QVERIFY(manager.accountList().contains(Accounts::AccountId(m_qmlAccount)));
    std::unique_ptr<Accounts::Account> a(manager.account(static_cast<Accounts::AccountId>(m_qmlAccount)));
    QVERIFY(a);
    QCOMPARE(a->displayName(), QStringLiteral("Keel test account"));
    QCOMPARE(a->providerName(), QStringLiteral("test-provider"));
}

void tst_Accounts::modelSeesOtherClients()
{
    std::unique_ptr<QObject> model(create("AccountModel { }"));
    QVERIFY(model);
    auto *m = qobject_cast<QAbstractItemModel *>(model.get());
    QVERIFY(m);
    QTRY_COMPARE(m->rowCount(), 1);

    // Another client adds an account.
    Accounts::Manager other;
    Accounts::Account *added = other.createAccount(QStringLiteral("test-provider"));
    QVERIFY(added);
    added->setDisplayName(QStringLiteral("Added elsewhere"));
    added->syncAndBlock();
    QVERIFY(added->id() > 0);
    // libaccounts-glib's change notification over D-Bus updates the model.
    QTRY_COMPARE_WITH_TIMEOUT(m->rowCount(), 2, 10000);
    const QHash<int, QByteArray> roles = m->roleNames();
    const int nameRole = roles.key("accountDisplayName");
    QStringList names;
    for (int row = 0; row < m->rowCount(); ++row)
        names << m->data(m->index(row, 0), nameRole).toString();
    names.sort();
    QCOMPARE(names, (QStringList { QStringLiteral("Added elsewhere"), QStringLiteral("Keel test account") }));
    delete added;
}

void tst_Accounts::providers()
{
    std::unique_ptr<QObject> manager(create(R"QML(AccountManager {
    function providerDisplayName(name) { return provider(name).displayName }
})QML"));
    QVERIFY(manager);
    QTRY_VERIFY(manager->property("providerNames").toStringList().contains(QStringLiteral("test-provider")));
    QVERIFY(manager->property("serviceNames").toStringList().contains(QStringLiteral("test-service2")));
    QVariant displayName;
    QVERIFY(QMetaObject::invokeMethod(manager.get(), "providerDisplayName", Q_RETURN_ARG(QVariant, displayName),
                                      Q_ARG(QVariant, QStringLiteral("test-provider"))));
    QCOMPARE(displayName.toString(), QStringLiteral("Provider(test)"));
}

int main(int argc, char **argv)
{
    QTemporaryDir db;
    if (!db.isValid())
        return 1;
    qputenv("ACCOUNTS", QFile::encodeName(db.path()));
    qputenv("AG_PROVIDERS", KEEL_ACCOUNTS_DATA);
    qputenv("AG_SERVICES", KEEL_ACCOUNTS_DATA);
    qputenv("AG_SERVICE_TYPES", KEEL_ACCOUNTS_DATA);
    qputenv("AG_APPLICATIONS", KEEL_ACCOUNTS_DATA);
    QGuiApplication app(argc, argv);
    tst_Accounts test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_accounts.moc"
