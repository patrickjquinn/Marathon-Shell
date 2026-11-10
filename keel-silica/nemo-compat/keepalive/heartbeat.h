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

#ifndef HEARTBEAT_H_
# define HEARTBEAT_H_

# include <QObject>
# include <QSocketNotifier>
# include <QTimer>

extern "C" {
# include <iphbd/libiphb.h>
}

class Heartbeat : public QObject
{
    Q_OBJECT

public:
    explicit Heartbeat(QObject *parent = 0);
    virtual ~Heartbeat();

    void setInterval(int global_slot);
    void setInterval(int mindelay, int maxdelay);

    void start();
    void start(int global_slot);
    void start(int mindelay, int maxdelay);

    void stop();

    void disconnect();

Q_SIGNALS:
    void timeout();

private Q_SLOTS:
    void retryConnect();
    void wakeup(int fd);
    void wait();

private:
    int              m_min_delay;
    int              m_max_delay;

    bool             m_started;
    bool             m_waiting;

    iphb_t           m_iphb_handle;
    QSocketNotifier *m_wakeup_notifier;
    QTimer          *m_connect_timer;

private:
    Q_DISABLE_COPY(Heartbeat)
    bool tryConnect();
    void connect();

};
#endif /* HEARTBEAT_H_ */
