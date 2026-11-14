// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
**
** All rights reserved.
**
** This file is part of nemo-keepalive package.
**
** You may use this file under the terms of the GNU Lesser General
** Public License version 2.1 as published by the Free Software Foundation
** and appearing in the file license.lgpl included in the packaging
** of this file.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file license.lgpl included in the packaging
** of this file.
**
** This library is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
** Lesser General Public License for more details.
**
****************************************************************************************/

#ifndef DISPLAYBLANKING_H_
# define DISPLAYBLANKING_H_

# include <QObject>

class DisplayBlankingPrivate;

class DisplayBlanking: public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool preventBlanking READ preventBlanking WRITE setPreventBlanking NOTIFY preventBlankingChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_ENUMS(Status)

public:
    explicit DisplayBlanking(QObject *parent = 0);
    virtual ~DisplayBlanking();

    enum Status {
        Unknown,
        Off,
        Dimmed,
        On
    };

    bool preventBlanking() const;
    Status status() const;

public Q_SLOTS:
    void setPreventBlanking(bool);

Q_SIGNALS:
    void preventBlankingChanged();
    void statusChanged();

private:
    Q_DISABLE_COPY(DisplayBlanking)
    DisplayBlankingPrivate *priv;
};

#endif // DISPLAYBLANKING_H_
