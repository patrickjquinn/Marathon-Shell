// SPDX-FileCopyrightText: 2012 Timur Kristóf
// SPDX-License-Identifier: LGPL-2.1-only


// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#ifndef LAUNCHERMODEL_H
#define LAUNCHERMODEL_H

#include <QObject>
#include <QSettings>
#include <QFileSystemWatcher>
#include <QDBusServiceWatcher>
#include <QMap>

#include "qobjectlistmodel.h"
#include "lipstickglobal.h"
#include "launchermonitor.h"
#include "launcherdbus.h"

class LauncherItem;

class LIPSTICK_EXPORT LauncherModel : public QObjectListModel
{
    Q_OBJECT
    Q_DISABLE_COPY(LauncherModel)

    Q_PROPERTY(QStringList directories READ directories WRITE setDirectories NOTIFY directoriesChanged)
    Q_PROPERTY(QStringList iconDirectories READ iconDirectories WRITE setIconDirectories NOTIFY iconDirectoriesChanged)
    Q_PROPERTY(QStringList categories READ categories WRITE setCategories NOTIFY categoriesChanged)
    Q_PROPERTY(QStringList blacklistedApplications READ blacklistedApplications WRITE setBlacklistedApplications NOTIFY blacklistedApplicationsChanged)
    Q_PROPERTY(QString replacementIdentityKey READ replacementIdentityKey WRITE setReplacementIdentityKey NOTIFY replacementIdentityKeyChanged)
    Q_PROPERTY(QString scope READ scope WRITE setScope NOTIFY scopeChanged)

    Q_ENUMS(ItemType)

public:
    explicit LauncherModel(QObject *parent = 0);
    virtual ~LauncherModel();

    enum ItemType {
        Application,
        Folder
    };

    QStringList directories() const;
    void setDirectories(QStringList);

    QStringList iconDirectories() const;
    void setIconDirectories(QStringList);

    QStringList categories() const;
    void setCategories(const QStringList &categories);

    QStringList blacklistedApplications() const;
    void setBlacklistedApplications(const QStringList &blacklistedApplications);
    bool isBlacklisted(LauncherItem *item) const;

    QString replacementIdentityKey() const;
    void setReplacementIdentityKey(const QString &key);

    QString scope() const;
    void setScope(const QString &scope);

    void updatingStarted(const QString &packageName, const QString &label,
                         const QString &iconPath, QString desktopFile, const QString &serviceName);
    void updatingProgress(const QString &packageName, int progress, const QString &serviceName);
    void updatingFinished(const QString &packageName, const QString &serviceName);
    void notifyLaunching(const QString &desktopFile);
    void cancelNotifyLaunching(const QString &desktopFile);

    void requestLaunch(const QString &packageName);
    LauncherItem *itemInModel(const QString &path);
    int indexInModel(const QString &path);

    QList<LauncherItem *> itemsForMimeType(const QString &mimeType);

    LauncherItem *itemForService(const QString &name);

public slots:
    void savePositions();
    void removeTemporaryLaunchers();

signals:
    void directoriesChanged();
    void iconDirectoriesChanged();
    void categoriesChanged();
    void blacklistedApplicationsChanged();
    void replacementIdentityKeyChanged();
    void scopeChanged();
    void launcherReplaced(LauncherItem *item, const QString &oldFilePath);
    void notifyLaunching(LauncherItem *item);
    void canceledNotifyLaunching(LauncherItem *item);

protected:
    enum InitializationMode {
        DeferInitialization
    };

    explicit LauncherModel(InitializationMode, QObject *parent = 0);

    void initialize();

private slots:
    void monitoredFileChanged(const QString &changedPath);
    void onFilesUpdated(const QStringList &added, const QStringList &modified, const QStringList &removed);
    void onServiceUnregistered(const QString &serviceName);

private:
    void reorderItems();
    void loadPositions();
    bool displayCategory(LauncherItem *item) const;
    int findItem(const QString &path, LauncherItem **item);
    LauncherItem *packageInModel(const QString &packageName);
    QVariant launcherPos(const QString &path);
    LauncherItem *addItemIfValid(const QString &path);
    void updateItemsWithIcon(const QString &iconId, const QString &iconFilename);
    void updateWatchedDBusServices();
    void setTemporary(LauncherItem *item);
    void unsetTemporary(LauncherItem *item);
    LauncherItem *temporaryItemToReplace();

    LauncherItem *takeHiddenItem(const QString &path);

    QStringList m_directories;
    QStringList m_iconDirectories;
    QStringList m_categories;
    QStringList m_blacklistedApplications;
    QString m_replacementIdentityKey;
    QFileSystemWatcher m_fileSystemWatcher;
    QSettings m_launcherSettings;
    QSettings m_globalSettings;
    LauncherMonitor m_launcherMonitor;
    QString m_scope;
    QString m_launcherOrderPrefix;

    QDBusServiceWatcher m_dbusWatcher;
    QMap<QString, QString> m_packageNameToDBusService;
    QList<LauncherItem *> m_temporaryLaunchers;
    QList<LauncherItem *> m_hiddenLaunchers;
    bool m_initialized;

    friend class Ut_LauncherModel;
};

#endif // LAUNCHERMODEL_H
