// SPDX-FileCopyrightText: 2014 Sami Kananoja
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
// Copyright (c) 2014, Sami Kananoja <sami.kananoja@jolla.com>

#include <QFile>

#include "launcherwatchermodel.h"
#include "launcheritem.h"

LauncherWatcherModel::LauncherWatcherModel(QObject *parent)
    : QObjectListModel(parent)
{
    connect(&m_fileSystemWatcher, &QFileSystemWatcher::directoryChanged,
            this, &LauncherWatcherModel::directoryChanged);
}

LauncherWatcherModel::~LauncherWatcherModel()
{
}

QStringList LauncherWatcherModel::filePaths()
{
    return m_filePaths;
}

void LauncherWatcherModel::setFilePaths(const QStringList &paths)
{
    if (m_filePaths == paths)
        return;

    m_filePaths = paths;

    const QStringList watchedDirectories = m_fileSystemWatcher.directories();
    const QStringList directories = updateItems();

    foreach (const QString &directory, watchedDirectories) {
        if (!directories.contains(directory))
            m_fileSystemWatcher.removePath(directory);
    }

    if (directories.length() > 0) {
        m_fileSystemWatcher.addPaths(directories);
    }

    emit filePathsChanged();
}

void LauncherWatcherModel::directoryChanged(const QString &)
{
    updateItems();
}

QStringList LauncherWatcherModel::updateItems()
{
    QStringList directories;

    int index = 0;
    for (int i = 0; i < m_filePaths.count(); ++i) {
        const QString filePath = m_filePaths.at(i);

        if (filePath.isEmpty() || (i > 0 && m_filePaths.lastIndexOf(filePath, i - 1) != -1))
            continue;

        const QString directory = filePath.mid(0, filePath.lastIndexOf(QLatin1Char('/')));
        if (!directories.contains(directory))
            directories.append(directory);

        if (!QFile::exists(filePath))
            continue;

        int existingIndex;
        for (existingIndex = index; existingIndex < itemCount(); ++existingIndex) {
            if (static_cast<LauncherItem *>(get(existingIndex))->filePath() == filePath)
                break;
        }

        if (existingIndex >= itemCount()) {
            QScopedPointer<LauncherItem> item(new LauncherItem(filePath, this));
            if (item->isValid()) {
                insertItem(index, item.take());
            } else {
                continue;
            }
        } else if (existingIndex > index) {
            move(existingIndex, index);
        }
        ++index;
    }

    while (itemCount() > index) {
        QObject * const item = get(index);
        removeItem(index);
        delete item;
    }

    return directories;
}
