// SPDX-FileCopyrightText: 2016-2019 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (c) 2016-2019 Jolla Ltd.
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

#include "qmcepowersavemode.h"
#include "qmceproxy.h"

// ==========================================================================
// QMcePowerSaveMode::Private
// ==========================================================================

class QMcePowerSaveMode::Private : public QObject {
    Q_OBJECT
public:
    Private(QMcePowerSaveMode *aParent);

    bool valid() const;
    bool value() const;

private:
    void queryValue();
    void setValid(bool valid);

private Q_SLOTS:
    void onNameOwnerChanged();
    void onQueryFinished(QDBusPendingCallWatcher *aWatcher);
    void updateValue(bool active);

private:
    QMcePowerSaveMode* iParent;
    QSharedPointer<QMceProxy> iProxy;
    bool iValid;
    bool iValue;
};

QMcePowerSaveMode::Private::Private(QMcePowerSaveMode* aParent)
    : QObject(aParent)
    , iParent(aParent)
    , iProxy(QMceProxy::instance())
    , iValid(false)
    , iValue(false)
{
    QObject::connect(iProxy->signalProxy(),
                     &QMceSignalProxy::psm_state_ind,
                     this,
                     &QMcePowerSaveMode::Private::updateValue);
    QObject::connect(iProxy.data(),
                     &QMceProxy::nameOwnerChanged,
                     this,
                     &QMcePowerSaveMode::Private::onNameOwnerChanged);
    onNameOwnerChanged();
}

bool QMcePowerSaveMode::Private::valid() const
{
    return iValid;
}

void QMcePowerSaveMode::Private::setValid(bool valid)
{
    if (iValid != valid) {
        iValid = valid;
        Q_EMIT iParent->validChanged();
    }
}

bool QMcePowerSaveMode::Private::value() const
{
    return iValue;
}

void QMcePowerSaveMode::Private::updateValue(bool active)
{
    if (iValue != active) {
        iValue = active;
        Q_EMIT iParent->activeChanged();
    }
}

void QMcePowerSaveMode::Private::queryValue()
{
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        iProxy->requestProxy()->get_psm_state(), this);
    QObject::connect(watcher,
                     &QDBusPendingCallWatcher::finished,
                     this,
                     &QMcePowerSaveMode::Private::onQueryFinished);
}

void QMcePowerSaveMode::Private::onQueryFinished(QDBusPendingCallWatcher* aWatcher)
{
    QDBusPendingReply<bool> reply(*aWatcher);
    if (!reply.isError()) {
        updateValue(reply.value());
        setValid(true);
    }
    aWatcher->deleteLater();
}

void QMcePowerSaveMode::Private::onNameOwnerChanged()
{
    if (iProxy->hasNameOwner()) {
        queryValue();
    } else {
        setValid(false);
    }
}

// ==========================================================================
// QMcePowerSaveMode
// ==========================================================================

QMcePowerSaveMode::QMcePowerSaveMode(QObject* aParent)
    : QObject(aParent)
    , iPrivate(new Private(this))
{
}

bool QMcePowerSaveMode::valid() const
{
    return iPrivate->valid();
}

bool QMcePowerSaveMode::active() const
{
    return iPrivate->value();
}

#include "qmcepowersavemode.moc"
