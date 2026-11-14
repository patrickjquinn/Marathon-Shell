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

#ifndef LAUNCHERFOLDERITEM_H
#define LAUNCHERFOLDERITEM_H

#include <QObject>
#include <QPointer>
#include <QSharedPointer>
#include <QTimer>

#include "qobjectlistmodel.h"
#include "launchermodel.h"
#include "lipstickglobal.h"

class LauncherModel;
class MDesktopEntry;

class LIPSTICK_EXPORT LauncherFolderItem : public QObjectListModel
{
    Q_OBJECT
    Q_PROPERTY(LauncherModel::ItemType type READ type CONSTANT)
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY titleChanged)
    Q_PROPERTY(QString iconId READ iconId WRITE setIconId NOTIFY iconIdChanged)
    Q_PROPERTY(bool isUpdating READ isUpdating NOTIFY isUpdatingChanged)
    Q_PROPERTY(int updatingProgress READ updatingProgress NOTIFY updatingProgressChanged)
    Q_PROPERTY(LauncherFolderItem *parentFolder READ parentFolder NOTIFY parentFolderChanged)

public:
    LauncherFolderItem(QObject *parent = 0);

    LauncherModel::ItemType type() const;

    const QString &title() const;
    void setTitle(const QString &name);

    const QString &iconId() const;
    void setIconId(const QString &icon);

    bool isUpdating() const;
    int updatingProgress() const;

    LauncherFolderItem *parentFolder() const;
    void setParentFolder(LauncherFolderItem *parent);

    Q_INVOKABLE LauncherFolderItem *createFolder(int index, const QString &name);
    Q_INVOKABLE void destroyFolder();

    LauncherFolderItem *findContainer(QObject *item);

    QString directoryFile() const;
    void loadDirectoryFile(const QString &filename);
    void saveDirectoryFile();
    void clear();

signals:
    void titleChanged();
    void iconIdChanged();
    void isUpdatingChanged();
    void updatingProgressChanged();
    void parentFolderChanged();
    void directoryFileChanged();
    void saveNeeded();

private slots:
    void handleAdded(QObject*);
    void handleRemoved(QObject*);

private:
    QString m_title;
    QString m_iconId;
    QString m_directoryFile;
    QSharedPointer<MDesktopEntry> m_desktopEntry;
    QPointer<LauncherFolderItem> m_parentFolder;
};

#endif
