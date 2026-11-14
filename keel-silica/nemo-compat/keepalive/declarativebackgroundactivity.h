// SPDX-FileCopyrightText: 2014 - 2018 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2018 Jolla Ltd.
**
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Valerio Valerio <valerio.valerio@jollamobile.com>
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
** Author: Aaron McCarthy <aaron.mccarthy@jollamobile.com>
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

#ifndef DECLARATIVEBACKGROUNDACTIVITY_H_
# define DECLARATIVEBACKGROUNDACTIVITY_H_

# include <QObject>
# include <QBasicTimer>
# include <qqml.h>
# include "backgroundactivity.h"

class DeclarativeKeepAlive : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    DeclarativeKeepAlive(QObject *parent = 0);

    bool enabled() const;
    void setEnabled(bool enabled);

Q_SIGNALS:
    void enabledChanged();

private:
    bool mEnabled;
    BackgroundActivity *mBackgroundActivity;
};

QML_DECLARE_TYPE(DeclarativeKeepAlive)


class DeclarativeBackgroundJob : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_PROPERTY(bool triggeredOnEnable READ triggeredOnEnable WRITE setTriggeredOnEnable NOTIFY triggeredOnEnableChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(Frequency frequency READ frequency WRITE setFrequency NOTIFY frequencyChanged)
    Q_PROPERTY(int minimumWait READ minimumWait WRITE setMinimumWait NOTIFY minimumWaitChanged)
    Q_PROPERTY(int maximumWait READ maximumWait WRITE setMaximumWait NOTIFY maximumWaitChanged)
    Q_ENUMS(Frequency)

    Q_INTERFACES(QQmlParserStatus)

public:
    DeclarativeBackgroundJob(QObject *parent = 0);

    enum Frequency {
        Range             = BackgroundActivity::Range,
        ThirtySeconds     = BackgroundActivity::ThirtySeconds,
        TwoAndHalfMinutes = BackgroundActivity::TwoAndHalfMinutes,
        FiveMinutes       = BackgroundActivity::FiveMinutes,
        TenMinutes        = BackgroundActivity::TenMinutes,
        FifteenMinutes    = BackgroundActivity::FifteenMinutes,
        ThirtyMinutes     = BackgroundActivity::ThirtyMinutes,
        OneHour           = BackgroundActivity::OneHour,
        TwoHours          = BackgroundActivity::TwoHours,
        FourHours         = BackgroundActivity::FourHours,
        EightHours        = BackgroundActivity::EightHours,
        TenHours          = BackgroundActivity::TenHours,
        TwelveHours       = BackgroundActivity::TwelveHours,
        TwentyFourHours   = BackgroundActivity::TwentyFourHours,
        MaximumFrequency  = BackgroundActivity::MaximumFrequency
    };

    void setTriggeredOnEnable(bool triggeredOnEnable);
    bool triggeredOnEnable() const;

    bool enabled() const;
    void setEnabled(bool enabled);

    bool running() const;

    Frequency frequency() const;
    void setFrequency(Frequency frequency);

    int minimumWait() const;
    void setMinimumWait(int minimum);

    int maximumWait() const;
    void setMaximumWait(int maximum);

    QString id() const;

    void classBegin();
    void componentComplete();

Q_SIGNALS:
    void triggeredOnEnableChanged();
    void enabledChanged();
    void runningChanged();
    void frequencyChanged();
    void minimumWaitChanged();
    void maximumWaitChanged();

Q_SIGNALS:
    void triggered();

public Q_SLOTS:
    void begin();
    void finished();

protected:
    bool event(QEvent *event);

private Q_SLOTS:
    void stateChanged();
    void update();

private:
    void scheduleUpdate();

    BackgroundActivity *mBackgroundActivity;
    QBasicTimer mTimer;
    Frequency mFrequency;
    BackgroundActivity::State mPreviousState;
    int mMinimum;
    int mMaximum;
    bool mTriggeredOnEnable;
    bool mEnabled;
    bool mComplete;
};

QML_DECLARE_TYPE(DeclarativeBackgroundJob)


#endif /* DECLARATIVEBACKGROUNDACTIVITY_H_ */
