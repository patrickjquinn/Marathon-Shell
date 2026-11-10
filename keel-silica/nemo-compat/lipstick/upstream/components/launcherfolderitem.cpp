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

#include "launcheritem.h"
#include "launcherfolderitem.h"
#include "launcherfoldermodel.h"
#include "launchermodel.h"

#include <QFile>
#include <QTemporaryFile>
#include <QDebug>

#include <glib.h>

static const QString DEFAULT_ICON_ID("icon-launcher-folder-01");

static QString absoluteConfigPath(const QString &fileName)
{
    return LauncherFolderModel::configDir() + fileName;
}

// This is modeled after the freedesktop.org menu files http://standards.freedesktop.org/menu-spec/latest/
// but handles only the basic elements, i.e. no merging, filtering, layout, etc. is supported.

LauncherFolderItem::LauncherFolderItem(QObject *parent)
    : QObjectListModel(parent), m_iconId(DEFAULT_ICON_ID)
{
    connect(this, &LauncherFolderItem::itemRemoved,
            this, &LauncherFolderItem::handleRemoved);
    connect(this, &LauncherFolderItem::itemAdded,
            this, &LauncherFolderItem::handleAdded);
    connect(this, &LauncherFolderItem::rowsMoved,
            this, &LauncherFolderItem::saveNeeded);
}

LauncherModel::ItemType LauncherFolderItem::type() const
{
    return LauncherModel::Folder;
}

const QString &LauncherFolderItem::title() const
{
    return m_title;
}

void LauncherFolderItem::setTitle(const QString &title)
{
    if (title == m_title)
        return;

    m_title = title;
    emit titleChanged();
    emit saveNeeded();
}

const QString &LauncherFolderItem::iconId() const
{
    return m_iconId;
}

void LauncherFolderItem::setIconId(const QString &icon)
{
    if (icon == m_iconId)
        return;

    m_iconId = icon;
    saveDirectoryFile();
    emit iconIdChanged();
}

bool LauncherFolderItem::isUpdating() const
{
    LauncherFolderItem *me = const_cast<LauncherFolderItem*>(this);
    for (int i = 0; i < rowCount(); ++i) {
        const LauncherItem *launcherItem = qobject_cast<const LauncherItem*>(me->get(i));
        if (launcherItem && launcherItem->isUpdating())
            return true;
    }

    return false;
}

int LauncherFolderItem::updatingProgress() const
{
    int updatingCount = 0;
    int updatingTotal = 0;
    LauncherFolderItem *me = const_cast<LauncherFolderItem*>(this);
    for (int i = 0; i < rowCount(); ++i) {
        const LauncherItem *launcherItem = qobject_cast<const LauncherItem*>(me->get(i));
        if (launcherItem && launcherItem->isUpdating()) {
            int progress = launcherItem->updatingProgress();
            if (progress < 0 || progress > 100)
                return progress;
            ++updatingCount;
            updatingTotal += progress;
        }
    }

    return updatingCount ? updatingTotal / updatingCount : 0;
}

LauncherFolderItem *LauncherFolderItem::parentFolder() const
{
    return m_parentFolder;
}

void LauncherFolderItem::setParentFolder(LauncherFolderItem *parent)
{
    if (parent == m_parentFolder)
        return;

    m_parentFolder = parent;
    emit parentFolderChanged();
}

// Creates a folder and moves the item at that index into the folder
LauncherFolderItem *LauncherFolderItem::createFolder(int index, const QString &name)
{
    if (index < 0 || index > rowCount())
        return nullptr;

    LauncherFolderItem *folder = new LauncherFolderItem(this);
    folder->setTitle(name);
    folder->setParentFolder(this);
    QObject *item = get(index);
    insertItem(index, folder);
    if (item) {
        removeItem(item);
        folder->addItem(item);
    }

    emit saveNeeded();

    return folder;
}

void LauncherFolderItem::destroyFolder()
{
    if (itemCount() != 0)
        qWarning() << "Removing a folder that is not empty.";
    if (m_parentFolder)
        m_parentFolder->removeItem(this);
    if (!m_directoryFile.isEmpty()) {
        QFile file(m_directoryFile);
        file.remove();
    }

    emit saveNeeded();

    deleteLater();
}

LauncherFolderItem *LauncherFolderItem::findContainer(QObject *item)
{
    LauncherFolderItem *me = const_cast<LauncherFolderItem*>(this);
    for (int i = 0; i < rowCount(); ++i) {
        QObject *obj = me->get(i);
        if (obj == item) {
            return this;
        } else if (LauncherFolderItem *subFolder = qobject_cast<LauncherFolderItem*>(obj)) {
            LauncherFolderItem *folder = subFolder->findContainer(item);
            if (folder)
                return folder;
        }
    }

    return nullptr;
}

QString LauncherFolderItem::directoryFile() const
{
    return m_directoryFile;
}

void LauncherFolderItem::loadDirectoryFile(const QString &filename)
{
    m_directoryFile = filename;
    if (!m_directoryFile.startsWith('/')) {
        m_directoryFile = absoluteConfigPath(m_directoryFile);
    }

    GKeyFile *keyfile = g_key_file_new();
    GError *err = NULL;

    if (g_key_file_load_from_file(keyfile, m_directoryFile.toLatin1(), G_KEY_FILE_NONE, &err)) {
        m_iconId = QString::fromLatin1(g_key_file_get_string(keyfile, "Desktop Entry", "Icon", &err));
        emit iconIdChanged();
    }

    if (err != NULL) {
        qWarning() << "Failed to load .directory file" << err->message;
        g_error_free(err);
    }

    g_key_file_free(keyfile);
}

