// SPDX-FileCopyrightText: 2014 Jolla Ltd
// SPDX-License-Identifier: LGPL-2.1-only

// This file is part of lipstick, a QML desktop library
//
// Copyright (c) 2014 Jolla Ltd.
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

#ifndef LAUNCHERDBUS_H
#define LAUNCHERDBUS_H

#include <QObject>
#include <QDBusContext>

#include <QString>

#include "lipstickdbus.h"

class LauncherModel;

class LauncherDBus : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_DISABLE_COPY(LauncherDBus)
    Q_CLASSINFO("D-Bus Interface", LIPSTICK_DBUS_LAUNCHER_MODEL_INTERFACE)

public:
    LauncherDBus(LauncherModel *model = 0);
    ~LauncherDBus();

    void requestLaunch(QString packageName);

    void registerModel(LauncherModel *model);
    void deregisterModel(LauncherModel *model);

public slots:
    void updatingStarted(QString packageName, QString label, QString iconPath, QString desktopFile);
    void updatingProgress(QString packageName, int progress);
    void updatingFinished(QString packageName);
    void notifyLaunching(const QString &desktopFile);
    void cancelNotifyLaunching(const QString &desktopFile);

signals:
    void showUpdatingProgress(QString packageName);

private:
    QList<LauncherModel *> m_models;
};

#endif // LAUNCHERDBUS_H
