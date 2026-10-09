// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2024 - 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause
// Modified by Shipwright for Qt 6: QTranslator::load() is [[nodiscard]]; a missing
// catalogue still leaves the text untranslated, as upstream intends ((void) casts).

#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include <QtQml>

#include <QTranslator>
#include <QGuiApplication>
#include <QLocale>

#include "globalaccountmanager_p.h"

#include "account.h"
#include "accountmanager.h"
#include "accountmodel.h"
#include "provider.h"
#include "providermodel.h"
#include "service.h"
#include "servicetype.h"
#include "servicemodel.h"
#include "signinparameters.h"
#include "accountsyncmanager.h"
#include "accountsyncoptions.h"
#include "accountauthenticator.h"
#include "accountvalue.h"

// using custom translator so it gets properly removed from qApp when engine is deleted
class AppTranslator: public QTranslator
{
    Q_OBJECT
public:
    AppTranslator(QObject *parent)
        : QTranslator(parent)
    {
        qApp->installTranslator(this);
    }

    virtual ~AppTranslator()
    {
        qApp->removeTranslator(this);
    }
};


class SailfishAccountsPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.sailfish.components.accounts")

public:

    void initializeEngine(QQmlEngine *engine, const char *uri)
    {
        Q_UNUSED(uri)
        Q_ASSERT(QLatin1String(uri) == QLatin1String("Sailfish.Accounts"));

        AppTranslator *engineeringEnglish = new AppTranslator(engine);
        AppTranslator *translator = new AppTranslator(engine);
        (void)engineeringEnglish->load("sailfish_components_accounts_qt5_eng_en", "/usr/share/translations");
        (void)translator->load(QLocale(), "sailfish_components_accounts_qt5", "-", "/usr/share/translations");
    }

    virtual void registerTypes(const char *uri)
    {
        Q_UNUSED(uri)
        Q_ASSERT(QLatin1String(uri) == QLatin1String("Sailfish.Accounts"));

        qmlRegisterType<Account>("Sailfish.Accounts", 1, 0, "Account");
        qmlRegisterType<AccountManager>("Sailfish.Accounts", 1, 0, "AccountManager");
        qmlRegisterType<AccountModel>("Sailfish.Accounts", 1, 0, "AccountModel");
        qmlRegisterType<Provider>("Sailfish.Accounts", 1, 0, "Provider");
        qmlRegisterType<ProviderModel>("Sailfish.Accounts", 1, 0, "ProviderModel");
        qmlRegisterType<Service>("Sailfish.Accounts", 1, 0, "Service");
        qmlRegisterType<ServiceType>("Sailfish.Accounts", 1, 0, "ServiceType");
        qmlRegisterType<ServiceModel>("Sailfish.Accounts", 1, 0, "ServiceModel");
        qmlRegisterType<SignInParameters>("Sailfish.Accounts", 1, 0, "SignInParameters");
        qmlRegisterType<AccountSyncManager>("Sailfish.Accounts", 1, 0, "AccountSyncManager");
        qmlRegisterType<AccountSyncOptions>("Sailfish.Accounts", 1, 0, "AccountSyncOptions");
        qmlRegisterType<AccountSyncSchedule>("Sailfish.Accounts", 1, 0, "AccountSyncSchedule");
        qmlRegisterType<AccountAuthenticator>("Sailfish.Accounts", 1, 0, "AccountAuthenticator");
        // Modified by Shipwright for Qt 6: a gadget (value) type needs a
        // lower-case QML name in Qt 6; QML only meets it as a property value.
        qmlRegisterUncreatableType<AccountAuthenticatorCredentials>("Sailfish.Accounts", 1, 0,
                                                                    "accountAuthenticatorCredentials", "");
        qmlRegisterType<AccountValue>("Sailfish.Accounts", 1, 0, "AccountValue");
    }
};

#include "plugin.moc"