void LauncherFolderItem::saveDirectoryFile()
{
    QScopedPointer<QFile> dirFile;
    if (m_directoryFile.isEmpty()) {
        QTemporaryFile *tempFile = new QTemporaryFile(absoluteConfigPath("FolderXXXXXX.directory"));
        dirFile.reset(tempFile);
        // Modified by Shipwright for Qt 6: open() is [[nodiscard]]; say why the
        // folder will not be saved instead of failing silently.
        if (!tempFile->open())
            qWarning() << "Cannot create the folder file" << tempFile->fileTemplate();
        tempFile->setAutoRemove(false);
        m_directoryFile = tempFile->fileName();
        emit directoryFileChanged();
        emit saveNeeded();
    } else {
        dirFile.reset(new QFile(m_directoryFile));
        dirFile.data()->open(QIODevice::WriteOnly);
    }

    if (!dirFile.data()->isOpen()) {
        qWarning() << "Cannot open" << m_directoryFile;
        return;
    }

    GKeyFile *keyfile = g_key_file_new();
    GError *err = NULL;

    g_key_file_load_from_file(keyfile, m_directoryFile.toLatin1(), G_KEY_FILE_NONE, &err);
    g_key_file_set_string(keyfile, "Desktop Entry", "Icon", m_iconId.toLatin1());

    gchar *data = g_key_file_to_data(keyfile, NULL, &err);
    dirFile.data()->write(data);
    dirFile.data()->close();
    g_free(data);

    g_key_file_free(keyfile);
}

void LauncherFolderItem::clear()
{
    for (int i = 0; i < rowCount(); ++i) {
        QObject *item = get(i);
        LauncherItem *launcherItem = qobject_cast<LauncherItem*>(item);
        LauncherFolderItem *folder = qobject_cast<LauncherFolderItem*>(item);

        if (launcherItem) {
            disconnect(launcherItem, &LauncherItem::isTemporaryChanged,
                       this, &LauncherFolderItem::saveNeeded);
            disconnect(launcherItem, &LauncherItem::isUpdatingChanged,
                       this, &LauncherFolderItem::isUpdatingChanged);
            disconnect(launcherItem, &LauncherItem::updatingProgressChanged,
                       this, &LauncherFolderItem::updatingProgressChanged);
        } else if (folder) {
            disconnect(folder, &LauncherFolderItem::saveNeeded,
                       this, &LauncherFolderItem::saveNeeded);
            disconnect(folder, &LauncherFolderItem::isUpdatingChanged,
                       this, &LauncherFolderItem::isUpdatingChanged);
            disconnect(folder, &LauncherFolderItem::updatingProgressChanged,
                       this, &LauncherFolderItem::updatingProgressChanged);

            folder->clear();
            folder->deleteLater();
        }
    }

    reset();
}

void LauncherFolderItem::handleAdded(QObject *item)
{
    const LauncherItem *launcherItem = qobject_cast<const LauncherItem*>(item);
    const LauncherFolderItem *folder = qobject_cast<const LauncherFolderItem*>(item);

    if (launcherItem) {
        if (launcherItem->isUpdating()) {
            emit isUpdatingChanged();
            emit updatingProgressChanged();
        }
        connect(launcherItem, &LauncherItem::isTemporaryChanged,
                this, &LauncherFolderItem::saveNeeded);
        connect(launcherItem, &LauncherItem::isUpdatingChanged,
                this, &LauncherFolderItem::isUpdatingChanged);
        connect(launcherItem, &LauncherItem::updatingProgressChanged,
                this, &LauncherFolderItem::updatingProgressChanged);
    } else if (folder) {
        if (folder->isUpdating()) {
            emit isUpdatingChanged();
            emit updatingProgressChanged();
        }
        connect(folder, &LauncherFolderItem::saveNeeded,
                this, &LauncherFolderItem::saveNeeded);
        connect(folder, &LauncherFolderItem::isUpdatingChanged,
                this, &LauncherFolderItem::isUpdatingChanged);
        connect(folder, &LauncherFolderItem::updatingProgressChanged,
                this, &LauncherFolderItem::updatingProgressChanged);
    }

    emit saveNeeded();
}

void LauncherFolderItem::handleRemoved(QObject *item)
{
    const LauncherItem *launcherItem = qobject_cast<const LauncherItem*>(item);
    const LauncherFolderItem *folder = qobject_cast<const LauncherFolderItem*>(item);

    if (launcherItem) {
        if (launcherItem->isUpdating()) {
            emit isUpdatingChanged();
            emit updatingProgressChanged();
        }
        disconnect(launcherItem, &LauncherItem::isTemporaryChanged,
                   this, &LauncherFolderItem::saveNeeded);
        disconnect(launcherItem, &LauncherItem::isUpdatingChanged,
                   this, &LauncherFolderItem::isUpdatingChanged);
        disconnect(launcherItem, &LauncherItem::updatingProgressChanged,
                   this, &LauncherFolderItem::updatingProgressChanged);
    } else if (folder) {
        if (folder->isUpdating()) {
            emit isUpdatingChanged();
            emit updatingProgressChanged();
        }
        disconnect(folder, &LauncherFolderItem::saveNeeded,
                   this, &LauncherFolderItem::saveNeeded);
        disconnect(folder, &LauncherFolderItem::isUpdatingChanged,
                   this, &LauncherFolderItem::isUpdatingChanged);
        disconnect(folder, &LauncherFolderItem::updatingProgressChanged,
                   this, &LauncherFolderItem::updatingProgressChanged);
    }

    emit saveNeeded();
}
