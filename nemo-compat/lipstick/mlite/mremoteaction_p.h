// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only

/***************************************************************************
**
** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
** All rights reserved.
** Contact: Nokia Corporation (directui@nokia.com)
**
** This file is part of libmeegotouch.
**
** If you have questions regarding the use of this file, please contact
** Nokia at directui@nokia.com.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#ifndef MREMOTEACTION_P_H
#define MREMOTEACTION_P_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QVariant>
#include <QVector>

class MRemoteActionPrivate
{
public:
    MRemoteActionPrivate();
    virtual ~MRemoteActionPrivate();

    void trigger(bool wait);
    QString toString() const;

    //! The name of the D-Bus service to call
    QString serviceName;
    //! The path of the D-Bus object to call
    QString objectPath;
    //! The name of the D-Bus interface to call
    QString interface;
    //! The name of the D-Bus method to call
    QString methodName;
    //! The arguments of the D-Bus call
    QList<QVariant> arguments;
    bool keepPrivileges = false;
};

#endif
