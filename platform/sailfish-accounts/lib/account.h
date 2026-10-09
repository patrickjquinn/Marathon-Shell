/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__ACCOUNT_H
#define SAILFISH_ACCOUNTS__ACCOUNT_H

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtCore/QStringList>
#include <QtCore/QString>

#include <QtGlobal>
#include <QQmlParserStatus>

// libaccounts-qt
#include <Accounts/Account>
#include <Accounts/Error>

class SignInParameters;
class AccountPrivate;

/*
 * NOTE: if you construct one of these in C++ directly,
 * you MUST call classBegin() and componentCompleted()
 * directly after construction.
 */

class Q_DECL_EXPORT Account : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int identifier READ identifier WRITE setIdentifier NOTIFY identifierChanged)
    Q_PROPERTY(QString providerName READ providerName NOTIFY providerNameChanged)
    Q_PROPERTY(QString displayName READ displayName WRITE setDisplayName NOTIFY displayNameChanged)
    Q_PROPERTY(QString defaultCredentialsUserName READ defaultCredentialsUserName NOTIFY defaultCredentialsUserNameChanged)

    Q_PROPERTY(bool provisioned READ provisioned NOTIFY provisionedChanged)
    Q_PROPERTY(bool readonly READ readonly NOTIFY readonlyChanged)
    Q_PROPERTY(bool limited READ limited NOTIFY limitedChanged)

    Q_PROPERTY(QStringList supportedServiceNames READ supportedServiceNames NOTIFY supportedServiceNamesChanged)

    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(ErrorType error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

    Q_ENUMS(Status)
    Q_ENUMS(ErrorType)

public:
    enum Status {
        Initialized = 0,
        Initializing,
        Synced,
        SyncInProgress,
        Modified,
        SigningIn,
        Error,
        Invalid
    };

    enum ErrorType {
        NoError                 = Accounts::Error::NoError,
        UnknownError            = Accounts::Error::Unknown,
        DatabaseError           = Accounts::Error::Database,
        DeletedError            = Accounts::Error::Deleted,
        DatabaseLockedError     = Accounts::Error::DatabaseLocked,
        AccountNotFoundError    = Accounts::Error::AccountNotFound,
        InitializationFailedError,
        SignInUnknownError,
        SignInInvalidStatusError,
        SignInInvalidCredentialsError,
        SignInCredentialsExpiredError,
        SignInNetworkError,
        SignInMissingDataError,
        SignInPermissionDeniedError,
        SignInOperationCanceledError
    };

public:
    Account(QObject *parent = 0);
    ~Account();

    // QQmlParserStatus
    void classBegin() override;
    void componentComplete() override;

    // database sync
    Q_INVOKABLE void sync();
    Q_INVOKABLE void blockingSync();
    Q_INVOKABLE void remove();

    // invokable api.
    Q_INVOKABLE QVariantMap configurationValues(const QString &serviceName) const;
    Q_INVOKABLE QVariant configurationValue(const QString &serviceName, const QString &key) const;
    Q_INVOKABLE void setConfigurationValue(const QString &serviceName, const QString &key, const QVariant &value);
    Q_INVOKABLE void removeConfigurationValue(const QString &serviceName, const QString &key);
    Q_INVOKABLE bool isEnabledWithService(const QString &serviceName) const;
    Q_INVOKABLE void enableWithService(const QString &serviceName);
    Q_INVOKABLE void disableWithService(const QString &serviceName);

    // sign-in related invokable api.
    Q_INVOKABLE SignInParameters *signInParameters(const QString &serviceName,
                                                   const QString &username = QString(),
                                                   const QString &password = QString());
    Q_INVOKABLE bool hasSignInCredentials(const QString &applicationName,
                                          const QString &credentialsName) const;
    Q_INVOKABLE void createSignInCredentials(const QString &applicationName,
                                             const QString &credentialsName,
                                             SignInParameters *parameters,
                                             const QString &symmetricKey = QString());
    Q_INVOKABLE void updateSignInCredentials(const QString &applicationName,
                                             const QString &credentialsName,
                                             SignInParameters *parameters,
                                             const QString &symmetricKey = QString());
    Q_INVOKABLE void removeSignInCredentials(const QString &applicationName,
                                             const QString &credentialsName);
    Q_INVOKABLE void signIn(const QString &applicationName,
                            const QString &credentialsName,
                            SignInParameters *parameters,
                            const QString &symmetricKey = QString());
    Q_INVOKABLE void signOut(const QString &applicationName,
                             const QString &credentialsName);

    // property accessors.
    bool enabled() const;
    void setEnabled(bool e);
    int identifier() const;
    void setIdentifier(int id);
    QString displayName() const;
    void setDisplayName(const QString &dn);
    QString defaultCredentialsUserName() const;
    bool provisioned() const;
    bool readonly() const;
    bool limited() const;
    QString providerName() const;
    QStringList supportedServiceNames() const;

    Status status() const;
    ErrorType error() const;
    QString errorMessage() const;

public Q_SLOTS:
    void cancelSignInOperation();

Q_SIGNALS:
    void enabledChanged();
    void identifierChanged();
    void displayNameChanged();
    void providerNameChanged();
    void supportedServiceNamesChanged();
    void statusChanged();
    void errorChanged();
    void errorMessageChanged();
    void defaultCredentialsUserNameChanged();

    void provisionedChanged();
    void readonlyChanged();
    void limitedChanged();

    void enabledWithServiceChanged(const QString &serviceName);

    void signInCredentialsCreated(const QVariantMap &data);
    void signInCredentialsUpdated(const QVariantMap &data);
    void signInResponse(const QVariantMap &data);
    void signInError(const QString &message, int errorType);

protected:
    Account(QObject *parent, AccountPrivate *d);

    // the following should be protected, but are public to allow AccountFactory
    // (from jolla-settings-accounts) to use them during account creation.
public:
    Account(bool queryInfoOnCreation, Accounts::Account *account, QObject *parent,
            const QVariantMap &serviceConfigValues = QVariantMap());
    Accounts::Account *account();

protected:
    AccountPrivate *d;
    friend class AccountPrivate;
};

#endif
