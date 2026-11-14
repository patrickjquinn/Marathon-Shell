// SPDX-FileCopyrightText: 2011 Robin Burchell
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
// Copyright (c) 2011, Robin Burchell
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#ifndef LAUNCHERITEM_H
#define LAUNCHERITEM_H

#include <QObject>
#include <QStringList>
#include <QSharedPointer>
#include <QBasicTimer>
#include <QRegularExpression>

// Define DEBUG_LAUNCHER if you'd like to see debug messages from the launcher
// #define DEBUG_LAUNCHER

#ifdef DEBUG_LAUNCHER
#include <QDebug>
#define LAUNCHER_DEBUG(things) qDebug() << Q_FUNC_INFO << things
#else
#define LAUNCHER_DEBUG(things)
#endif

#include "launchermodel.h"
#include "lipstickglobal.h"

class MDesktopEntry;
class MRemoteAction;
class QDBusPendingCallWatcher;

class LIPSTICK_EXPORT LauncherItem : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(LauncherItem)

    Q_PROPERTY(LauncherModel::ItemType type READ type CONSTANT)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY itemChanged)
    Q_PROPERTY(QString fileID READ fileID NOTIFY itemChanged)
    Q_PROPERTY(QString exec READ exec NOTIFY itemChanged)
    Q_PROPERTY(QString title READ title NOTIFY itemChanged)
    Q_PROPERTY(QString entryType READ entryType NOTIFY itemChanged)
    Q_PROPERTY(QString iconId READ iconId NOTIFY itemChanged)
    Q_PROPERTY(QStringList desktopCategories READ desktopCategories NOTIFY itemChanged)
    Q_PROPERTY(QStringList mimeType READ mimeType NOTIFY itemChanged)
    Q_PROPERTY(QString titleUnlocalized READ titleUnlocalized NOTIFY itemChanged)
    Q_PROPERTY(bool shouldDisplay READ shouldDisplay NOTIFY itemChanged)
    Q_PROPERTY(bool isSandboxed READ isSandboxed NOTIFY itemChanged)
    Q_PROPERTY(bool isValid READ isValid NOTIFY itemChanged)
    Q_PROPERTY(bool isLaunching READ isLaunching WRITE setIsLaunching NOTIFY isLaunchingChanged)
    Q_PROPERTY(bool isUpdating READ isUpdating WRITE setIsUpdating NOTIFY isUpdatingChanged)
    Q_PROPERTY(bool isTemporary READ isTemporary WRITE setIsTemporary NOTIFY isTemporaryChanged)
    Q_PROPERTY(bool dBusActivated READ dBusActivated NOTIFY itemChanged)
    Q_PROPERTY(QString dBusServiceName READ dBusServiceName NOTIFY itemChanged)
    Q_PROPERTY(QString packageName READ packageName WRITE setPackageName NOTIFY packageNameChanged)
    Q_PROPERTY(int updatingProgress READ updatingProgress WRITE setUpdatingProgress NOTIFY updatingProgressChanged)
    Q_PROPERTY(bool isBlacklisted READ isBlacklisted WRITE setIsBlacklisted NOTIFY isBlacklistedChanged)

public:
    explicit LauncherItem(const QString &filePath = QString(), QObject *parent = 0);
    LauncherItem(const QString &packageName, const QString &label,
                 const QString &iconPath, const QString &desktopFile, QObject *parent);
    virtual ~LauncherItem();

    LauncherModel::ItemType type() const;
    void setFilePath(const QString &filePath);
    QString filePath() const;
    QString fileID() const;
    QString filename() const;
    QString exec() const;
    QString title() const;
    QString entryType() const;
    QString iconId() const;
    QStringList desktopCategories() const;
    QStringList mimeType() const;
    QString titleUnlocalized() const;
    bool shouldDisplay() const;
    bool isSandboxed() const;
    bool isValid() const;
    bool isLaunching() const;
    bool isStillValid();
    bool dBusActivatable() const;
    bool dBusActivated() const;
    MRemoteAction remoteAction(const QStringList &arguments = QStringList()) const;

    QString getOriginalIconId() const;
    void setIconFilename(const QString &path);
    QString iconFilename() const;

    QString dBusServiceName() const;

    Q_INVOKABLE void launchApplication();
    Q_INVOKABLE void launchWithArguments(const QStringList &arguments);

    bool isUpdating() const { return m_isUpdating; }
    void setIsUpdating(bool isUpdating);

    bool isTemporary() const { return m_isTemporary; }
    void setIsTemporary(bool isTemporary);

    QString packageName() const { return m_packageName; }
    void setPackageName(QString packageName);

    int updatingProgress() const { return m_updatingProgress; }
    void setUpdatingProgress(int updatingProgress);

    bool isBlacklisted() const;
    void setIsBlacklisted(bool isBlacklisted);

    void setCustomTitle(QString customTitle);

    Q_INVOKABLE QString readValue(const QString &key) const;

    Q_INVOKABLE bool canOpenMimeType(const QString &mimeType);

    void invalidateCaches();

public slots:
    void setIsLaunching(bool isLaunching = false);

signals:
    void itemChanged();
    void isLaunchingChanged();
    void isUpdatingChanged();
    void isTemporaryChanged();
    void packageNameChanged();
    void updatingProgressChanged();
    void isBlacklistedChanged();

protected:
    void timerEvent(QTimerEvent *event);

private slots:
    void sandboxingInfoChanged(const QString &appname);

private:
    void initializeSandboxingInfo();
    void fetchSandboxingInfo();
    QString sandboxingName() const;

    QSharedPointer<MDesktopEntry> m_desktopEntry;
    QBasicTimer m_launchingTimeout;
    QVector<QRegularExpression> m_mimeTypes;
    bool m_isLaunching;
    bool m_isUpdating;
    bool m_isTemporary;
    QString m_packageName;
    int m_updatingProgress;
    QString m_customTitle;
    QString m_customIconFilename;
    QString m_serviceName;
    int m_serial;
    bool m_isBlacklisted;
    bool m_mimeTypesPopulated;
    bool m_sandboxingInfoFetched;
    bool m_sandboxed;
};

#endif // LAUNCHERITEM_H
