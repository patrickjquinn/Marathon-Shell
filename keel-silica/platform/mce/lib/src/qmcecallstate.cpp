// SPDX-FileCopyrightText: 2019 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (c) 2019 Jolla Ltd.
 * Copyright (c) 2019 Open Mobile Platform LLC.
 * Contact: Slava Monich <slava.monich@jolla.com>
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

#include "qmcecallstate.h"
#include "qmceproxy.h"

#include <mce/mode-names.h>

// ==========================================================================
// QMceCallState::Private
// ==========================================================================

class QMceCallState::Private : public QObject
{
    Q_OBJECT
public:
    Private(QMceCallState* aParent);

    bool valid() const;
    QMceCallState::State value() const;
    QMceCallState::Type type() const;

private:
    void queryValue();
    void setValid(bool valid);

private Q_SLOTS:
    void onNameOwnerChanged();
    void onQueryFinished(QDBusPendingCallWatcher *aWatcher);
    void updateValue(QString state, QString type);

private:
    QMceCallState* iParent;
    QSharedPointer<QMceProxy> iProxy;
    bool iValid;
    QMceCallState::State iValue;
    QMceCallState::Type iType;
};

QMceCallState::Private::Private(QMceCallState *aParent)
    : QObject(aParent)
    , iParent(aParent)
    , iProxy(QMceProxy::instance())
    , iValid(false)
    , iValue(None)
    , iType(Normal)
{
    QObject::connect(iProxy->signalProxy(),
                     &QMceSignalProxy::sig_call_state_ind,
                     this,
                     &QMceCallState::Private::updateValue);
    QObject::connect(iProxy.data(),
                     &QMceProxy::nameOwnerChanged,
                     this,
                     &QMceCallState::Private::onNameOwnerChanged);
    onNameOwnerChanged();
}

bool QMceCallState::Private::valid() const
{
    return iValid;
}

void QMceCallState::Private::setValid(bool valid)
{
    if (iValid != valid) {
        iValid = valid;
        Q_EMIT iParent->validChanged();
    }
}

QMceCallState::State QMceCallState::Private::value() const
{
    return iValue;
}

QMceCallState::Type QMceCallState::Private::type() const
{
    return iType;
}

void QMceCallState::Private::updateValue(QString stateName, QString typeName)
{
    bool valid = true;
    QMceCallState::State state = None;
    QMceCallState::Type type = Normal;

    if (stateName == QStringLiteral(MCE_CALL_STATE_NONE))
        state = None;
    else if (stateName == QStringLiteral(MCE_CALL_STATE_RINGING))
        state = Ringing;
    else if (stateName == QStringLiteral(MCE_CALL_STATE_ACTIVE))
        state = Active;
    else if (stateName == QStringLiteral(MCE_CALL_STATE_SERVICE))
        state = Service;
    else
        valid = false;

    if (typeName == QStringLiteral(MCE_NORMAL_CALL))
        type = Normal;
    else if (typeName == QStringLiteral(MCE_EMERGENCY_CALL))
        type = Emergency;
    else
        valid = false;

    if (valid) {
        if (iValue != state) {
            iValue = state;
            Q_EMIT iParent->stateChanged();
        }
        if (iType != type) {
            iType = type;
            Q_EMIT iParent->typeChanged();
        }
    }
    setValid(valid);
}

void QMceCallState::Private::queryValue()
{
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        iProxy->requestProxy()->get_call_state(), this);
    QObject::connect(watcher,
                     &QDBusPendingCallWatcher::finished,
                     this,
                     &QMceCallState::Private::onQueryFinished);
}

void QMceCallState::Private::onQueryFinished(QDBusPendingCallWatcher* aWatcher)
{
    QDBusPendingReply<QString, QString> reply(*aWatcher);
    if (!reply.isError()) {
        updateValue(reply.argumentAt<0>(), reply.argumentAt<1>());
    }
    aWatcher->deleteLater();
}

void QMceCallState::Private::onNameOwnerChanged()
{
    if (iProxy->hasNameOwner()) {
        queryValue();
    } else {
        setValid(false);
    }
}

// ==========================================================================
// QMceCallState
// ==========================================================================

QMceCallState::QMceCallState(QObject *aParent)
    : QObject(aParent)
    , iPrivate(new Private(this))
{
}

bool QMceCallState::valid() const
{
    return iPrivate->valid();
}

QMceCallState::State QMceCallState::state() const
{
    return iPrivate->value();
}

QMceCallState::Type QMceCallState::type() const
{
    return iPrivate->type();
}

#include "qmcecallstate.moc"
