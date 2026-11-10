// SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
/****************************************************************************************
**
** Copyright (C) 2014 - 2023 Jolla Ltd.
**
** Author: Martin Jones <martin.jones@jollamobile.com>
** Author: Valerio Valerio <valerio.valerio@jollamobile.com>
** Author: Simo Piiroinen <simo.piiroinen@jollamobile.com>
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

#include "declarativebackgroundactivity.h"
#include <QDebug>

/*!
    \qmltype KeepAlive
    \inqmlmodule Nemo.KeepAlive
    \brief Provides means for preventing device suspend

    Provides simple abstraction for D-Bus mechanisms that are required
    for preventing suspend (when allowed by lower level policies).

*/

/*!
    \qmlproperty bool KeepAlive::enabled
    \brief Sets the desired suspend prevention mode

    When set to true, prevents system from suspending.

    enabled defaults to false.
*/

DeclarativeKeepAlive::DeclarativeKeepAlive(QObject *parent)
    : QObject(parent), mEnabled(false), mBackgroundActivity(0)
{
}

bool DeclarativeKeepAlive::enabled() const
{
    return mEnabled;
}

void DeclarativeKeepAlive::setEnabled(bool enabled)
{
    if (enabled != mEnabled) {
        if (!mBackgroundActivity)
            mBackgroundActivity = new BackgroundActivity(this);
        mEnabled = enabled;
        if (mEnabled)
            mBackgroundActivity->run();
        else
            mBackgroundActivity->stop();
        Q_EMIT enabledChanged();
    }
}

//==============================

/*!
    \qmltype BackgroundJob
    \inqmlmodule Nemo.KeepAlive
    \brief Provides means for waking up from / preventing suspend

    Provides abstraction for scheduling tasks that can wake the system
    from suspended state and prevent system from suspending while
    handling the wakeup.

*/

/*!
    \qmlproperty bool BackgroundJob::triggeredOnEnable

    This property serves similar purpose as triggeredOnStart in
    standard QML Timer objects: Setting triggeredOnEnable to
    true causes triggering immediately after enabling - which
    can be useful for example for establishing an initial state.

    triggeredOnEnable defaults to false.
*/

/*!
    \qmlproperty bool BackgroundJob::enabled

    If changed from false to true, starts the timer.

    If changed from true to false, stops the timer / ends suspend
    prevention.

    enabled defaults to false.
*/

/*!
    \qmlproperty bool BackgroundJob::running

    Returns true when the timer has been triggered (and the device
    is prevented from suspending).

*/

/*!
    \qmlproperty enumeration BackgroundJob::frequency

    Sets the desired wakeup frequency and starts the timer.

    Note that wakeups are aligned in system wide manner so that every
    timer that is scheduled to occur in the same frequency gets
    triggered simultaneously. Effectively this means that the first
    wakeup most likely happens earlier then the requested frequency
    would suggest.

    The frequence can be one of:
    \list
    \li BackgroundJob.ThirtySeconds
    \li BackgroundJob.TwoAndHalfMinutes
    \li BackgroundJob.FiveMinutes
    \li BackgroundJob.TenMinutes
    \li BackgroundJob.FifteenMinutes
    \li BackgroundJob.ThirtyMinutes
    \li BackgroundJob.OneHour - the default
    \li BackgroundJob.TwoHours
    \li BackgroundJob.FourHours
    \li BackgroundJob.EightHours
    \li BackgroundJob.TenHours
    \li BackgroundJob.TwelveHours
    \li BackgroundJob.TwentyFourHours
    \li BackgroundJob.MaximumFrequency
    \endlist

    Note that defining wakeup frequency is mutually exclusive
    with using wakeup range.

    \sa BackgroundJob::minimumWait
    \sa BackgroundJob::maximumWait
*/

/*!
    \qmlproperty int BackgroundJob::minimumWait

    Sets the desired minimum wait delay in seconds and starts the timer.

    \sa BackgroundJob::maximumWait
    \sa BackgroundJob::frequency

*/

/*!
    \qmlproperty int BackgroundJob::maximumWait

    Sets the desired maximum wait delay in seconds and starts the timer.

    \sa BackgroundJob::minimumWait
    \sa BackgroundJob::frequency

*/

/*!
    \qmlsignal BackgroundJob::triggered()

    This signal is emitted when timer wakeup occurs and system is
    prevented from suspending.

    In order to allow suspending again, the application must define
    onTriggered handler and make sure one of the following actions
    are taken after handling tasks related to the wakeup:

    \list
    \li set BackgroundJob::enabled property to false - to stop the timer
    \li call BackgroundJob::finished() method - to schedule the next
    wake up
    \endlist

*/

/*!
    \qmlmethod BackgroundJob::begin()

    If enabled property is true, switches BackgroundJob to running
    state and emits BackgroundJob::triggered() signal.
*/

