/*
 * SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef ACCOUNTSYNCPROFILEMANAGER_P_H
#define ACCOUNTSYNCPROFILEMANAGER_P_H

#include <QObject>
#include <QVariantMap>
#include <QDateTime>

#include <Accounts/AccountService>

namespace Buteo {
    class SyncProfile;
}

namespace Accounts {
    class Account;
    class Manager;
}

class AccountSyncProfileManagerPrivate;
class AccountSyncOptions;

class Q_DECL_EXPORT AccountSyncManager : public QObject
{
    Q_OBJECT
public:
    enum SyncStatus {
        UnknownSyncStatus,
        SyncStarted,
        SyncFinished,
        SyncAborted,
        SyncError
    };
    Q_ENUM(SyncStatus)

    enum BackupOperationType {
        InvalidOperation,
        Backup,
        BackupQuery,
        BackupRestore
    };
    Q_ENUM(BackupOperationType)

    AccountSyncManager(QObject *parent = 0);
    ~AccountSyncManager();

    Q_INVOKABLE void createProfile(const QString &templateProfileName, int accountId, const QString &serviceName);
    Q_INVOKABLE void updateProfile(const QString &profileId, const QVariantMap &properties, AccountSyncOptions *options);
    Q_INVOKABLE void syncProfile(const QString &profileId);
    Q_INVOKABLE void abortProfileSync(const QString &profileId);

    Q_INVOKABLE int createAllProfiles(int accountId);
    Q_INVOKABLE QStringList profileIds(int accountId, const QString &serviceName = QString()) const;
    Q_INVOKABLE AccountSyncOptions *accountSyncOptions(const QString &profileId);

    Q_INVOKABLE QDateTime nextSyncTime(const QString &profileId);
    Q_INVOKABLE QDateTime lastSyncTime(const QString &profileId);
    Q_INVOKABLE QDateTime lastSuccessfulSyncTime(const QString &profileId);

    Q_INVOKABLE bool templateProfilesAvailable(const QStringList &templateProfiles) const;
    Q_INVOKABLE QStringList defaultTemplateProfiles(int accountId, const QString &serviceName) const;

    QString createProfile(const QString &templateProfileName,
                          Accounts::Account *account,
                          const Accounts::Service &srv,
                          bool enableProfile,
                          const QVariantMap &properties = QVariantMap());
    bool checkProfile(const QString &templateProfileName,
                      Accounts::Account *account,
                      const Accounts::Service &srv);
    bool updateSyncProfile(const QString &profileId, const QVariantMap &properties, AccountSyncOptions *options);

    Q_INVOKABLE QVariantMap profileProperties(const QString &profileId) const;
    QString syncScheduleXml(const QString &profileId) const;

    Q_INVOKABLE QString findBackupOperationProfile(int accountId, BackupOperationType operation);
    static BackupOperationType backupOperationTypeForProfileId(const QString &profileId);

    QString accountDisplayName(int accountId);

    bool hasProfile(Accounts::Account *account, const Accounts::Service &srv) const;
    bool hasProfile(Accounts::Account *account, const Accounts::Service &srv, const QString &templateProfile) const;
    QStringList defaultTemplateProfiles(Accounts::Account *account, const Accounts::Service &srv) const;

    Buteo::SyncProfile *newProfileFromTemplate(const QString &templateProfileName,
                                               Accounts::Account *account,
                                               const Accounts::Service &srv,
                                               bool enableProfile,
                                               const QVariantMap &properties = QVariantMap());
    Buteo::SyncProfile *newProfileFromTemplate(const QString &templateProfileName,
                                               Accounts::Account *account,
                                               const Accounts::Service &srv,
                                               bool enableProfile,
                                               const QVariantMap &properties,
                                               const QString &scheduleXml);

signals:
    void profileCreated(const QString &profileId);
    void profileCreationError(int accountId, const QString &serviceName, const QString &errorString);
    void profileUpdated(const QString &profileId);
    void profileUpdateError(const QString &profileId, const QString &errorString);
    void profileSyncStatusChanged(const QString &profileId, int status, const QString &errorString);

    void allProfilesCreated(int accountId, const QStringList &profileIds);
    void allProfileCreationError(int accountId, const QString &errorString);

private:
    AccountSyncProfileManagerPrivate *d;
    Accounts::Manager *accountManager() const;
};

#endif
