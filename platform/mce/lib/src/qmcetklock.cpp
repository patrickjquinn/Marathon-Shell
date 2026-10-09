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

#include "qmcetklock.h"
#include "qmceproxy.h"

#include "mce/mode-names.h"

class QMceTkLock::Private : public QObject {
    Q_OBJECT

public:
    Private(QMceTkLock* aParent);

    void queryMode();

private Q_SLOTS:
    void onNameOwnerChanged();
    void onQueryFinished(QDBusPendingCallWatcher* aWatcher);
    void updateMode(QString aStatus);

public:
    QMceTkLock* iParent;
    QSharedPointer<QMceProxy> iProxy;
    bool iValid;
    bool iLocked;
    Mode iMode;
};

QMceTkLock::Private::Private(QMceTkLock *aParent)
    : QObject(aParent)
    , iParent(aParent)
    , iProxy(QMceProxy::instance())
    , iValid(false)
    , iLocked(true)
    , iMode(Locked)
{
    QObject::connect(iProxy->signalProxy(),
                     &QMceSignalProxy::tklock_mode_ind,
                     this,
                     &QMceTkLock::Private::updateMode);
    QObject::connect(iProxy.data(),
                     &QMceProxy::nameOwnerChanged,
                     this,
                     &QMceTkLock::Private::onNameOwnerChanged);
    onNameOwnerChanged();
}

void QMceTkLock::Private::queryMode()
{
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(
        iProxy->requestProxy()->get_tklock_mode(), this);
    QObject::connect(watcher,
                     &QDBusPendingCallWatcher::finished,
                     this,
                     &QMceTkLock::Private::onQueryFinished);
}

void QMceTkLock::Private::updateMode(QString aMode)
{
    static const struct tklock_mode {
        QString name;
        Mode mode;
        bool locked;
    } modes [] = {
        /* Most commonly used modes first */
        { MCE_TK_LOCKED, Locked, true },
        { MCE_TK_UNLOCKED, Unlocked, false },
        { MCE_TK_SILENT_LOCKED, SilentLocked, true },
        { MCE_TK_LOCKED_DIM, LockedDim, true },
        { MCE_TK_LOCKED_DELAY, LockedDelay, true },
        { MCE_TK_SILENT_LOCKED_DIM, SilentLockedDim, true },
        { MCE_TK_SILENT_UNLOCKED, SilentUnlocked, false }
    };
    const Mode prevMode = iMode;
    const bool prevLocked = iLocked;
    for (uint i=0; i<sizeof(modes)/sizeof(modes[0]); i++) {
        if (aMode == modes[i].name) {
            iMode = modes[i].mode;
            iLocked = modes[i].locked;
            break;
        }
    }
    if (iMode != prevMode) {
        Q_EMIT iParent->modeChanged();
    }
    if (iLocked != prevLocked) {
        Q_EMIT iParent->lockedChanged();
    }
}

void QMceTkLock::Private::onQueryFinished(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<QString> reply(*aWatcher);
    if (!reply.isError()) {
        updateMode(reply.value());
        if (!iValid) {
            iValid = true;
            Q_EMIT iParent->validChanged();
        }
    }
    aWatcher->deleteLater();
}

void QMceTkLock::Private::onNameOwnerChanged()
{
    if (iProxy->hasNameOwner()) {
        queryMode();
    } else {
        if (iValid) {
            iValid = false;
            Q_EMIT iParent->validChanged();
        }
    }
}

// ==========================================================================
// QMceTkLock
// ==========================================================================

QMceTkLock::QMceTkLock(QObject *aParent)
    : QObject(aParent)
    , iPrivate(new Private(this))
{
}

bool QMceTkLock::valid() const
{
    return iPrivate->iValid;
}

bool QMceTkLock::locked() const
{
    return iPrivate->iLocked;
}

QMceTkLock::Mode QMceTkLock::mode() const
{
    return iPrivate->iMode;
}

#include "qmcetklock.moc"
