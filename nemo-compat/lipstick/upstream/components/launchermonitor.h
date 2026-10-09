// SPDX-FileCopyrightText: 2012 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only


// This file is part of lipstick, a QML desktop library
//
// Copyright (c) 2012 Jolla Ltd.
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

#ifndef LAUNCHERMONITOR_H
#define LAUNCHERMONITOR_H

#include <QObject>

#include <QMap>
#include <QString>
#include <QStringList>

#include <QFileSystemWatcher>
#include <QTimer>

class LauncherMonitor : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(LauncherMonitor)

public:
    LauncherMonitor();
    LauncherMonitor(const QString &desktopFilesPath, const QString &iconFilesPath);
    ~LauncherMonitor();

    void start();
    QStringList directories() const;
    void setDirectories(const QStringList &dirs);
    QStringList iconDirectories() const;
    void setIconDirectories(const QStringList &dirs);

    void reset(const QStringList &dirs);

signals:
    void filesUpdated(const QStringList &added, const QStringList &modified, const QStringList &removed);

private:
    void initialize();
    void setDirectories(const QStringList &newDirs, QStringList *targetDirs);

    QFileSystemWatcher m_watcher;
    QTimer m_holdbackTimer;

    QMap<QString, QStringList> m_knownFiles;

    QStringList m_addedFiles;
    QStringList m_modifiedFiles;
    QStringList m_removedFiles;

    QStringList m_desktopFilesPaths;
    QStringList m_iconFilesPaths;

private slots:
    void onDirectoryChanged(const QString &path);
    void onFileChanged(const QString &path);
    void onHoldbackTimerTimeout();
};

#endif // LAUNCHERMONITOR_H
