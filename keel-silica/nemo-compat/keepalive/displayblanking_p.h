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

#ifndef DISPLAYBLANKING_P_H_
# define DISPLAYBLANKING_P_H_

# include "displayblanking.h"
# include "mceiface.h"

class QTimer;

class DisplayBlankingSingleton: public QObject
{
    Q_OBJECT

private:
    explicit DisplayBlankingSingleton();

public:
    static DisplayBlankingSingleton *instance();
    void releaseInstance();
    void attachPreventingObject(DisplayBlankingPrivate *object);
    void detachPreventingObject(DisplayBlankingPrivate *object);
    DisplayBlanking::Status displayStatus() const;
Q_SIGNALS:
    void displayStatusChanged();

private:
    Q_DISABLE_COPY(DisplayBlankingSingleton)
    QTimer *keepaliveTimer();
    void startKeepalive();
    void stopKeepalive();
    void evaluateKeepalive();

private Q_SLOTS:
    void renewKeepalive();
    void updateDisplayStatus(const QString &status);
    void getDisplayStatusComplete(QDBusPendingCallWatcher *call);
    void updatePreventMode(bool preventAllowed);
    void getPreventModeComplete(QDBusPendingCallWatcher *call);

private:
    static DisplayBlankingSingleton *s_instance;
    QSet<DisplayBlankingPrivate*> m_preventingObjects;
    int     m_renew_period;
    QTimer *m_renew_timer;
    bool    m_preventAllowed;
    DisplayBlanking::Status m_displayStatus;
    int m_instanceRefCount;

    ComNokiaMceRequestInterface *m_mce_req_iface;
    ComNokiaMceSignalInterface *m_mce_signal_iface;
};

class DisplayBlankingPrivate
{
public:
    explicit DisplayBlankingPrivate(DisplayBlanking *parent);
    ~DisplayBlankingPrivate();

    DisplayBlanking::Status displayStatus() const;

    bool preventBlanking() const;
    void setPreventBlanking(bool preventBlanking);

private:
    DisplayBlankingSingleton *m_singleton;
    DisplayBlanking *m_parent;
    bool m_preventBlanking;
};

#endif // DISPLAYBLANKING_P_H_
