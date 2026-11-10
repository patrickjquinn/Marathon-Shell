// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Valerio Valerio <valerio.valerio@jollamobile.com>
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

#ifndef BACKGROUNDACTIVITY_P_H_
# define BACKGROUNDACTIVITY_P_H_

# include "backgroundactivity.h"
# include "heartbeat.h"
# include "mceiface.h"

class BackgroundActivityPrivate : public QObject
{
    Q_OBJECT

    friend class BackgroundActivity;

private:
    BackgroundActivityPrivate(const BackgroundActivityPrivate &that);
    explicit BackgroundActivityPrivate(BackgroundActivity *parent = 0);
    virtual ~BackgroundActivityPrivate();

    void startKeepalivePeriod();
    void stopKeepalivePeriod();

    void queryKeepalivePeriod();

    void setState(BackgroundActivity::State new_state);

    BackgroundActivity::State state() const;

    ComNokiaMceRequestInterface *mceInterface();

    BackgroundActivity::Frequency wakeupSlot() const;
    void wakeupRange(int &range_min, int &range_max) const;
    void setWakeup(BackgroundActivity::Frequency slot,
                   int range_min, int range_max);

    void setWakeupFrequency(BackgroundActivity::Frequency slot);
    void setWakeupRange(int range_min, int range_max);

    QString id() const;

private Q_SLOTS:
    void renewKeepalivePeriod();
    void keepalivePeriodReply(QDBusPendingCallWatcher *call);

private:
    BackgroundActivity::State m_state;
    BackgroundActivity::Frequency m_wakeup_freq;
    int m_wakeup_range_min;
    int m_wakeup_range_max;

    BackgroundActivity *pub;

    QString m_id;

    Heartbeat *m_heartbeat;

    bool    m_keepalive_queried;
    int     m_keepalive_period;
    QTimer *m_keepalive_timer;

    ComNokiaMceRequestInterface *m_mce_interface;
};

#endif /* BACKGROUNDACTIVITY_P_H_ */
