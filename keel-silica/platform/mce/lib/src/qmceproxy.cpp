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

#include "qmceproxy.h"

#include "mce/dbus-names.h"

class QMceProxy::Private : public QObject
{
    Q_OBJECT

public:
    Private(QMceProxy *aParent);

    QMceRequestProxy* requestProxy();
    QMceSignalProxy* signalProxy();

private Q_SLOTS:
    void onServiceOwnerChanged(QString serviceName, QString oldOwner, QString newOwner);
    void onGetNameOwnerReply(QDBusPendingCallWatcher *aWatcher);

public:
    QMceProxy* iParent;

    /* Whether we have received a name owner changed signal,
     * or reply to initial asynchronous name owner query.
     */
    bool iNameOwnerIsKnown;

    /* Private name of client owning well known mce
     * service name, or empty string when there is no
     * owner / owner is not yet known.
     */
    QString iNameOwner;

private:
    void setNameOwner(const QString &newOwner);
    QDBusConnection iBus;
    QString iService;
    QMceRequestProxy* iRequestProxy;
    QMceSignalProxy* iSignalProxy;
};

QMceProxy::Private::Private(QMceProxy* aParent)
    : QObject(aParent)
    , iParent(aParent)
    , iNameOwnerIsKnown(false)
    , iNameOwner()
    , iBus(QDBusConnection::systemBus())
    , iService(MCE_SERVICE)
    , iRequestProxy(nullptr)
    , iSignalProxy(nullptr)
{
    /* Start tracking name owner changes */
    QDBusServiceWatcher *serviceWatcher = new QDBusServiceWatcher(iService, iBus,
        QDBusServiceWatcher::WatchForOwnerChange, this);
    QObject::connect(serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged,
                     this, &QMceProxy::Private::onServiceOwnerChanged);
    /* Start async query to get the initial name owner */
    QDBusPendingCall pendingCall = iBus.interface()->asyncCall(QLatin1String("GetNameOwner"), iService);
    QDBusPendingCallWatcher *pendingCallWatcher = new QDBusPendingCallWatcher(pendingCall, this);
    QObject::connect(pendingCallWatcher, &QDBusPendingCallWatcher::finished,
                     this, &QMceProxy::Private::onGetNameOwnerReply);
}

void QMceProxy::Private::setNameOwner(const QString &newOwner)
{
    if (iNameOwner != newOwner) {
        iNameOwner = newOwner;
        Q_EMIT iParent->nameOwnerChanged();
    }
    if (!iNameOwnerIsKnown) {
        iNameOwnerIsKnown = true;
        Q_EMIT iParent->nameOwnerIsKnownChanged();
    }
}

QMceRequestProxy* QMceProxy::Private::requestProxy()
{
    if (!iRequestProxy) {
        iRequestProxy = new QMceRequestProxy(iService,
            MCE_REQUEST_PATH, iBus, this);
    }
    return iRequestProxy;
}

QMceSignalProxy* QMceProxy::Private::signalProxy()
{
    if (!iSignalProxy) {
        iSignalProxy = new QMceSignalProxy(iService,
            MCE_SIGNAL_PATH, iBus, this);
    }
    return iSignalProxy;
}

void QMceProxy::Private::onServiceOwnerChanged(QString serviceName, QString oldOwner, QString newOwner)
{
    if (serviceName == iService)
        setNameOwner(newOwner);
}

void QMceProxy::Private::onGetNameOwnerReply(QDBusPendingCallWatcher *aWatcher)
{
    QDBusPendingReply<QString> reply = *aWatcher;
    if (!reply.isError()) {
        const QString owner(reply.value());
        setNameOwner(owner);
    }
    aWatcher->deleteLater();
}

// ==========================================================================
// QMceProxy
// ==========================================================================

QMceProxy::QMceProxy()
    : iPrivate(new Private(this))
{
}

bool QMceProxy::nameOwnerIsKnown() const
{
    return iPrivate->iNameOwnerIsKnown;
}

QString QMceProxy::nameOwner() const
{
    return iPrivate->iNameOwner;
}

bool QMceProxy::hasNameOwner() const
{
    return !iPrivate->iNameOwner.isEmpty();
}

QMceRequestProxy* QMceProxy::requestProxy()
{
    return iPrivate->requestProxy();
}

QMceSignalProxy* QMceProxy::signalProxy()
{
    return iPrivate->signalProxy();
}

QSharedPointer<QMceProxy> QMceProxy::instance()
{
    static QWeakPointer<QMceProxy> sSharedInstance;
    QSharedPointer<QMceProxy> ref = sSharedInstance;
    if (ref.isNull()) {
        ref = QSharedPointer<QMceProxy>(new QMceProxy, &QObject::deleteLater);
        sSharedInstance = ref;
    }
    return ref;
}

#include "qmceproxy.moc"
