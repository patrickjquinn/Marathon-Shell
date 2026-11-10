// SPDX-FileCopyrightText: 2014-2017 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only

// This file is part of lipstick, a QML desktop library
//
// Copyright (c) 2014-2017 Jolla Ltd.
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

#ifndef LAUNCHERFOLDERMODEL_H
#define LAUNCHERFOLDERMODEL_H

#include <QObject>
#include <QStringList>
#include <QPointer>
#include <QSharedPointer>
#include <QTimer>

#include "qobjectlistmodel.h"
#include "launchermodel.h"
#include "launcherfolderitem.h"
#include "lipstickglobal.h"

class QXmlStreamWriter;
class LauncherModel;
class LauncherItem;
class DeferredLauncherModel;

class LIPSTICK_EXPORT LauncherFolderModel : public LauncherFolderItem
{
    Q_OBJECT
    Q_PROPERTY(QString scope READ scope WRITE setScope NOTIFY scopeChanged)
    Q_PROPERTY(QStringList directories READ directories WRITE setDirectories NOTIFY directoriesChanged)
    Q_PROPERTY(QStringList iconDirectories READ iconDirectories WRITE setIconDirectories NOTIFY iconDirectoriesChanged)
    Q_PROPERTY(QStringList categories READ categories WRITE setCategories NOTIFY categoriesChanged)
    Q_PROPERTY(QStringList blacklistedApplications READ blacklistedApplications WRITE setBlacklistedApplications NOTIFY blacklistedApplicationsChanged)
    Q_PROPERTY(QString replacementIdentityKey READ replacementIdentityKey WRITE setReplacementIdentityKey NOTIFY replacementIdentityKeyChanged)
    Q_PROPERTY(LauncherModel *allItems READ allItems CONSTANT)

public:
    LauncherFolderModel(QObject *parent = 0);

    LauncherModel *allItems() const;

    QString scope() const;
    void setScope(const QString &scope);

    QStringList directories() const;
    void setDirectories(QStringList);

    QStringList iconDirectories() const;
    void setIconDirectories(QStringList);

    QStringList categories() const;
    void setCategories(const QStringList &categories);

    QStringList blacklistedApplications() const;
    void setBlacklistedApplications(const QStringList &applications);

    QString replacementIdentityKey() const;
    void setReplacementIdentityKey(const QString &key);

    Q_INVOKABLE bool moveToFolder(QObject *item, LauncherFolderItem *folder, int index = -1);

    void import();

    static QString configFile();
    static void setConfigDir(const QString &dirPath);
    static QString configDir();

public slots:
    void load();
    void save();

signals:
    void scopeChanged();
    void directoriesChanged();
    void iconDirectoriesChanged();
    void categoriesChanged();
    void blacklistedApplicationsChanged();
    void replacementIdentityKeyChanged();
    void notifyLaunching(LauncherItem *item);
    void canceledNotifyLaunching(LauncherItem *item);
    void applicationRemoved(LauncherItem *item);

protected:
    enum InitializationMode {
        DeferInitialization
    };

    explicit LauncherFolderModel(InitializationMode, QObject *parent = 0);

    void initialize();

private slots:
    void scheduleSave();
    void onAppRemoved(QObject *item);
    void onAppAdded(QObject *item);
    void onAppReplaced(LauncherItem *item, const QString &oldFilePath);

    void updateblacklistedApplications();

private:
    void saveFolder(QXmlStreamWriter &xml, LauncherFolderItem *folder, const QString &directoryId);
    void blacklistApps(LauncherFolderItem *folder, const QString &directoryId);
    void removeAppsFromBlacklist();
    void updateAppsInBlacklistedFolders();
    LauncherFolderItem *findContainerFolder(const QString &directoryId) const;

    DeferredLauncherModel *m_launcherModel;
    QTimer m_saveTimer;
    bool m_loading;
    bool m_initialized;
    QMap<QString, QString> m_blacklistedApplicationPositions;

    static QString s_configDir;
};

#endif