/*!
    \qmlmethod BackgroundJob::finished()

    If enabled property is true, reschedules wake up timer and
    ends suspend prevention.
*/

DeclarativeBackgroundJob::DeclarativeBackgroundJob(QObject *parent)
    : QObject(parent), mBackgroundActivity(0), mFrequency(OneHour), mPreviousState(BackgroundActivity::Stopped)
    , mMinimum(0), mMaximum(0), mTriggeredOnEnable(false), mEnabled(false), mComplete(false)
{
    mBackgroundActivity = new BackgroundActivity(this);
    connect(mBackgroundActivity, SIGNAL(stateChanged()), this, SLOT(stateChanged()));
}

void DeclarativeBackgroundJob::setTriggeredOnEnable(bool triggeredOnEnable)
{
    if (triggeredOnEnable != mTriggeredOnEnable) {
        mTriggeredOnEnable = triggeredOnEnable;
        Q_EMIT triggeredOnEnableChanged();
        scheduleUpdate();
    }
}

bool DeclarativeBackgroundJob::triggeredOnEnable() const
{
    return mTriggeredOnEnable;
}

bool DeclarativeBackgroundJob::enabled() const
{
    return mEnabled;
}

void DeclarativeBackgroundJob::setEnabled(bool enabled)
{
    if (enabled != mEnabled) {
        mEnabled = enabled;
        Q_EMIT enabledChanged();
        scheduleUpdate();
    }
}

bool DeclarativeBackgroundJob::running() const
{
    return mBackgroundActivity->isRunning();
}

DeclarativeBackgroundJob::Frequency DeclarativeBackgroundJob::frequency() const
{
    return mFrequency;
}

void DeclarativeBackgroundJob::setFrequency(Frequency frequency)
{
    if (frequency != mFrequency) {
        mFrequency = frequency;
        Q_EMIT frequencyChanged();
        scheduleUpdate();
    }
}

int DeclarativeBackgroundJob::minimumWait() const
{
    return mMinimum;
}

void DeclarativeBackgroundJob::setMinimumWait(int minimum)
{
    if (minimum != mMinimum) {
        mMinimum = minimum;
        Q_EMIT minimumWaitChanged();
        scheduleUpdate();
    }
}

int DeclarativeBackgroundJob::maximumWait() const
{
    return mMaximum;
}

void DeclarativeBackgroundJob::setMaximumWait(int maximum)
{
    if (maximum != mMaximum) {
        mMaximum = maximum;
        Q_EMIT maximumWaitChanged();
        scheduleUpdate();
    }
}

QString DeclarativeBackgroundJob::id() const
{
    return mBackgroundActivity->id();
}

void DeclarativeBackgroundJob::begin()
{
    if (!mComplete || !mEnabled)
        return;

    mTimer.stop();
    mBackgroundActivity->setState(BackgroundActivity::Running);
}

void DeclarativeBackgroundJob::finished()
{
    if (!mComplete || !mEnabled)
        return;

    mTimer.stop();
    mBackgroundActivity->setState(BackgroundActivity::Waiting);
}

bool DeclarativeBackgroundJob::event(QEvent *event)
{
    if (event->type() == QEvent::Timer) {
        QTimerEvent *te = static_cast<QTimerEvent *>(event);
        if (te->timerId() == mTimer.timerId()) {
            mTimer.stop();
            update();
        }
    }

    return QObject::event(event);
}

void DeclarativeBackgroundJob::update()
{
    if (!mComplete)
        return;

    if (!mEnabled) {
        mBackgroundActivity->stop();
    } else {
        if (mFrequency == Range)
            mBackgroundActivity->setWakeupRange(mMinimum, mMaximum);
        else
            mBackgroundActivity->setWakeupFrequency(static_cast<BackgroundActivity::Frequency>(mFrequency));

        if (mBackgroundActivity->state() == BackgroundActivity::Running) {
            // Once Running state is entered, it should be left only when
            // finished() method is called / enabled property is set to false.
        } else if (mTriggeredOnEnable) {
            mBackgroundActivity->run();
        } else {
            mBackgroundActivity->wait();
        }
    }
}

void DeclarativeBackgroundJob::scheduleUpdate()
{
    mTimer.start(0, this);
}

void DeclarativeBackgroundJob::classBegin()
{
}

void DeclarativeBackgroundJob::stateChanged()
{
    if (mBackgroundActivity->isRunning()) {
        Q_EMIT triggered();
        Q_EMIT runningChanged();
    }

    if (mPreviousState == BackgroundActivity::Running)
        Q_EMIT runningChanged();

    mPreviousState = mBackgroundActivity->state();
}

void DeclarativeBackgroundJob::componentComplete()
{
    mComplete = true;
    update();
}
