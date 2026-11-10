// SPDX-FileCopyrightText: 2022 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (c) 2022 Jolla Ltd.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   1. Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *   2. Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *   3. Neither the name of Jolla Ltd nor the names of its contributors may
 *      be used to endorse or promote products derived from this software
 *      without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation
 * are those of the authors and should not be interpreted as representing
 * any official policies, either expressed or implied.
 */

#include "qmcechargingstate.h"
#include "qmceproxy.h"

#include <mce/mode-names.h>

// ==========================================================================
// QMceChargingState::Private
// ==========================================================================

class QMceChargingState::Private : public QObject
{
    Q_OBJECT
public:
    Private(QMceChargingState *aParent);

private:
    void queryValue();
    void setValid(bool valid);

private Q_SLOTS:
    void onNameOwnerChanged();
    void onQueryFinished(QDBusPendingCallWatcher *aWatcher);
    void updateValue(QString state);

private:
    QMceChargingState* iParent;
    QSharedPointer<QMceProxy> iProxy;

public:
    bool iValid;
    QMceChargingState::State iValue;
};

QMceChargingState::Private::Private(QMceChargingState *aParent)
    : QObject(aParent)
    , iParent(aParent)
    , iProxy(QMceProxy::instance())
    , iValid(false)
    , iValue(Unknown)
{
    QObject::connect(iProxy->signalProxy(),
                     &QMceSignalProxy::charging_state_ind,
                     this,
                     &QMceChargingState::Private::updateValue);
    QObject::connect(iProxy.data(),
                     &QMceProxy::nameOwnerChanged,
                     this,
                     &QMceChargingState::Private::onNameOwnerChanged);
    onNameOwnerChanged();
}

void QMceChargingState::Private::setValid(bool valid)
{
    if (iValid != valid) {
        iValid = valid;
        Q_EMIT iParent->validChanged();
    }
}

void QMceChargingState::Private::updateValue(QString state)
{
    QMceChargingState::State value = Unknown;

    if (state == QStringLiteral(MCE_CHARGING_STATE_ENABLED)) {
        value = Enabled;
    } else if (state == QStringLiteral(MCE_CHARGING_STATE_DISABLED)) {
        value = Disabled;
    }

    if (iValue != value) {
        iValue = value;
        Q_EMIT iParent->stateChanged();
    }
    setValid(true);
}

void QMceChargingState::Private::queryValue()
{
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        iProxy->requestProxy()->get_charging_state(), this);
    QObject::connect(watcher,
                     &QDBusPendingCallWatcher::finished,
                     this,
                     &QMceChargingState::Private::onQueryFinished);
}

void QMceChargingState::Private::onQueryFinished(QDBusPendingCallWatcher* aWatcher)
{
    QDBusPendingReply<QString> reply(*aWatcher);
    if (!reply.isError()) {
        updateValue(reply.value());
    }
    aWatcher->deleteLater();
}

void QMceChargingState::Private::onNameOwnerChanged()
{
    if (iProxy->hasNameOwner()) {
        queryValue();
    } else {
        setValid(false);
    }
}

// ==========================================================================
// QMceChargingState
// ==========================================================================

QMceChargingState::QMceChargingState(QObject *aParent)
    : QObject(aParent)
    , iPrivate(new Private(this))
{
}

bool QMceChargingState::valid() const
{
    return iPrivate->iValid;
}

QMceChargingState::State QMceChargingState::state() const
{
    return iPrivate->iValue;
}

#include "qmcechargingstate.moc"
